# ADR 0001: Dapr sidecar for inter-service communication

| Status   | Date       |
| -------- | ---------- |
| Accepted | 2026-04-29 |

## Context

The platform consists of multiple Node.js / TypeScript services that need
to call each other and share state. Each service must:

- discover and invoke other services without hard-coding URLs;
- read and write application state with built-in retries / TTL;
- publish and subscribe to domain events;
- fetch secrets without bundling credentials in the image;
- be hostable identically in local Docker Compose, local Kubernetes,
  and Azure Container Apps.

Implementing each capability per service (custom HTTP clients, Redis
clients, secret-fetcher loops, retry middleware) duplicates work and
ties the application code to the choice of broker / store. The
alternative is a sidecar runtime that exposes a stable HTTP / gRPC API
to the application and abstracts the underlying implementation.

## Decision

Adopt **[Dapr](https://dapr.io/)** as the per-service sidecar for state,
pub/sub, service invocation, and secret access. Every backend service
runs as two containers in a shared network namespace: the application
container plus a `daprd` container scaled 1:1.

## Consequences

**Pros**

- Application code calls a single localhost endpoint
  (`http://localhost:3500/v1.0/...`) regardless of where the
  state store / broker actually lives.
- Swapping Redis (local) for Azure Cache for Redis (prod) is a
  component-YAML change; no code change.
- Dapr's secretstore abstraction lets the application read DB
  credentials from the local file in dev and from Azure Key Vault in
  prod via the same SDK call (`Secrets.get()`).
- Every cross-service call is automatically traced via the sidecar's
  built-in OpenTelemetry exporter.

**Cons**

- Each service now has two containers — small per-pod memory and
  CPU overhead (sidecar is ~20–40 MB resident).
- Failures span more components: the sidecar can be the cause of an
  apparent application bug. Mitigated by reading sidecar logs first
  and by the integration-test layer running real `daprd`.
- Component YAML is part of the deploy artifact; new state stores or
  brokers require both code change AND YAML change in the same PR.

## Alternatives considered

- **Direct HTTP between services**: rejected — would require a separate
  service-discovery layer, custom retry / circuit-breaker middleware,
  and would couple application code to the wire format of every store.
- **Service mesh (Istio/Linkerd)**: rejected — solves traffic
  management but not state, pub/sub, or secret access. Too heavyweight
  for the application surface here.
- **Cloud-native SDKs (Azure SDK + Redis SDK)**: rejected — locks the
  application to a specific cloud's identity and control planes,
  defeating the goal of identical local + prod execution.

## See also

- `shared/dapr/` — Dapr runtime config and components
- `app/backend-ts/dapr/components/` — service-scoped overrides
- `infra/azure/main.tf` — ACA deploys with Dapr enabled
