# 06 — Routing a model through a custom Bedrock inference profile

By default `gateway.yaml` sets `auto_include_builtin_models: true`, which routes
every enabled model through the standard `us.anthropic.*` cross-region inference
profile. You may want a specific model to go through a **custom application
inference profile** instead — commonly for cost allocation/tagging, a
provisioned-throughput allotment, or a Bedrock guardrail attached to that
profile.

## 1. Create the application inference profile (outside this repo)

Create it however you manage Bedrock — console, CLI, or a separate Terraform
config — and note its ARN:

```
arn:aws:bedrock:<region>:<account-id>:application-inference-profile/<profile-id>
```

## 2. Reference it in `gateway.yaml`

Uncomment and edit the `models:` block in `app/gateway/gateway.yaml`. Add one
entry per model that needs its own profile; any model not listed keeps the
default cross-region profile:

```yaml
models:
  - id: claude-sonnet-5
    label: Claude Sonnet 5 (custom inference profile)
    upstream_model:
      bedrock: arn:aws:bedrock:<region>:<account-id>:application-inference-profile/<profile-id>
```

The `upstream_model` key (`bedrock`) matches the `upstreams[].name`, which
defaults to the provider string `bedrock`.

## 3. No IAM change needed

The gateway task role already grants `bedrock:InvokeModel[WithResponseStream]`
on **any application inference profile in this account** (see the
`BedrockInvokeCustomInferenceProfiles` statement in `modules/gateway/main.tf`),
so adding, removing, or repointing profiles in `gateway.yaml` needs no Terraform
IAM change — only the YAML changes.

## 4. Rebuild and roll

`gateway.yaml` is baked into the image, so this is a source change:

```bash
make redeploy-gateway
```

CodeBuild produces a new source-hash-tagged image and the gateway rolls to it.
