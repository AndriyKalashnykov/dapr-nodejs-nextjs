# Architecture Decision Records

Each ADR captures one significant architectural decision: the context
that forced the choice, the decision itself, the trade-offs accepted,
and the alternatives that were ruled out. ADRs are append-only;
superseded decisions get a new ADR that links back to the original
rather than editing history in place.

| #    | Title                                                                              | Status   |
| ---- | ---------------------------------------------------------------------------------- | -------- |
| 0001 | [Dapr sidecar for inter-service communication](0001-dapr-sidecar.md)               | Accepted |
| 0002 | [Azure Container Apps as the production deploy target](0002-aca-as-prod-target.md) | Accepted |
| 0003 | [Redis as the state store and pub/sub broker](0003-redis-state-pubsub.md)          | Accepted |

## Adding a new ADR

1. Pick the next number.
2. Copy the structure from an existing ADR (Status / Date / Context /
   Decision / Consequences / Alternatives / See also).
3. Add the row to the table above.
4. Link from the relevant code or `README.md` section.
