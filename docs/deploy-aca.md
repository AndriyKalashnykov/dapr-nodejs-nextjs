# Deploying to Azure Container Apps

`make e2e-aca` (and the matching `.github/workflows/e2e-aca.yml`) deploys the full stack to Azure Container Apps, runs a smoke test, and destroys everything. Use it as a prod-parity e2e layer beyond local compose.

## What gets deployed

From `infra/azure/`:

| Resource | Purpose |
|---|---|
| Azure Container Apps environment | Runtime platform (Dapr sidecar injection, scale rules, ingress) |
| `backend-ts` Container App | Express 5 API, external ingress, Dapr-enabled |
| `web-nextjs` Container App | Next.js SSR, external ingress, Dapr-enabled |
| Azure Container Registry | Hosts the two images (tagged with git SHA) |
| PostgreSQL Flexible Server | `backend_ts` schema, VNet-integrated, private DNS |
| Azure Cache for Redis | Dapr state + pub/sub backend, private endpoint |
| Azure Key Vault | JWT secret, DB password, Redis password, App Insights conn string |
| Dapr components | `redis-state`, `redis-pubsub`, `azure-keyvault-secretstore` — scoped to both app-ids |
| Application Insights + Log Analytics | Traces, logs, metrics |
| Virtual Network + subnets + private DNS zones | Private connectivity between apps and backing services |

## Cost

Approximate cost per full `make e2e-aca` run (deploy → smoke → destroy), West US 2:

| Resource | Per-hour | 15-min run |
|---|---|---|
| PostgreSQL `B_Standard_B1ms` + 32 GB storage | ~$0.03 | ~$0.01 |
| Azure Cache for Redis Basic C0 | ~$0.02 | ~$0.01 |
| Container Apps (2× 0.5 vCPU / 1 GiB, idle) | ~$0.05 | ~$0.02 |
| Key Vault + Log Analytics + App Insights + ACR (Basic) | ~$0.02 | ~$0.01 |
| **Total** | | **~$0.05–$0.30** |

The bulk of the expense is sunk in the first deploy (ACR, VNet, DNS zones are ~free but creation is serialized). Repeated runs inside one hour don't add much. **Do NOT wire to PRs** — cost compounds and each run serializes on Terraform state.

## One-time setup: OIDC federation

CI authenticates to Azure via OpenID Connect workload identity federation (no long-lived secrets). One-time steps, run from a local Azure CLI with Owner rights on the target subscription.

### 1. Create the Azure AD app and service principal

```bash
SUB="<your-subscription-id>"
APP_NAME="dapr-nodejs-nextjs-e2e"

# App registration
APP_ID=$(az ad app create --display-name "$APP_NAME" --query appId -o tsv)
SP_ID=$(az ad sp create --id "$APP_ID" --query id -o tsv)

echo "AZURE_CLIENT_ID=$APP_ID"
echo "AZURE_TENANT_ID=$(az account show --query tenantId -o tsv)"
echo "AZURE_SUBSCRIPTION_ID=$SUB"
```

### 2. Grant the SP rights on the subscription

```bash
# Contributor — creates all resources
az role assignment create \
  --assignee "$APP_ID" \
  --role "Contributor" \
  --scope "/subscriptions/$SUB"

# User Access Administrator — needed so Terraform can assign "Key Vault
# Secrets User" to the container-app managed identities.
az role assignment create \
  --assignee "$APP_ID" \
  --role "User Access Administrator" \
  --scope "/subscriptions/$SUB"
```

### 3. Add federated credentials for GitHub Actions

One credential per `sub` claim GitHub will present. For a `workflow_dispatch`-only workflow on `main`:

```bash
REPO="AndriyKalashnykov/dapr-nodejs-nextjs"

az ad app federated-credential create --id "$APP_ID" --parameters - <<EOF
{
  "name": "gh-main-workflow-dispatch",
  "issuer": "https://token.actions.githubusercontent.com",
  "subject": "repo:${REPO}:ref:refs/heads/main",
  "audiences": ["api://AzureADTokenExchange"]
}
EOF
```

For PR-triggered runs (not recommended due to cost) add a second credential with `subject = "repo:${REPO}:pull_request"`.

### 4. Configure GitHub repository secrets

Settings → Secrets and variables → Actions → **Secrets**:

| Secret | Value |
|---|---|
| `AZURE_CLIENT_ID` | `$APP_ID` from step 1 |
| `AZURE_TENANT_ID` | Tenant ID from step 1 |
| `AZURE_SUBSCRIPTION_ID` | Subscription ID |
| `JWT_SECRET_KEY` | A strong random value; must match the value the smoke test uses when signing tokens. `openssl rand -hex 32` is a reasonable choice |

### 5. (Optional) Service-principal client-secret alternative

If OIDC federation isn't viable (corporate policy, non-standard GH plan), fall back to a client secret:

```bash
az ad sp credential reset --id "$APP_ID" --query password -o tsv
```

Store the result as the `AZURE_CLIENT_SECRET` secret and swap the `azure/login@...` step inputs accordingly. Accept the long-lived-secret risk + manual rotation.

## Running `make e2e-aca` locally

Local runs are identical to CI but use `az login` interactively:

```bash
az login
export TF_VAR_AZURE_SUBSCRIPTION_ID="<subscription-id>"
export TF_VAR_jwt_secret_key="$(openssl rand -hex 32)"
export JWT_SECRET_KEY="$TF_VAR_jwt_secret_key"   # must match for smoke
make e2e-aca
```

The target:

1. Runs `terraform apply -target=module.container_registry` to create the ACR if it doesn't exist yet
2. Reads the ACR login server from Terraform outputs
3. Builds + pushes `backend-ts:${git_sha}` and `web-nextjs:${git_sha}` to the ACR
4. Full `terraform apply` with the SHA tags wired in
5. Runs `e2e/e2e-aca.sh` against the deployed ingress URLs
6. `terraform destroy` — always, in a trap

## Running from CI

Actions → **E2E (ACA)** → Run workflow. Optional input `keep_resources=true` skips the destroy (for debugging a failing deploy); remember to destroy manually afterward or the cost accrues.

The workflow is `workflow_dispatch`-only. It will not run on push or PR.

## Image supply-chain gate (Trivy)

The `e2e-aca` workflow runs Trivy between `docker build` and `docker push` for each image:

```
Build → Trivy scan (CRITICAL/HIGH blocking) → Push → Terraform deploy
```

If Trivy finds a fixable CRITICAL or HIGH CVE in the base image, a leaked secret embedded in an image layer, or a Dockerfile misconfiguration, the workflow fails before `docker push` — nothing lands in ACR, nothing deploys to ACA.

Options passed to `aquasecurity/trivy-action`:

- `scanners: 'vuln,secret,misconfig'` — three checks in one pass
- `severity: 'CRITICAL,HIGH'` — lower-severity findings don't block (they're informational in CI logs)
- `exit-code: '1'` — non-zero exit on any matching finding
- `ignore-unfixed: true` — skip CVEs with no upstream fix (can't act on them)

When Trivy fails, inspect the workflow log for the CVE ID and advisory URL. If the finding is a false positive or upstream-unfixable with a known mitigation, add it to `.trivyignore` at the repo root with a dated comment explaining why. Example:

```
# .trivyignore — justifications required, dated
# CVE-2099-12345 (2026-04-20): alpine-musl advisory; mitigated by non-root user + read-only rootfs
CVE-2099-12345
```

Cosign signing, multi-arch, and buildkit in-manifest attestations are deliberately omitted from this pipeline:
- Images are ephemeral — `terraform destroy` removes them at the end of each run
- No third-party consumers need to verify signatures
- ACA runs amd64 only

For a GHCR-publishing pipeline with long-lived consumer images, those gates would be mandatory — see the `/harden-image-pipeline` skill for the canonical template.

## What the smoke test validates (and what it doesn't)

**Does** validate:
- Container Apps reach the Ready state
- Ingress routes incoming HTTPS to both apps
- Managed identity + Key Vault + Dapr secretstore chain resolves at app startup
- JWT auth works end-to-end (401 without, 200 with)
- Backend CRUD cycle against Azure-hosted PostgreSQL
- Dapr component init against Azure Cache for Redis (verified via backend startup succeeding)

**Does NOT** validate (deferred — compose e2e covers locally, none of these run in ACA):
- Zipkin tracing (ACA uses App Insights; needs `@azure/monitor-opentelemetry` wiring — see `TODO` in `infra/azure/main.tf` locals)
- Dapr dashboard / placement / scheduler visibility (ACA hides these)
- Grafana OTEL collector

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `terraform apply` fails at `azurerm_role_assignment.*_kv_secrets_user` | SP lacks `User Access Administrator` | Re-run step 2 of OIDC setup |
| Container Apps stuck `Provisioning` | Image pull failed | Check ACR role assignment on container app MI (provisioned by the `container_app` module) and that the image+tag exists in the ACR |
| Backend returns 500 | Dapr secretstore can't reach KV | Verify `azurerm_role_assignment.backend_kv_secrets_user` applied; check the MI has "Key Vault Secrets User" on the vault |
| Smoke test 401 on authed calls | `JWT_SECRET_KEY` secret mismatch between the KV value seeded by TF and the value signing the JWT in the smoke script | Ensure `TF_VAR_jwt_secret_key` and `JWT_SECRET_KEY` both export to the same value in the same shell |
| `terraform destroy` hangs on Key Vault | Soft delete holds the vault for retention days | `var.purge_protection_enabled = false` in the KV module lets destroy proceed; add `az keyvault purge` as a post-step if needed |
