terraform {
  required_providers {
    aws    = { source = "hashicorp/aws" }
    random = { source = "hashicorp/random" }
  }
}

# Aurora Serverless v2 PostgreSQL backing the gateway's device-grant store and
# (with spend limits enabled) its spend-tracking tables.
# == ClaudeGatewayDatabaseStack.
#
# The CDK sample let RDS manage its own credentials and used a Lambda custom
# resource to compose the postgres_url without ever exposing the password to
# the template. Terraform composes the URL natively instead: we generate the
# master password with random_password and build the connection string
# directly. The password therefore lives in Terraform state -- which is why
# backend.tf requires an encrypted remote backend. This removes an entire
# Lambda + custom-resource provider from the deployment.

resource "aws_db_subnet_group" "this" {
  name_prefix = "${var.name_prefix}-db-"
  description = "Private subnets for the Claude gateway Aurora cluster"
  subnet_ids  = var.private_subnet_ids

  lifecycle { create_before_destroy = true }
}

resource "random_password" "master" {
  length  = 32
  special = false # keep the password URL-safe for the postgres_url connection string
}

resource "aws_rds_cluster" "this" {
  cluster_identifier = "${var.name_prefix}-aurora"
  engine             = "aurora-postgresql"
  engine_mode        = "provisioned" # required for Serverless v2 scaling config
  engine_version     = var.engine_version

  database_name   = var.database_name
  master_username = "gateway"
  master_password = random_password.master.result

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [var.database_security_group]

  storage_encrypted = true

  serverlessv2_scaling_configuration {
    min_capacity             = var.min_capacity
    max_capacity             = var.max_capacity
    seconds_until_auto_pause = var.seconds_until_auto_pause
  }

  # Reference/sample defaults: torn down easily. For production set
  # deletion_protection = true and skip_final_snapshot = false with a
  # final_snapshot_identifier.
  deletion_protection = false
  skip_final_snapshot = true

  lifecycle {
    ignore_changes = [master_password] # rotate out of band, not on every apply
  }
}

resource "aws_rds_cluster_instance" "writer" {
  identifier         = "${var.name_prefix}-aurora-writer"
  cluster_identifier = aws_rds_cluster.this.id
  instance_class     = "db.serverless"
  engine             = aws_rds_cluster.this.engine
  engine_version     = aws_rds_cluster.this.engine_version
}

# The single connection-string secret the gateway config reads as
# ${GATEWAY_POSTGRES_URL}. sslmode=require matches the CDK sample.
resource "aws_secretsmanager_secret" "postgres_url" {
  name_prefix = "${var.name_prefix}-postgres-url-"
  description = "Full Postgres connection URL for the Claude apps gateway store."
}

resource "aws_secretsmanager_secret_version" "postgres_url" {
  secret_id = aws_secretsmanager_secret.postgres_url.id
  secret_string = format(
    "postgresql://%s:%s@%s:%d/%s?sslmode=require",
    "gateway",
    urlencode(random_password.master.result),
    aws_rds_cluster.this.endpoint,
    aws_rds_cluster.this.port,
    var.database_name,
  )
}
