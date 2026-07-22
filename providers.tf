provider "aws" {
  region = var.aws_region

  default_tags {
    tags = merge(
      {
        Project   = "claude-apps-gateway"
        ManagedBy = "terraform"
      },
      var.tags,
    )
  }
}

# The awscc provider needs its own region/credentials block. It reads the
# same shared config/credentials as the aws provider by default; region is
# pinned explicitly so both providers always target the same account/region.
provider "awscc" {
  region = var.aws_region
}
