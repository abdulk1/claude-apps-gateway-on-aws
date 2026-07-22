config {
  call_module_type = "all"
}

plugin "terraform" {
  enabled = true
  preset  = "recommended"
}

# Local child modules declare required_providers with `source` only; the ROOT
# module owns version pinning (the recommended pattern for in-repo modules).
# Disable the version-constraint rule so that intentional pattern doesn't fail
# lint. `terraform validate` still catches undeclared providers.
rule "terraform_required_providers" {
  enabled = false
}

plugin "aws" {
  enabled = true
  version = "0.42.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
