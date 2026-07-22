# Differences from the CDK sample

This repo ports
[`aws-samples/sample-claude-apps-gateway-on-aws`](https://github.com/aws-samples/sample-claude-apps-gateway-on-aws)
from CDK (TypeScript) to Terraform. The **architecture is identical**; the
implementation differs where Terraform's model makes something cleaner. This
page is the honest accounting.

## Provider / resource choices

| Concern | CDK sample | This repo |
|---|---|---|
| ECS Express Mode service | `ecs.CfnExpressGatewayService` (L1) | `awscc_ecs_express_gateway_service` (AWS Cloud Control provider). Verified against **awscc v1.93.0** — every attribute used matches the live schema. |
| New/bleeding-edge AWS resources | CDK L1 constructs from the CFN spec | The `awscc` provider, which auto-generates resources from the CloudFormation registry — the idiomatic Terraform path for resources the classic `aws` provider hasn't caught up to. |

## Lambda custom resources eliminated

The CDK sample used **four** Lambda-backed custom resources. Three are gone in
Terraform, replaced by native providers:

| CDK custom resource | Replaced with |
|---|---|
| `PostgresUrlCombiner` (Lambda reads RDS-managed secret, composes `postgres_url`) | `random_password` for the master password + `format()` to compose the URL directly (`modules/database`). |
| `vpn-cert-generator` (Lambda builds CA/server/client certs, imports to ACM) | The `tls` provider (`tls_private_key`, `tls_self_signed_cert`, `tls_locally_signed_cert`) + `aws_acm_certificate` (`modules/vpn`). |
| `vpn-profile-assembler` (Lambda renders the `.ovpn`) | `templatefile()` against `templates/client-config.ovpn.tftpl` (`modules/vpn`). |

The **fourth** — the gateway/console URL fixer — remains, as a
`terraform_data` + `local-exec` calling the AWS CLI, because the Express Mode
endpoint is genuinely knowable only after creation. Same reason the CDK needed
a custom resource for it.

## Image build: EC2 + SSM → CodeBuild

The CDK provisioned a temporary x86_64 EC2 instance, installed Docker over SSM,
built and pushed both images, and tore the instance down via a Lambda poller.
This repo uses a managed **CodeBuild** project on an x86_64 build image
(`modules/image-build`): nothing to provision, wait for, or clean up. A
`terraform_data` provisioner starts the build and polls to completion, mirroring
the CDK poller's behavior. Images are tagged by **source-content hash** (the CDK
used `:latest`), so a change under `app/` yields a new immutable tag and forces
an ECS redeploy — and immutable ECR tags are enforced.

## Secrets in state — the one real tradeoff

Composing `postgres_url` in Terraform means the Aurora master password lives in
Terraform **state**; generating the VPN chain with the `tls` provider means the
client private key does too. The CDK sample avoided this by doing both inside
Lambdas so nothing sensitive touched the CloudFormation template.

Mitigation, and why it's acceptable for a reference deployment:

- `backend.tf` requires an **encrypted remote backend** with locking and
  least-privilege access — state is treated as sensitive material.
- All such values are `sensitive = true` and never `output`.
- The alternative (Lambda custom resources) trades this for more moving parts
  and Lambda code to audit. For production, you can switch the database module
  to `manage_master_user_password = true` (RDS-managed secret) and have the
  gateway read host/port/user/password separately if its config supports it.

## Behavioral parity notes

- **Secret names**: the CDK let CloudFormation generate unique names to avoid
  collisions on redeploy. This repo uses `name_prefix`-based `name_prefix` on
  each secret for the same reason (unique physical names), and everything
  references secrets by ARN.
- **`primary_container` is `ignore_changes`d** after creation. The CDK kept the
  placeholder URL permanently in its template and re-patched on every deploy via
  a force-re-run custom resource; the model list was likewise only ever changed
  out-of-band by the admin console. Ignoring the container after creation
  expresses that ownership boundary directly. Consequence: roll a new image with
  `make redeploy-gateway` / `make redeploy-console` (or by tainting the
  service), not by editing env in `.tf` and running `apply`.
- **VPN connection logging** is enabled here (to a CloudWatch log group); the
  CDK sample disabled it. Flip `connection_log_options.enabled` in
  `modules/vpn` if you'd rather not log connections.

## What's intentionally the same

The VPC layout, the private-gateway/public-console split, the three-IAM-role
pattern, the least-privilege policy statements (including the non-obvious ones —
`ecs:DescribeTaskDefinition` can't be resource-scoped; the console needs
`RegisterTaskDefinition` + `PassRole` to change the model list), the gateway
container's cryptographic binary verification, and `gateway.yaml` are all ported
faithfully. The hard-won comments from the CDK sample are preserved next to the
Terraform that carries the same lesson.
