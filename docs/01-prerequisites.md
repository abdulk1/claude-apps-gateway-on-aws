# 01 — Prerequisites (Cognito + IAM Identity Center)

## Tooling (on the machine running Terraform)

- **Terraform ≥ 1.9**, **AWS CLI v2**, and **`jq`** — `terraform apply` shells
  out to the AWS CLI for the image-build wait, the gateway URL fix, and the
  Cognito callback fix, so valid AWS credentials must be present.
- **Docker** — only for the `terraform` MCP server.
- **`gh`** — only for `scripts/fetch-admin-console-source.sh`.

## AWS account

- **Amazon Bedrock model access** for the Claude models you'll expose, in a
  region where **Bedrock and ECS Express Mode** are available.
- **IAM Identity Center enabled** in the account/region (Identity Center is
  regional — enable it in the same region you deploy to, and note it must be
  reachable for SAML metadata).

## Why Cognito is in the picture

The Claude apps gateway is **OIDC-only** — per the
[gateway docs](https://code.claude.com/docs/en/claude-apps-gateway), *"SAML,
LDAP, and other non-OIDC auth… Not supported. OIDC only. Front with an OIDC
bridge if needed."* IAM Identity Center federates to third-party apps over
**SAML**, so it can't be the gateway's OIDC issuer directly. This repo puts an
**Amazon Cognito user pool** in front as the OIDC bridge: Cognito speaks **OIDC**
to the gateway and **SAML** to Identity Center.

```
Gateway ──OIDC──▶ Cognito user pool ──SAML──▶ IAM Identity Center ──▶ your users
```

This is the default (`enable_cognito_idp = true`). To use an external OIDC IdP
(Okta etc.) instead, set `enable_cognito_idp = false` and provide
`oidc_issuer` / `oidc_client_id` / `oidc_client_secret` — see the end of this
page.

## The setup is two-phase (chicken-and-egg)

Cognito needs Identity Center's SAML metadata, and the Identity Center app needs
Cognito's ACS URL / entity ID. So:

### Phase 1 — create Cognito, get the SAML values

Deploy once with federation left unset (the default):

```bash
cp terraform.tfvars.example terraform.tfvars   # region, name_prefix, admin group
terraform init
terraform apply     # identity_center_saml_metadata_url is null on this pass
```

Then read the values you'll enter into Identity Center:

```bash
terraform output identity_center_saml_acs_url      # e.g. https://<domain>.auth.us-east-1.amazoncognito.com/saml2/idpresponse
terraform output identity_center_saml_entity_id    # e.g. urn:amazon:cognito:sp:us-east-1_XXXXXXXXX
```

> On phase 1 the gateway falls back to Cognito-only sign-in (no external users
> yet). That's expected — it's just a bootstrap so these two values exist.

### Create the customer-managed SAML app in IAM Identity Center

In the **IAM Identity Center console → Applications → Add application → "I have
an application I want to set up" → SAML 2.0**:

1. **Application metadata → manually**: set
   - **Application ACS URL** = `identity_center_saml_acs_url` output
   - **Application SAML audience** = `identity_center_saml_entity_id` output
2. **Attribute mappings** — map at least:
   - **Subject** → `${user:email}`, format `emailAddress`
   - `email` → `${user:email}`
   - a **groups** attribute (this is the one to watch — see the note below)
3. **Assign users / groups**, including your **admin group** (default
   `claude-gateway-admins`, set via `admin_okta_group_name`).
4. From the app's details page, copy the **IAM Identity Center SAML metadata
   URL** (or download the metadata file).

> **Groups attribute caveat.** Identity Center's SAML attribute mappings don't
> always expose human-readable group *names* out of the box. Whatever attribute
> you emit for groups, set `saml_groups_attribute` to its name; it's mapped to
> Cognito `custom:groups` and then to the gateway's `groups` claim by the
> pre-token Lambda (`modules/idp-cognito/lambda/pre_token.py`). The gateway
> matches `admin_okta_group_name` against that claim, so the value must contain
> your admin group's name. If Identity Center can't emit group names, assign the
> admin group to the app and adjust the Lambda to inject the group name, or fall
> back to Cognito groups. This is the one integration point that depends on your
> Identity Center configuration — validate it in [03-verify.md](03-verify.md).

### Phase 2 — wire up federation

Set the metadata URL and apply again:

```hcl
# terraform.tfvars
identity_center_saml_metadata_url = "https://<region>.signin.aws.amazon.com/platform/saml/metadata/....."
```

```bash
terraform apply     # creates the Cognito SAML IdP and points the app client at it
```

`terraform output cognito_saml_federation_active` should now be `true`.

## What Terraform manages vs. what you do by hand

| Managed by Terraform (`modules/idp-cognito`) | Done in the Identity Center console |
|---|---|
| Cognito user pool, hosted-UI domain | Enable IAM Identity Center |
| Cognito SAML IdP (from your metadata URL) | Create the customer-managed SAML app |
| Confidential app client (client secret, code flow, `/oauth/callback`) | Enter the ACS URL + entity ID |
| Pre-token Lambda that emits the `groups` claim | Attribute mappings (incl. groups) |
| The gateway's `oidc_issuer` / `client_id` / `client_secret` (from the pool) | Assign users/groups to the app |

There is **no client secret for you to supply** — Cognito generates it and it
flows to the gateway via Secrets Manager automatically.

## Alternative: external OIDC IdP (Okta, Entra, Google, …)

Set `enable_cognito_idp = false` and provide:

| Variable | From your IdP app registration |
|---|---|
| `oidc_issuer` | issuer URL (must serve `/.well-known/openid-configuration`) |
| `oidc_client_id` | OAuth client ID |
| `oidc_client_secret` | OAuth client secret (via `TF_VAR_oidc_client_secret`) |
| `admin_okta_group_name` | the admin group name your IdP emits in the `groups` claim |

Register the redirect URI `https://<gateway-endpoint>/oauth/callback` (use a
placeholder first; the gateway URL is only known after deploy). The gateway
requests `openid profile email offline_access groups` in this mode.

Next: [02 — Deploy](02-deploy.md).
