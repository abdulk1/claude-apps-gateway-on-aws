# 04 — Admin console guide

The admin console turns spend control and model access — normally a ticket, a
CLI call, or a redeploy — into something a platform admin does directly, gated
by IdP group membership.

Open `terraform output -raw admin_console_endpoint` and sign in with a user in
`admin_okta_group_name`. It's publicly reachable (no VPN); membership is what
authorizes you.

## Spend limits

Set daily/weekly/monthly caps per organization, group, or user. Changes take
effect on the **next request** — no redeploy.

**Auditability:** the console makes these calls with the signed-in admin's own
gateway-issued bearer token (obtained via the same device-authorization flow the
CLI uses). So every spend-limit change is recorded in the **gateway's own audit
log** as `oidc:<sub>` — attributed to the real admin, not a shared credential.

## Model access

Toggle which Claude models are available to developers, from the **live Bedrock
catalog** (`bedrock:ListFoundationModels`), not a hardcoded list.

**How it works (and why it's the one auditability exception):** the gateway has
no runtime admin API for its model catalog — `availableModels` only exists as a
line in `gateway.yaml`, populated from the `AVAILABLE_MODELS_RAW` env var by
`entrypoint.sh`. So the console changes it by calling
`ecs:UpdateExpressGatewayService` on the **gateway's own** ECS service (its only
runtime-mutable surface), using the console's IAM task role — no image rebuild.

Because that path is IAM, not a gateway bearer token, model-catalog changes are
**not** in the gateway's audit log; they appear in **AWS CloudTrail**,
attributed to the console's task role. That's a real, documented difference from
spend-limit changes. If you need model changes attributed to a human identity,
change the initial catalog via Terraform (`available_models`) through your
normal reviewed/CI'd change process instead of the console.

## Terraform and the model list

`available_models` in Terraform sets only the **initial** catalog. After the
console changes it, the live value diverges from Terraform — which is expected:
`primary_container` is `ignore_changes`d precisely so this out-of-band,
intended change doesn't show as drift. If you later change `available_models` in
Terraform and want it to take effect, use `make redeploy-gateway` (a plain
`apply` will ignore the container change by design).
