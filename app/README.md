# Application build contexts

These are the container build contexts CodeBuild turns into images (see
`modules/image-build`). They are application code, not infrastructure — kept
here so the same proven images the CDK sample ships can be built from Terraform.

## `gateway/`

The gateway image. Checked in because it is small and central:

- `Dockerfile` — downloads and cryptographically verifies the `claude` binary
  (GPG signature + SHA256) at build time. Because it hardcodes `linux-x64`, it
  must be built on an x86_64 host — which is why `modules/image-build` uses an
  x86_64 CodeBuild environment.
- `gateway.yaml` — the gateway config. `${VAR}` placeholders are resolved from
  the container environment (which Terraform populates from Secrets Manager and
  plain env vars). `${AVAILABLE_MODELS_RAW}` is special: it is a YAML
  flow-sequence substituted by `entrypoint.sh` before the gateway parses the
  file, so the model list can change via a plain ECS parameter update.
- `entrypoint.sh` — performs that substitution, then execs the gateway.

Pin a specific gateway version by editing `CLAUDE_CODE_VERSION` in the
`Dockerfile`.

## `admin-console/`

Not checked in. Vendor it from the upstream sample with:

```bash
scripts/fetch-admin-console-source.sh
```

It is a full FastAPI application (server-rendered HTML) that belongs to the
upstream repo; fetching it on demand keeps this repo focused on the Terraform.
Set `enable_admin_console = false` to skip it entirely.
