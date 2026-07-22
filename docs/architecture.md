# Architecture

## What the gateway does

The Claude apps gateway is a self-hosted control plane between Claude Code (and
other Claude apps) and the model provider — here, Amazon Bedrock. It owns five
responsibilities the AWS launch post calls out:

- **Identity** — OIDC/OAuth sign-in against your IdP (Okta in this sample).
- **Policy** — centrally-enforced managed settings (e.g. the available-model
  allow-list).
- **Routing** — holds the AWS credentials and routes inference to Bedrock (via
  the ECS task role), with room to fail over across regions/profiles.
- **Spend caps** — per-user/group/org daily/weekly/monthly limits, enforced on
  the next request.
- **Telemetry** — OTLP forwarding to a backend (omitted here; add a
  `telemetry.forward_to` block in `app/gateway/gateway.yaml`).

Developers point Claude Code at the gateway (`forceLoginGatewayUrl` in managed
settings) and run `claude /login`; the gateway runs the OIDC flow, issues a
short-lived token, applies policy, and proxies inference to Bedrock.

## Request flow

```
1. Developer connects to the Client VPN (modules/vpn) — needed because the
   gateway is on private subnets.
2. `claude /login` → device-flow login → browser → IdP (Okta) sign-in.
   (Split-tunnel VPN: the Okta redirect goes over the normal internet, not the
   tunnel — full-tunnel would break it.)
3. Gateway validates the code, issues a session token (signed with the JWT
   secret), persists device-grant state in Aurora.
4. Subsequent inference requests carry the token. The gateway applies managed
   policy, then invokes Bedrock using its ECS *task role* (no static keys).
5. Bedrock responds; the gateway streams it back to Claude Code.

Admins, separately, hit the public admin console → sign in via the same IdP →
the console calls the gateway's admin APIs with the admin's own bearer token
(spend limits) or calls ECS directly with its task role (model catalog).
```

## Why the gateway is private and the console is public

Both run on **ECS Express Mode** (`awscc_ecs_express_gateway_service`), which
derives public-vs-private ingress from the *subnets' routing*, not a flag:

- **Gateway → private subnets** (no internet gateway route) ⇒ Express Mode
  provisions an **internal** ALB. This satisfies the "deploy on your private
  network" guidance. Developers reach it only via the Client VPN's device-flow
  login.
- **Admin console → public subnets** ⇒ **internet-facing** ALB, but access is
  gated by **IdP group membership** (checked by the gateway on every admin API
  call), not by network placement — so an admin can manage spend limits without
  VPN access.

## The three IAM roles per service

ECS Express Mode's create API requires an **infrastructure role** in addition
to the usual two:

| Role | Used by | Grants |
|---|---|---|
| execution | ECS agent | pull image from ECR, read the injected Secrets Manager secrets |
| task | the gateway process | `bedrock:InvokeModel[WithResponseStream]` on Claude models + your own inference profiles |
| infrastructure | ECS Express Mode | provision the ALB, target group, SGs, autoscaling on your behalf (`AmazonECSInfrastructureRoleforExpressGatewayServices`) |

The admin console's task role is different: instead of Bedrock invoke, it gets
scoped `ecs:UpdateExpressGatewayService`/`DescribeExpressGatewayService` on the
*gateway's* service, `RegisterTaskDefinition` on the gateway's task-def family,
`PassRole` on the gateway's two roles, and `bedrock:ListFoundationModels`. Every
statement is commented in `modules/admin-console/main.tf`.

## Module dependency graph

```
network ──┬─► database ──► secrets ──┐
          │                          ├─► gateway ──► admin_console
          ├─► image_build ───────────┘        │
          └─► vpn                              (gateway feeds console its ARNs)
```

- `secrets` re-exports the `postgres_url` ARN from `database` alongside the
  secrets it generates, so `gateway` takes all four secret ARNs from one place.
- `image_build`'s image-URI outputs are read through a `terraform_data` whose
  provisioner waits for CodeBuild — so `gateway`/`admin_console` implicitly
  depend on the images existing before the ECS services reference them.
- `admin_console` depends on `gateway` for its service ARN, endpoint, role
  ARNs, and task-definition family (all needed for its scoped IAM + config).

## The two-pass public URL

Express Mode's ingress hostname is unpredictable and known only *after* the
service is created — it can't be an input to the service that owns it. So:

1. The `awscc_ecs_express_gateway_service` is created with
   `GATEWAY_PUBLIC_URL = https://placeholder.invalid`.
2. A `terraform_data.url_fixer` provisioner then calls
   `aws ecs update-express-gateway-service` to set the real
   `https://<endpoint>` (and re-applies the current image).
3. `primary_container` carries `ignore_changes`, so that post-create patch —
   and the admin console's later model-list edits — don't show as drift.

This mirrors the CDK sample's URL-fixer custom resource. See
[differences-from-cdk-sample.md](differences-from-cdk-sample.md) for the full
list of what changed in the port.
