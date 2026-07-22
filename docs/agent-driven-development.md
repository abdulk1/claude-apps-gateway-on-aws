# Agent-driven development

This repo is set up so AI coding agents and humans share one workflow, one
toolbelt, and one set of guardrails. This page covers the MCP servers, the
conventions, and how to keep agent-authored infrastructure changes safe.

## The toolbelt: MCP servers (`.mcp.json`)

Model Context Protocol (MCP) is the open standard for giving agents tools and
context. The project root's `.mcp.json` declares the **terraform** server so
every teammate and agent gets it on approval; the **aws-knowledge** server is
provided by the `deploy-on-aws` Claude Code plugin in this setup (add it back to
`.mcp.json` if you don't run that plugin):

| Server | Kind | What it's for |
|---|---|---|
| **terraform** (HashiCorp official) | local, Docker — in `.mcp.json` | Terraform Registry lookups, module/provider **schema**, and policy. Use it to confirm a resource attribute instead of guessing (especially for the new `awscc_ecs_express_gateway_service`). Runs in **general mode** — no HCP Terraform / TFE account required. |
| **aws-knowledge** (AWS, managed) | **remote, HTTP**, read-only — via the `deploy-on-aws` plugin | Up-to-date AWS docs, API references, regional availability, and the Agent Toolkit **skills** (`retrieve_skill`). No `uvx`, no credentials. |

Why remote AWS, and not the uvx execution servers:

- The AWS **Knowledge** server is a hosted HTTP endpoint — nothing to spawn
  locally, no credentials. That covers docs + skills, which is what an agent
  needs most while *planning* infra.
- The AWS Agent Toolkit's execution server (`aws configure agent-toolkit`,
  which wires up `mcp-proxy-for-aws`) and the awslabs `aws-api` server both run
  locally via **`uvx`** and sign requests with your AWS credentials. This repo
  deliberately does **not** enable them — AWS *actions* go through the **AWS CLI**
  with the SSO profile instead (see `CLAUDE.md`). Enable the toolkit server with
  `aws configure agent-toolkit --region us-east-1` if you want sandboxed MCP
  execution.
- HashiCorp's terraform server **superseded** the deprecated
  `awslabs.terraform-mcp-server` (yanked in 2026) — use the one wired here.
- In Claude Code, project MCP servers require approval on first use. The
  `deploy-on-aws` plugin's bundled `awsknowledge` server provides the AWS
  Knowledge MCP in this setup, so the project `.mcp.json` no longer declares its
  own `aws-knowledge` entry (dropping it avoided duplicating the plugin's
  server). If you don't run that plugin, add a remote `aws-knowledge` HTTP entry
  (url `https://knowledge-mcp.global.api.aws`) back to `.mcp.json`.

### AWS credentials (IAM Identity Center / SSO)

This account authenticates via SSO, not static keys:

- Profile `claude-gateway`, account `998850986983`, role `AdministratorAccess`,
  region `us-east-1`; session config lives in `~/.aws/config` under
  `[sso-session claude-gateway]`.
- Refresh with `aws sso login --sso-session claude-gateway`; set
  `AWS_PROFILE=claude-gateway` for CLI actions.
- Prefer describing reality with read-only CLI calls, then expressing changes in
  **Terraform** — don't mutate infrastructure out-of-band with the CLI, or it
  becomes Terraform drift. Never expose long-lived keys to the agent.

## Conventions the agent reads

- **`AGENTS.md`** (root) — the canonical, cross-tool agent guide (the
  [agents.md](https://agents.md) convention): repo map, ground rules, definition
  of done, and the sharp edges. **`CLAUDE.md`** points here so Claude Code and
  other tools converge on one source of truth.
- Every non-obvious IAM statement and design choice carries an inline comment
  explaining *why* — so an agent editing the module inherits the reasoning
  instead of "simplifying" away a hard-won constraint.

## The workflow: plan → generate → verify → guardrail

1. **Plan against real schema.** Use the `terraform` and `aws-knowledge` MCP
   servers to check resource shapes and regional availability *before* writing
   HCL. For a task with several parts, ask the agent for a written plan first.
2. **Generate** the smallest coherent change, matching the surrounding module's
   style.
3. **Verify locally** — the definition of done:
   ```bash
   make fmt validate lint security
   # or: pre-commit run --all-files
   ```
4. **Guardrails catch the rest.** `.pre-commit-config.yaml` and
   `.github/workflows/terraform.yml` run the *same* `fmt` / `validate` /
   `tflint` / `checkov` set locally and in CI, plus a `terraform plan` on PRs
   once AWS OIDC is configured. Policy-as-code (checkov) is the backstop for
   security regressions an agent might introduce.

## Keeping state and secrets safe with agents

- **State is sensitive** here (Aurora password, VPN key). Keep it in an
  encrypted remote backend; don't let an agent read raw state or `*.tfstate`
  files, and never `output` a secret.
- `.gitignore` blocks `*.tfvars`, `*.tfstate*`, and `*.ovpn` so an agent can't
  accidentally commit them. `detect-private-key` in pre-commit is a second net.
- Review agent-proposed IAM diffs specifically — least privilege is easy to
  erode one convenience grant at a time.

## Further reading

- HashiCorp Terraform MCP server —
  <https://developer.hashicorp.com/terraform/mcp-server>
- AWS Labs MCP servers (aws-api, aws-knowledge) —
  <https://awslabs.github.io/mcp/>
- agents.md convention — <https://agents.md>
- Model Context Protocol — <https://modelcontextprotocol.io>
