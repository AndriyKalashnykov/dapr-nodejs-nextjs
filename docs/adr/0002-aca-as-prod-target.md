# ADR 0002: Azure Container Apps as the production deploy target

| Status   | Date       |
|----------|------------|
| Accepted | 2026-04-29 |

## Context

The platform needs a production runtime that:

- supports the [Dapr sidecar pattern](./0001-dapr-sidecar.md) natively;
- provides ingress, scale-to-zero, and HTTPS-by-default with no separate
  load-balancer or cert-manager configuration;
- requires no Kubernetes operator knowledge for everyday deploys;
- has a fixed monthly cost predictable from a Terraform plan.

## Decision

Deploy to **[Azure Container Apps](https://learn.microsoft.com/en-us/azure/container-apps/overview)** (ACA) using Terraform
(`infra/azure/`). Each service is one Container App with `daprEnabled = true`;
ACA injects and manages the Dapr sidecar from its own control plane.

## Consequences

**Pros**
- ACA ships a managed Dapr runtime — no separate Helm install of
  `dapr-system`, no placement / scheduler / operator pods to maintain.
- External ingress is a single Terraform property; ACA auto-provisions
  the public TLS certificate.
- Scale-to-zero on idle traffic; pay only for actual request seconds.
- Identity is `azurerm_user_assigned_identity` per service with RBAC
  to Key Vault — no client secrets in app config or env vars.
- Postgres Flexible Server and Cache for Redis live in the same VNet
  via private endpoints; ACA reaches them on private IPs only.

**Cons**
- ACA's Dapr version trails the OSS release by a few weeks; the local
  dev stack must pin a Dapr version compatible with the ACA-managed
  one (currently 1.17.x — see `.mise.toml` and `docker-compose.yaml`).
- Less raw flexibility than AKS: per-pod resource overrides, custom
  CRDs, and arbitrary sidecars are not supported.
- Cost model is request-based, so a runaway autoscaler is a real risk.
  Mitigation: tight `replicas` bounds in Terraform.

## Alternatives considered

- **AKS + Dapr Helm chart**: rejected for this project's size — too
  much operator burden for a 2-service platform. Revisit if the service
  count grows or if a feature ACA lacks (custom CRD, GPU pods) becomes
  load-bearing.
- **Azure App Service for Containers**: rejected — no first-class Dapr
  support; would need to run the sidecar manually in a multi-container
  group.
- **Single VM + docker-compose**: rejected — defeats scale-to-zero,
  managed TLS, and managed Postgres/Redis.

## See also

- `infra/azure/` — Terraform stack
- `docs/deploy-aca.md` — OIDC setup, GitHub secrets, smoke test scope
- `.github/workflows/e2e-aca.yml` — manual deploy + destroy workflow
- `make e2e-aca` — Makefile entrypoint (incurs Azure cost)
