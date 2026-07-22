# CLAUDE.md

This repo's agent guidance lives in **[AGENTS.md](AGENTS.md)** — read it first.

Quick reminders for Claude Code specifically:

- The project `.mcp.json` declares the `terraform` server (via docker); the
  `aws-knowledge` remote HTTP server is provided by the `deploy-on-aws` plugin
  in this setup (teammates without that plugin should add a remote
  `aws-knowledge` entry to `.mcp.json`). Approve them when prompted; prefer them
  over guessing at Terraform schemas or AWS behavior.
- Before proposing Terraform changes, run `make fmt validate` (and `make lint
  security` if the tools are installed). These match CI.
- This deployment targets bleeding-edge AWS (ECS Express Mode via the `awscc`
  provider). When unsure about a resource attribute, check the terraform MCP
  server rather than assuming.
- Never print or output secret values. See `AGENTS.md` → "Ground rules".

## AWS Agent Toolkit rules

From AWS's official [`aws-agent-rules.md`](https://github.com/aws/agent-toolkit-for-aws)
(Step 7 of the toolkit setup), adapted for this repo. **This account uses IAM
Identity Center (SSO):** profile `claude-gateway`, account `998850986983`, role
`AdministratorAccess`, region `us-east-1`. If AWS calls fail with
`ExpiredToken`, run `aws sso login --sso-session claude-gateway`; set
`AWS_PROFILE=claude-gateway` for AWS CLI actions.

- **AWS knowledge/skills:** use the remote **AWS Knowledge MCP** (the
  `aws-knowledge` server, provided by the `deploy-on-aws` plugin in this setup;
  add a remote `aws-knowledge` entry to `.mcp.json` if you don't run that
  plugin) for docs, API references, regional availability, and `retrieve_skill`.
  Before starting an AWS task, check for a relevant skill, load it, and prefer
  its guidance over general knowledge.
- **AWS actions:** run through the **AWS CLI** with the SSO profile above. (The
  toolkit's uvx-based execution MCP was intentionally not enabled — this repo
  prefers the remote MCP + CLI. Re-enable it with
  `aws configure agent-toolkit --region us-east-1` if you want sandboxed MCP
  execution.)
- When uncertain about AWS specifics (API params, permissions, limits, error
  codes), verify against documentation rather than guessing; state uncertainty
  explicitly if you cannot confirm.
- **Infrastructure-as-code:** the upstream rule says "prefer AWS CDK or
  CloudFormation." **This repo standardizes on Terraform** — express infra as
  Terraform under `modules/`, not CDK/CFN. Follow AWS Well-Architected
  principles.
- Use hyphens, not em dashes, in AWS resource names and descriptions.

### Secret safety
- For any secret / credential / API-key / token / password task, prefer the
  `aws-secrets-manager` skill (`retrieve_skill`) first. Do **not** pull secret
  values into context with ad-hoc `secretsmanager get-secret-value` /
  `batch-get-secret-value`. In this repo, secrets are provisioned in
  `modules/secrets`, stored in Secrets Manager, and injected into ECS **by ARN**
  (never by value) — keep it that way, and never echo or `output` a secret.
