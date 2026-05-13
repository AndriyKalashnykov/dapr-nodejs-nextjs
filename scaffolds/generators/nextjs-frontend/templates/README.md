# <%= name %> — Next.js SSR frontend (App Router)

A Next.js 16 App Router SSR frontend scaffolded from `scaffolds/generators/nextjs-frontend`. Calls
backend services via Dapr sidecar invocation, NOT direct HTTP.

## Local development

```bash
# Full stack (recommended)
make up -d
open http://localhost:3000

# Frontend-only hot reload (sidecar must be reachable separately)
pnpm --filter <%= name %> run dev
```

## Production runtime

The production `Dockerfile` uses Next.js standalone output and invokes `node app/<%= name %>/server.js`
directly — no pnpm/corepack at runtime (avoids the corepack per-user activation trap; see the project's
`lint-docker-no-runtime-pnpm` Makefile guard and PR #198 in the parent repo for the root cause).

For the dev image (`Dockerfile.dev`), a minimal `pnpm-workspace.yaml` is emitted inline before
`pnpm install` so pnpm v11's `allowBuilds` config can authorize sharp/protobufjs postinstall scripts.

## Environment variables

| Variable | Default | Notes |
|---|---|---|
| `JWT_SECRET_KEY` | `secret` | Matches backend's JWT signing key |
| `DAPR_HOST` | `127.0.0.1` | Dapr sidecar host (shares network namespace via `network_mode: service:<%= name %>`) |
| `DAPR_PORT` | `3500` | Dapr sidecar HTTP port |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | unset | Set to `http://grafana-otel:4318` to enable `@vercel/otel` traces |

## OpenTelemetry

Instrument via [`@vercel/otel`](https://www.npmjs.com/package/@vercel/otel), NOT plain
`@opentelemetry/sdk-node`. Next.js core loads before standard SDK hooks can patch it; `@vercel/otel`
hooks Next.js's built-in span emission instead.

For outbound Dapr invokes, inject W3C traceparent into headers:

```ts
import { context as otelContext, propagation } from "@opentelemetry/api";

const headers: Record<string, string> = {};
propagation.inject(otelContext.active(), headers);
await daprClient.invoker.invoke(appId, method, HttpMethod.GET, undefined, { headers });
```

See the parent repo's `app/web-nextjs/README.md` for the working reference implementation.

## Tests

| Layer | Command |
|-------|---------|
| Unit | `pnpm --filter <%= name %> run test` |
| Integration | `pnpm --filter <%= name %> run test:integration` (requires `make up -d`) |
