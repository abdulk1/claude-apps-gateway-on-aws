terraform {
  required_version = ">= 1.9"

  required_providers {
    # Standard AWS provider for everything that has a first-class resource.
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }

    # AWS Cloud Control (awscc) provider. Used for ECS Express Mode
    # (aws_ecs_express_gateway_service has no equivalent in the classic aws
    # provider yet -- the awscc provider auto-generates resources from the
    # CloudFormation registry, so brand-new resource types like
    # AWS::ECS::ExpressGatewayService are reachable from Terraform here first).
    # See modules/gateway and docs/differences-from-cdk-sample.md.
    awscc = {
      source  = "hashicorp/awscc"
      version = "~> 1.0"
    }

    # Generates the Aurora master password locally so we can compose the
    # gateway's postgres_url connection string in Terraform, replacing the
    # CDK sample's Lambda-backed "URL combiner" custom resource entirely.
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }

    # Generates the Client VPN mutual-TLS certificate chain (CA + server +
    # client) natively, replacing the CDK sample's Lambda-backed
    # vpn-cert-generator + vpn-profile-assembler custom resources.
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }

    # Zips the container build context for upload to CodeBuild.
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.4"
    }

    # Writes the rendered .ovpn client profile to disk for convenience.
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}
