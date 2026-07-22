terraform {
  required_providers {
    aws   = { source = "hashicorp/aws" }
    tls   = { source = "hashicorp/tls" }
    local = { source = "hashicorp/local" }
  }
}

# A self-service AWS Client VPN endpoint (== ClaudeGatewayVpnStack) using
# mutual TLS, so a stranger deploying this repo has a real way to reach the
# gateway's private endpoint with no manual console work.
#
# The CDK generated the whole CA/server/client cert chain inside two Lambda
# custom resources and assembled the .ovpn by hand. Terraform does all of it
# natively with the tls provider + a template -- no Lambdas.
#
# Split-tunnel is deliberate: full-tunnel would route the developer's browser
# redirect to the public IdP sign-in page through the VPN (where only the VPC
# CIDR is authorized), silently breaking sign-in. Split-tunnel routes only
# VPC-bound traffic through the tunnel.

########################################
# Certificate chain (CA -> server, client)
########################################

resource "tls_private_key" "ca" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_self_signed_cert" "ca" {
  private_key_pem = tls_private_key.ca.private_key_pem

  subject {
    common_name  = "${var.name_prefix}-vpn-ca"
    organization = "Claude Apps Gateway"
  }

  is_ca_certificate     = true
  validity_period_hours = 87600 # 10 years
  allowed_uses          = ["cert_signing", "crl_signing", "key_encipherment", "digital_signature"]
}

# --- Server cert ---
resource "tls_private_key" "server" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "server" {
  private_key_pem = tls_private_key.server.private_key_pem
  subject {
    common_name  = "${var.name_prefix}-vpn-server"
    organization = "Claude Apps Gateway"
  }
}

resource "tls_locally_signed_cert" "server" {
  cert_request_pem   = tls_cert_request.server.cert_request_pem
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca.cert_pem

  validity_period_hours = 43800 # 5 years
  allowed_uses          = ["key_encipherment", "digital_signature", "server_auth"]
}

# --- Client cert ---
resource "tls_private_key" "client" {
  algorithm = "RSA"
  rsa_bits  = 2048
}

resource "tls_cert_request" "client" {
  private_key_pem = tls_private_key.client.private_key_pem
  subject {
    common_name  = "${var.name_prefix}-vpn-client"
    organization = "Claude Apps Gateway"
  }
}

resource "tls_locally_signed_cert" "client" {
  cert_request_pem   = tls_cert_request.client.cert_request_pem
  ca_private_key_pem = tls_private_key.ca.private_key_pem
  ca_cert_pem        = tls_self_signed_cert.ca.cert_pem

  validity_period_hours = 43800
  allowed_uses          = ["key_encipherment", "digital_signature", "client_auth"]
}

########################################
# ACM imports
########################################

resource "aws_acm_certificate" "server" {
  private_key       = tls_private_key.server.private_key_pem
  certificate_body  = tls_locally_signed_cert.server.cert_pem
  certificate_chain = tls_self_signed_cert.ca.cert_pem
  tags              = { Name = "${var.name_prefix}-vpn-server" }
}

resource "aws_acm_certificate" "client" {
  private_key       = tls_private_key.client.private_key_pem
  certificate_body  = tls_locally_signed_cert.client.cert_pem
  certificate_chain = tls_self_signed_cert.ca.cert_pem
  tags              = { Name = "${var.name_prefix}-vpn-client" }
}

########################################
# Client VPN endpoint
########################################

resource "aws_cloudwatch_log_group" "vpn" {
  name_prefix       = "/vpn/${var.name_prefix}-"
  retention_in_days = 14
}

resource "aws_cloudwatch_log_stream" "vpn" {
  name           = "connections"
  log_group_name = aws_cloudwatch_log_group.vpn.name
}

resource "aws_ec2_client_vpn_endpoint" "this" {
  description            = "Claude apps gateway self-service Client VPN (mutual TLS)"
  server_certificate_arn = aws_acm_certificate.server.arn
  client_cidr_block      = var.client_cidr
  split_tunnel           = true
  transport_protocol     = "udp"
  vpc_id                 = var.vpc_id

  authentication_options {
    type                       = "certificate-authentication"
    root_certificate_chain_arn = aws_acm_certificate.client.arn
  }

  connection_log_options {
    enabled               = true
    cloudwatch_log_group  = aws_cloudwatch_log_group.vpn.name
    cloudwatch_log_stream = aws_cloudwatch_log_stream.vpn.name
  }

  tags = { Name = "${var.name_prefix}-vpn" }
}

resource "aws_ec2_client_vpn_network_association" "this" {
  count                  = length(var.private_subnet_ids)
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.this.id
  subnet_id              = var.private_subnet_ids[count.index]
}

# Target network associations do not implicitly authorize traffic; authorize
# connected clients to reach the VPC CIDR explicitly.
resource "aws_ec2_client_vpn_authorization_rule" "vpc" {
  client_vpn_endpoint_id = aws_ec2_client_vpn_endpoint.this.id
  target_network_cidr    = var.vpc_cidr
  authorize_all_groups   = true

  depends_on = [aws_ec2_client_vpn_network_association.this]
}

########################################
# .ovpn profile
########################################

locals {
  # AWS Client VPN endpoints have a deterministic DNS name derived from the
  # endpoint id. remote-random-hostname (in the template) prepends a random
  # label to avoid DNS caching, per AWS's own generated configs.
  endpoint_dns = "${aws_ec2_client_vpn_endpoint.this.id}.prod.clientvpn.${var.region}.amazonaws.com"

  ovpn_profile = templatefile("${path.module}/templates/client-config.ovpn.tftpl", {
    endpoint_dns = local.endpoint_dns
    ca_cert      = tls_self_signed_cert.ca.cert_pem
    client_cert  = tls_locally_signed_cert.client.cert_pem
    client_key   = tls_private_key.client.private_key_pem
  })
}

resource "aws_secretsmanager_secret" "client_profile" {
  name_prefix = "${var.name_prefix}-vpn-profile-"
  description = "Ready-to-import .ovpn profile and cert chain for the Claude gateway Client VPN."
}

resource "aws_secretsmanager_secret_version" "client_profile" {
  secret_id = aws_secretsmanager_secret.client_profile.id
  secret_string = jsonencode({
    ovpnProfile = local.ovpn_profile
    caCert      = tls_self_signed_cert.ca.cert_pem
    serverCert  = tls_locally_signed_cert.server.cert_pem
    clientCert  = tls_locally_signed_cert.client.cert_pem
  })
}

resource "local_file" "ovpn" {
  count           = var.write_local_profile ? 1 : 0
  filename        = "${path.root}/${var.name_prefix}-vpn.ovpn"
  content         = local.ovpn_profile
  file_permission = "0600"
}
