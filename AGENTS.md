# AGENTS.md

Guidance for AI coding agents (and humans) working in this repository. This is
the canonical agent guide; `CLAUDE.md` points here. Format follows the
cross-tool [agents.md](https://agents.md) convention.

## What this repo is

A Terraform port of the AWS CDK reference architecture
[`sample-claude-apps-gateway-on-aws`](https://github.com/aws-samples/sample-claude-apps-gateway-on-aws):
it stands up the Anthropic **Claude apps gateway** on AWS in front of Amazon
Bedrock, plus an optional admin console and a self-service Client VPN.

Read `docs/architecture.md` before making structural changes, and
`docs/differences-from-cdk-sample.md` to understand where and why this diverges
from the CDK original.

## Repo map

```
main.tf, variables.tf, outputs.tf, locals.tf   # root module wiring
providers.tf, versions.tf, backend.tf          # providers, versions, state
modules/
  network/        VPC, subnets, NAT, VPC endpoints, security groups
  database/       Aurora Serverless v2 + composed postgres_url secret
  secrets/        generated + external secrets
  idp-cognito/    Cognito OIDC bridge -> IAM Identity Center (SAML) + pre-token Lambda
  image-build/    ECR + CodeBuild (x86_64) image build & push
  gateway/        ECS Express Mode service (private) + IAM + URL fixer
  admin-console/  ECS Express Mode service (public) + IAM + URL fixer
  vpn/            mutual-TLS Client VPN (tls provider) + .ovpn profile
app/
  gateway/        container build context (checked in)
  admin-console/  vendored on demand (scripts/fetch-admin-console-source.sh)
docs/             deploy/verify/cleanup guides + this architecture
```

## Ground rules

- **Providers**: `aws` for anything with a first-class resource; `awscc` only
  for `awscc_ecs_express_gateway_service` (ECS Express Mode is too new for the
  classic provider); `random`/`tls`/`archive`/`local` for what replaced the
  CDK's Lambda custom resources. Don't reach for a null-provider shell hack
  where a real resource exists.
- **Secrets never land in code or images.** They flow: input/generated →
  Secrets Manager → injected as container secrets by the ECS execution role.
  The Aurora password and VPN client key *do* land in Terraform state — that is
  the one accepted tradeoff, and it is why `backend.tf` insists on encrypted
  remote state. Never `output` a secret value.
- **The two ECS services' `primary_container` is intentionally
  `ignore_changes`d.** The public URL is patched post-create and the model list
  is changed by the admin console — both out of band by design. To roll a new
  image use `make redeploy-gateway` / `make redeploy-console`, not a hand edit.
- **IAM stays least-privilege.** Each policy statement in the gateway/console
  modules carries a comment explaining exactly why it exists (several encode
  hard-won lessons from the CDK sample — e.g. `ecs:DescribeTaskDefinition`
  can't be resource-scoped). Preserve that reasoning if you touch them.
- **`name_prefix` drives service names**, and ECS Express Mode derives the task
  definition family as `default-<service-name>`. Keep `locals.tf` the single
  source of truth for those names.

## Definition of done (run before proposing a change)

```bash
make fmt            # terraform fmt -recursive
make validate       # init -backend=false + validate
make lint           # tflint (if installed)
make security       # checkov/trivy (if installed)
```

Or all at once via `pre-commit run --all-files`. CI runs the same set. Do not
commit `.tfvars`, `*.tfstate`, or `*.ovpn` (all git-ignored).

## MCP servers available here

`.mcp.json` ships the **terraform** server; the **aws-knowledge** server comes
from the `deploy-on-aws` plugin in this setup. Use them instead of guessing:

- **terraform** (HashiCorp, docker, general mode) — Registry/module/provider
  lookups, resource schema. Consult it before inventing an
  `awscc_ecs_express_gateway_service` attribute. Declared in `.mcp.json`.
- **aws-knowledge** (managed, **remote HTTP**, read-only) — current AWS docs,
  API references, regional availability, and Agent Toolkit skills
  (`retrieve_skill`). No `uvx`, no credentials. Provided by the `deploy-on-aws`
  Claude Code plugin here; if you don't run that plugin, add a remote
  `aws-knowledge` entry to `.mcp.json`.

AWS **actions** (not lookups) go through the **AWS CLI** with the SSO profile
`claude-gateway` (account `998850986983`, region `us-east-1`); refresh with
`aws sso login --sso-session claude-gateway`. The uvx-based AWS execution MCPs
are intentionally not enabled. See `docs/agent-driven-development.md` and
`CLAUDE.md` for the workflow, credentials, and guardrails.

## Things that will bite you

- The `awscc_ecs_express_gateway_service` schema tracks the
  `AWS::ECS::ExpressGatewayService` CloudFormation resource. If `terraform plan`
  rejects an attribute, check the installed awscc provider version's schema (via
  the terraform MCP server) and align names — the resource is new and evolving.
- `terraform apply` invokes the AWS CLI locally (image build wait + URL fixer).
  The machine running Terraform needs `aws` and `jq` on PATH and valid creds.
- Building the gateway image on arm64 produces a broken image — the build is
  pinned to x86_64 CodeBuild for a reason. Don't "simplify" it to a local
  `docker build`.
