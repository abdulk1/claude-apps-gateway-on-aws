# Claude Apps Gateway on AWS — Terraform

A Terraform reference architecture for running Anthropic's
[Claude apps gateway](https://docs.claude.com/en/docs/claude-code/claude-apps-gateway)
on AWS, fronting Amazon Bedrock — plus an optional admin console for spend-limit
and model-access management, and a self-service Client VPN for reaching the
private gateway.

This is a faithful Terraform port of the AWS CDK sample
[`aws-samples/sample-claude-apps-gateway-on-aws`](https://github.com/aws-samples/sample-claude-apps-gateway-on-aws)
(see the [launch blog post](https://aws.amazon.com/blogs/machine-learning/introducing-claude-apps-gateway-for-aws/)).
Where Terraform lets us do something cleaner than the CDK original, we did —
those deviations are catalogued in
[docs/differences-from-cdk-sample.md](docs/differences-from-cdk-sample.md).

> **Status / expectations.** This targets bleeding-edge AWS: the gateway and
> admin console run on **ECS Express Mode**
> (`AWS::ECS::ExpressGatewayService`), consumed through the **`awscc`**
> (AWS Cloud Control) provider because the classic `aws` provider has no native
> resource for it yet. Treat this as a starting point you `terraform plan` in
> your own account: if the `awscc` schema in your installed provider version
> names an attribute differently, align it (the terraform MCP server helps).

## Architecture

Seven CDK stacks become one root module + six child modules:

| CDK stack | Terraform module | Contents |
|---|---|---|
| `ClaudeGatewayNetworkStack` | `modules/network` | Dedicated VPC: 2 private subnets (gateway) + 2 public (admin console), 1 NAT Gateway, VPC interface endpoints for Bedrock + Secrets Manager, and the 3 security groups. |
| `ClaudeGatewayDatabaseStack` | `modules/database` | Aurora Serverless v2 PostgreSQL (auto-pausing, encrypted), and the composed `postgres_url` connection secret. |
| `ClaudeGatewaySecretsStack` | `modules/secrets` | Generated JWT / admin-write / console-session secrets, plus the external OIDC client secret. |
| `ClaudeGatewayBuildMachineStack` | `modules/image-build` | ECR repos + a **CodeBuild** (x86_64) project that builds and pushes both images. |
| `ClaudeGatewayStack` | `modules/gateway` | The gateway: 3 IAM roles + an ECS Express Mode service on the **private** subnets (internal ALB). |
| `ClaudeGatewayAdminConsoleStack` | `modules/admin-console` | The admin console: same pattern on the **public** subnets, gated by IdP group membership. |
| `ClaudeGatewayVpnStack` | `modules/vpn` | A mutual-TLS AWS Client VPN endpoint with the cert chain and `.ovpn` profile generated in Terraform. |

```
Developer (claude /login)
   │  device-flow login over Client VPN (modules/vpn)
   ▼
┌──────────── VPC (modules/network) ─────────────────────────────┐
│  private subnets                    public subnets             │
│  ┌───────────────────────┐          ┌──────────────────────┐   │
│  │ Gateway (Express Mode)│◀────────▶│ Admin console        │   │
│  │ internal ALB          │  admin   │ (Express Mode, public │   │
│  │ modules/gateway       │  APIs    │  ALB, IdP-gated)      │   │
│  └───────┬─────────┬─────┘          └──────────────────────┘   │
│          │         │                                           │
│   Aurora ▼         ▼ VPC endpoints (bedrock-runtime, secrets)  │
│  (modules/database)      │                                     │
└──────────────────────────┼─────────────────────────────────────┘
                           ▼
                    Amazon Bedrock (Claude models)
```

The gateway is **private** (its subnets have no internet route, so Express Mode
gives it an internal load balancer); developers reach it via the CLI's
device-flow login over the VPN. The admin console is **public**, gated by IdP
group membership rather than network placement, so admins don't need VPN access
to manage spend limits.

## Prerequisites

- Terraform ≥ 1.9, AWS CLI v2, `jq`, and Docker (only for the `terraform` MCP
  server). `terraform apply` shells out to the AWS CLI for the image-build wait
  and the post-create URL fix, so the machine running Terraform needs valid AWS
  credentials.
- An AWS account with Amazon Bedrock access to the Claude models you plan to
  expose, in a region where **Bedrock and ECS Express Mode** are available.
- **IAM Identity Center enabled**. The gateway is OIDC-only, so by default this
  repo provisions an **Amazon Cognito** user pool as an OIDC bridge federated to
  Identity Center over SAML (or set `enable_cognito_idp = false` for an external
  OIDC IdP like Okta). See [docs/01-prerequisites.md](docs/01-prerequisites.md).

## Quick start

```bash
# 1. Vendor the admin console app source (skip if enable_admin_console = false)
scripts/fetch-admin-console-source.sh

# 2. Configure inputs (region, name_prefix, admin group)
cp terraform.tfvars.example terraform.tfvars

# 3. Phase 1 — create Cognito + the gateway; get the SAML values for Identity Center
terraform init
terraform apply
terraform output identity_center_saml_acs_url identity_center_saml_entity_id

# 4. Create the customer-managed SAML app in IAM Identity Center using those
#    outputs (docs/01-prerequisites.md), then set its metadata URL and re-apply:
#    echo 'identity_center_saml_metadata_url = "https://..."' >> terraform.tfvars
terraform apply     # phase 2 — wires up federation
```

The IdP is a **Cognito user pool federated to IAM Identity Center over SAML**, a
two-phase apply (Cognito's ACS URL and Identity Center's metadata reference each
other). Full walkthrough: [docs/01-prerequisites.md](docs/01-prerequisites.md) →
[docs/02-deploy.md](docs/02-deploy.md). Then
[docs/03-verify.md](docs/03-verify.md) to confirm sign-in works, and
[docs/05-cleanup.md](docs/05-cleanup.md) to tear it all down. No client secret
to supply — Cognito generates it and wires it to the gateway automatically.

`terraform output` surfaces the gateway endpoint (for `forceLoginGatewayUrl` in
developers' managed settings), the admin console URL, and the command to
download the `.ovpn` VPN profile.

## Documentation

| Doc | What it covers |
|---|---|
| [docs/architecture.md](docs/architecture.md) | Deep dive on the request flow, why the gateway is private and the console public, and the module dependency graph. |
| [docs/01-prerequisites.md](docs/01-prerequisites.md) | Cognito + IAM Identity Center (SAML) setup, the two-phase apply, and the external-OIDC alternative. |
| [docs/02-deploy.md](docs/02-deploy.md) | The literal deploy steps and what each phase does. |
| [docs/03-verify.md](docs/03-verify.md) | Confirming the deployment actually works. |
| [docs/04-admin-console-guide.md](docs/04-admin-console-guide.md) | Using spend limits + model access, and the auditability trade-off. |
| [docs/05-cleanup.md](docs/05-cleanup.md) | Tearing it down (Client VPN + ENIs need care). |
| [docs/06-custom-inference-profile.md](docs/06-custom-inference-profile.md) | Routing a model through a custom Bedrock inference profile. |
| [docs/differences-from-cdk-sample.md](docs/differences-from-cdk-sample.md) | Every deviation from the CDK original, and why. |
| [docs/agent-driven-development.md](docs/agent-driven-development.md) | The MCP servers, agent workflow, and IaC guardrails. |

## Agent-driven development

`.mcp.json` ships HashiCorp's **terraform** MCP server (docker, general mode) so
agents (and teammates) share one toolbelt, and `AGENTS.md` / `CLAUDE.md` capture
the repo's conventions. AWS docs + Agent Toolkit skills come from the managed,
**remote** AWS Knowledge MCP, which the **deploy-on-aws** Claude Code plugin
provides in this setup (no `uvx`, no credentials); teammates who don't run that
plugin should add a remote `aws-knowledge` entry to `.mcp.json`. AWS *actions* go
through the AWS CLI with the SSO profile, not a local execution server. Guardrails (pre-commit + CI running `fmt`/`validate`/`tflint`/`checkov`)
keep agent-authored changes honest. See
[docs/agent-driven-development.md](docs/agent-driven-development.md).

## Cost note

This deploys billable resources: a NAT Gateway (~$0.045/hr + data processing),
an Aurora Serverless v2 cluster (auto-pauses after 30 min idle, but isn't free
while active), two ECS Express Mode services (each provisions its own ALB), a
Client VPN endpoint (hourly + per-connection), CodeBuild minutes, and Bedrock
inference based on actual usage. None is covered by the AWS Free Tier. Use the
[AWS Pricing Calculator](https://calculator.aws/) for an estimate, and see
[docs/05-cleanup.md](docs/05-cleanup.md) when you're done evaluating.

## License

MIT-0 — see [LICENSE](LICENSE). The gateway container context under
`app/gateway` and the vendored `app/admin-console` derive from the upstream
aws-samples repository (also MIT-0).
