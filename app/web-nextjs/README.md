# web-nextjs — Next.js 16 SSR frontend (App Router)

The SSR frontend of the Dapr-on-Node reference stack. See the [root README](../../README.md) for the
project-wide overview, quickstart, and architecture diagrams.

## What this service does

- Serves a JWT-authed todo UI via Next.js 16 App Router (SSR pages + API routes).
- Calls the `backend-ts` REST API exclusively through `DaprClient.invoker.invoke()` (NOT direct HTTP)
  — see [`src/services/backend-ts.ts`](src/services/backend-ts.ts).
- Injects W3C `traceparent` into outbound Dapr invokes via `propagation.inject(otelContext.active(), headers)`
  so spans stay connected across the sidecar → sidecar → backend chain (verified by e2e probe [7/8]).
- Instruments with [`@vercel/otel`](https://www.npmjs.com/package/@vercel/otel) — Next.js core loads
  before standard `@opentelemetry/sdk-node` instrumentation hooks can patch it, so `@vercel/otel` is
  the only OTel integration that works for Next.js. See [`feedback_nextjs_otel_choice.md`](../../../.claude/projects/-home-andriy-projects-dapr-nodejs-nextjs/memory/feedback_nextjs_otel_choice.md)
  in the project memory for the failure-mode details.

## Local development

Two paths — pick one:

**Through the full stack** (recommended, mirrors prod):

```bash
make up -d                # starts web-nextjs + Dapr sidecar + backend-ts + Postgres + Redis + Zipkin
open http://localhost:3000
```

**Standalone hot-reload** (frontend-only iteration, backend stubbed via Dapr sidecar):

```bash
pnpm --filter web-nextjs run dev
```

Requires `JWT_SECRET_KEY=secret` (or whatever the running backend signs with) and `DAPR_HOST=localhost`
+ `DAPR_PORT=3500` in the env so `DaprClient` can reach the sidecar.

## Tests

| Layer | Command | Notes |
|-------|---------|-------|
| Unit | `pnpm --filter web-nextjs run test` | Vitest 4, mocked `DaprClient` |
| Unit + coverage | `pnpm --filter web-nextjs run test:cov` | Single-run with coverage |
| Integration | `pnpm --filter web-nextjs run test:integration` | `fetch()` against `localhost:3000`; requires `make up -d` first |
| Browser e2e | `make e2e-browser` | Playwright against full stack |

## Build

```bash
pnpm --filter web-nextjs run build       # next build, requires JWT_SECRET_KEY env var
```

Production runtime uses Next.js standalone output: `node app/web-nextjs/server.js` (no pnpm/corepack at
runtime — see [`app/web-nextjs/Dockerfile`](Dockerfile) and the project-wide
[`lint-docker-no-runtime-pnpm`](../../Makefile) guard).

## Environment

| Variable | Default | Notes |
|---|---|---|
| `JWT_SECRET_KEY` | `secret` | JWT signing key; must match backend's |
| `DAPR_HOST` | `127.0.0.1` in compose | Sidecar address (shares network namespace) |
| `DAPR_PORT` | `3500` | Dapr sidecar HTTP port |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | unset locally | Set to `http://grafana-otel:4318` to enable `@vercel/otel` |
| `BACKEND_APP_ID` | `backend-ts` | Target Dapr app-id for `invoker.invoke()` |

## Notes

- Do NOT set `NODE_ENV=development` in `.mise.toml [env]` or `.env.example` — the `jdx/mise-action` would
  leak it into CI, overriding Next.js's internal `NODE_ENV=production` during `next build` and triggering
  the `/_global-error` prerender crash ([vercel/next.js#87719](https://github.com/vercel/next.js/issues/87719)).
- `app/global-error.tsx` and `app/not-found.tsx` are intentional defense-in-depth + production error UX.
- Production deployment target is Azure Container Apps via Terraform (`infra/azure/`). See
  [`docs/deploy-aca.md`](../../docs/deploy-aca.md).
