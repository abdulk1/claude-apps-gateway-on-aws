# 02 — Deploy

## 0. Configure remote state (recommended before anything else)

This deployment puts sensitive values in Terraform state (see
[differences-from-cdk-sample.md](differences-from-cdk-sample.md#secrets-in-state--the-one-real-tradeoff)).
Uncomment and fill in the S3 backend in `backend.tf` before your first
`terraform init`. Local state works for a quick evaluation but is discouraged.

## 1. Vendor the admin console source

```bash
scripts/fetch-admin-console-source.sh
```

Skip if you set `enable_admin_console = false`.

## 2. Provide inputs

```bash
cp terraform.tfvars.example terraform.tfvars
$EDITOR terraform.tfvars                       # region, name_prefix, admin group
```

With the default `enable_cognito_idp = true` there is **no client secret to
supply** — Cognito generates it. (For an external OIDC IdP, set
`enable_cognito_idp = false` and export `TF_VAR_oidc_client_secret`.)

## 3. Init & apply (phase 1)

```bash
terraform init
terraform apply
```

What happens, in order (Terraform figures out the ordering from the graph):

1. **network** — VPC, subnets, NAT, VPC endpoints, security groups.
2. **idp_cognito** — Cognito user pool, hosted-UI domain, confidential app
   client, and the pre-token Lambda. (SAML federation is skipped until phase 2.)
3. **database** — Aurora Serverless v2 cluster + writer, and the composed
   `postgres_url` secret. (Cluster creation is the slowest step, ~10–15 min.)
4. **secrets** — generated JWT / admin-write / console-session secrets + the
   OIDC client secret (Cognito's, or your external one).
5. **image_build** — ECR repos, CodeBuild project, source upload, then the
   `local-exec` **starts CodeBuild and waits** for both images to build and
   push on an x86_64 host. (~3–6 min.)
6. **gateway** — 3 IAM roles, log group, the ECS Express Mode service (with a
   placeholder public URL), then the **url_fixer** patches in the real endpoint.
7. **cognito_callback_fixer** — sets the Cognito app client's callback to the
   real `https://<gateway-endpoint>/oauth/callback`.
8. **admin_console** — same pattern on public subnets, wired to the gateway.
9. **vpn** — cert chain, ACM imports, Client VPN endpoint, subnet associations,
   authorization rule, and the `.ovpn` profile.

> The machine running `terraform apply` needs the AWS CLI + `jq` and valid
> credentials: steps 5, 6, and 7 shell out to the CLI.

## 3b. Configure Identity Center, then apply (phase 2)

Create the customer-managed SAML application in IAM Identity Center using the
`identity_center_saml_acs_url` and `identity_center_saml_entity_id` outputs, and
map a groups attribute — full steps in
[01-prerequisites.md](01-prerequisites.md). Then set its metadata URL and apply
again to wire up federation:

```bash
echo 'identity_center_saml_metadata_url = "https://<region>.signin.aws.amazon.com/platform/saml/metadata/..."' >> terraform.tfvars
terraform apply
terraform output cognito_saml_federation_active   # -> true
```

## 4. Read the outputs

```bash
terraform output
```

Key outputs: `gateway_endpoint`, `admin_console_endpoint`,
`vpn_client_profile_secret_arn`, `oidc_client_secret_arn`.

## 5. Get the VPN profile

The `.ovpn` was written to `./claude-gateway-vpn.ovpn` (git-ignored). To fetch
it from Secrets Manager instead (e.g. for another developer):

```bash
make vpn-profile          # writes claude-gateway-vpn.ovpn
```

Import it into the [AWS VPN Client](https://aws.amazon.com/vpn/client/) (or any
OpenVPN client) and connect.

## Rolling a new image

Because `primary_container` is `ignore_changes`d after creation (so the
post-create URL patch and admin-console model edits don't churn), a plain
`apply` won't roll a new image. Edit `app/gateway/` (or bump
`CLAUDE_CODE_VERSION` in its Dockerfile), then:

```bash
make redeploy-gateway     # rebuilds via CodeBuild and re-applies the service
make redeploy-console
```

Next: [03 — Verify](03-verify.md).
