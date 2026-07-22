# Convenience targets for the Claude Apps Gateway Terraform.
# `make help` lists them.

TF ?= terraform

.DEFAULT_GOAL := help

.PHONY: help
help: ## List targets
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
	  | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-22s\033[0m %s\n", $$1, $$2}'

.PHONY: fmt
fmt: ## terraform fmt (recursive)
	$(TF) fmt -recursive

.PHONY: fmt-check
fmt-check: ## Check formatting without writing
	$(TF) fmt -recursive -check

.PHONY: init
init: ## terraform init
	$(TF) init

.PHONY: validate
validate: ## terraform validate (needs providers; runs init -backend=false)
	$(TF) init -backend=false -input=false >/dev/null
	$(TF) validate

.PHONY: lint
lint: ## Run tflint (if installed)
	@command -v tflint >/dev/null 2>&1 && tflint --recursive || echo "tflint not installed; skipping"

.PHONY: security
security: ## Run a security scan (checkov or trivy, if installed)
	@command -v checkov >/dev/null 2>&1 && checkov -d . --quiet \
	  || (command -v trivy >/dev/null 2>&1 && trivy config . \
	  || echo "neither checkov nor trivy installed; skipping")

.PHONY: fetch-app
fetch-app: ## Vendor the admin console source from upstream
	scripts/fetch-admin-console-source.sh

.PHONY: plan
plan: ## terraform plan
	$(TF) plan

.PHONY: apply
apply: ## terraform apply
	$(TF) apply

.PHONY: destroy
destroy: ## terraform destroy (see docs/05-cleanup.md first)
	$(TF) destroy

.PHONY: redeploy-gateway
redeploy-gateway: ## Rebuild + roll the gateway image (primary_container is ignored on apply by design)
	$(TF) apply -replace='module.image_build.terraform_data.build' -replace='module.gateway.terraform_data.url_fixer'

.PHONY: redeploy-console
redeploy-console: ## Rebuild + roll the admin console image
	$(TF) apply -replace='module.image_build.terraform_data.build' -replace='module.admin_console[0].terraform_data.url_fixer'

.PHONY: vpn-profile
vpn-profile: ## Download the .ovpn client profile from Secrets Manager
	@arn=$$($(TF) output -raw vpn_client_profile_secret_arn); \
	aws secretsmanager get-secret-value --secret-id "$$arn" \
	  --query SecretString --output text | jq -r .ovpnProfile > claude-gateway-vpn.ovpn; \
	echo "Wrote claude-gateway-vpn.ovpn"
