# ADR 0003: Redis as the state store and pub/sub broker

| Status   | Date       |
| -------- | ---------- |
| Accepted | 2026-04-29 |

## Context

The platform's [Dapr sidecar](./0001-dapr-sidecar.md) needs concrete
implementations for two building blocks:

- **State store** — a key-value layer that reads survive Postgres
  primary failover, supporting TTL for the read-through cache pattern
  (`<stateName>:<tableName>:<id>` keys destroyed on writes).
- **Pub/sub broker** — at-least-once delivery for `todo-data` events,
  fan-out to N subscribers, low operator burden.

The choice must be identical (or near-identical) in local Compose and
in Azure Container Apps so behavior parity is preserved across env.

## Decision

Use **Redis** as both the state store and the pub/sub broker, via the
following Dapr components:

| Component      | Type           | Local            | Production            |
| -------------- | -------------- | ---------------- | --------------------- |
| `redis-state`  | `state.redis`  | `redis:8-alpine` | Azure Cache for Redis |
| `redis-pubsub` | `pubsub.redis` | same instance    | same instance         |

Topic: `todo-data`. Component YAML lives in `shared/dapr/components/`.

## Consequences

**Pros**

- A single managed dependency (one Redis cluster) covers both
  capabilities, halving operational surface vs. a separate broker.
- Azure Cache for Redis is private-endpoint accessible from ACA over
  the VNet; no public surface.
- Redis Streams (under the pub/sub component) provide at-least-once
  delivery and consumer groups out of the box.
- Subscribers register declaratively in
  `app/backend-ts/dapr/components/subscriptions.yaml`; no broker-
  specific consumer code in the application.

**Cons**

- Pub/sub durability is bounded by Redis stream length / TTL — not
  suitable for events that must persist for days. The `todo-data`
  events are short-lived state-change notifications, so this fits.
- Redis is single-AZ in the basic SKU — the Terraform stack pins a
  Standard tier in production for cross-AZ failover.
- The same instance handling both state and pub/sub means a Redis
  outage takes down both capabilities at once. Mitigated by the
  read-through cache pattern: on state-store miss, the application
  falls back to Postgres (slower but available).

## Alternatives considered

- **Postgres LISTEN/NOTIFY**: rejected — at-most-once, no consumer
  groups, no replay. Would need a custom outbox table to add
  durability — more complex than Redis Streams.
- **Azure Service Bus**: rejected for pub/sub — adds a second managed
  dependency and a new Dapr component without solving the state-store
  question. Revisit if event durability requirements grow.
- **In-memory state (Dapr `state.in-memory`)**: rejected — single-
  process only; defeats horizontal scaling.

## See also

- `shared/dapr/components/statestore.yaml` — Redis state component
- `shared/dapr/components/pubsub.yaml` — Redis pub/sub component
- `app/backend-ts/dapr/components/subscriptions.yaml` — declarative
  consumer registration
- `infra/azure/main.tf` — Azure Cache for Redis private-endpoint setup
