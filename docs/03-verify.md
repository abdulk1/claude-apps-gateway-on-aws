# 03 — Verify

## 1. Services are healthy

```bash
GW_ARN=$(terraform output -raw gateway_service_arn)
aws ecs describe-express-gateway-service --service-arn "$GW_ARN" \
  --query '{status:status,endpoint:endpoint,running:runningTaskCount}'
```

Check CloudWatch Logs if a task isn't running: the gateway log group is
`/ecs/<name_prefix>-gateway-*`. A `client_secret is required` boot error means
the OIDC client secret didn't reach the container — confirm
`TF_VAR_oidc_client_secret` was set at apply time.

## 2. Confirm the public URL was patched

The gateway must know its own public URL for sign-in to work. Confirm the
`url_fixer` ran (it runs automatically on apply):

```bash
aws ecs describe-express-gateway-service --service-arn "$GW_ARN" \
  --query 'primaryContainer.environment[?name==`GATEWAY_PUBLIC_URL`].value' --output text
```

It should print `https://<endpoint>`, **not** `https://placeholder.invalid`.
If it's still the placeholder, re-run:

```bash
make redeploy-gateway
```

## 3. Point a developer's Claude Code at the gateway

On a developer machine, add the gateway URL to Claude Code managed settings so
`claude /login` targets it. In `managed-settings.json`:

```json
{ "forceLoginGatewayUrl": "https://<gateway_endpoint>" }
```

(`terraform output -raw gateway_endpoint` gives the value.)

## 4. Connect the VPN, then sign in

The gateway is private, so:

1. Connect the Client VPN using the `.ovpn` profile (see
   [02-deploy.md](02-deploy.md#5-get-the-vpn-profile)).
2. Run `claude /login`. A browser opens to your IdP; sign in; approve the
   device ("This matches my device — Continue").
   - If the approval click hangs with no error, you're likely on a **full
     tunnel** — this repo's VPN is split-tunnel specifically to avoid that, so
     confirm your client didn't override the pushed routes.
3. Back in the terminal, `claude` should now run inference through the gateway →
   Bedrock. Try a prompt.

## 5. Admin console

Open `terraform output -raw admin_console_endpoint` in a browser (no VPN
needed). Sign in with a user **in the admin group**. A non-member should see
"not authorized." An admin should see the spend dashboard — see
[04-admin-console-guide.md](04-admin-console-guide.md).

### 5a. Validate the `groups` claim (Cognito + Identity Center)

This is the one integration point that depends on your Identity Center config
(see the groups caveat in [01-prerequisites.md](01-prerequisites.md)). If an
admin-group member is treated as a non-admin, the `groups` claim isn't carrying
the group name. Inspect what Cognito actually emits:

1. Confirm `terraform output cognito_saml_federation_active` is `true`.
2. In the gateway logs (`/ecs/<name_prefix>-gateway-*`), a signed-in user's
   token should show a `groups` claim containing your admin group name. If it's
   empty or missing, the Identity Center SAML app isn't sending the groups
   attribute you mapped, or `saml_groups_attribute` doesn't match the attribute
   name.
3. Fix by adjusting the Identity Center attribute mapping, the
   `saml_groups_attribute` variable, and/or the claim format emitted by
   `modules/idp-cognito/lambda/pre_token.py` (it emits a space-delimited string
   by default — switch to a JSON array if your gateway expects one). Re-apply,
   then `make redeploy-gateway` if you changed the Lambda.

## 6. (Optional) exercise the admin API out-of-band

The admin write key exists for CLI/automation checks (the console never uses
it — it authenticates as the signed-in admin). Find the secret and read it:

```bash
ARN=$(aws secretsmanager list-secrets \
  --filters Key=name,Values="$(terraform output -raw name_prefix 2>/dev/null || echo claude-gateway)-admin-write-key" \
  --query 'SecretList[0].ARN' --output text)
aws secretsmanager get-secret-value --secret-id "$ARN" --query SecretString --output text
```

Use that key as a bearer token against the gateway's
`/v1/organizations/spend_limits` API to confirm spend enforcement independently
of the console.

Next: [04 — Admin console guide](04-admin-console-guide.md).
