# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Dapr-based microservices platform using Node.js/TypeScript with npm workspaces (monorepo). Services communicate through Dapr sidecars for state management, pub/sub, and service invocation. Container runtime is Podman (Docker-compatible).

## Common Commands

### Workspace Commands
This is an npm workspace monorepo. Run commands from repo root using `-w`:
```bash
npm run test -w app/backend-ts          # Run in specific workspace
npm run compile -w packages/@sos/sdk    # SDK must be compiled before backend
```

### Makefile (run `make help` for full list)
```bash
# Setup (first time)
make deps && make install && make setup && make build

# Start / stop
make up             # Bring up full stack (Ctrl-C to stop)
make down           # Tear down full stack

# Partial stack
make up-db          # PostgreSQL only
make up-dapr        # Dapr infrastructure (Redis, Zipkin, placement, dashboard)
make up-infra       # OpenTelemetry + database

# Build
make setup          # Build base Docker images (once after clone)
make build          # Build all service containers
make compile        # Compile SDK + backend TypeScript

# Test (no containers needed)
make lint           # Lint + typecheck across all workspaces
make test           # Unit tests across SDK + backend (with coverage)
make ci             # Full CI pipeline locally (lint + test + build)

# Test (containers needed)
make test-integration # Backend integration tests (requires Postgres + Dapr)
make e2e              # End-to-end smoke test — `make up -d` + e2e/e2e-test.sh + `make down`
make e2e-browser      # Playwright browser tests against a running stack
make e2e-aca          # Deploy to Azure Container Apps + smoke + destroy (INCURS AZURE COST — see docs/deploy-aca.md)

# Database
make migrate        # Run pending DB migrations in running backend-ts container
make psql           # Connect to Postgres CLI (user/pass: postgres)
make redis-cli      # Connect to Redis CLI

# Per-service
SERVICE=backend-ts make debug    # Debug mode with Node inspector (port 9229)
SERVICE=backend-ts make terminal # Shell into running container
SERVICE=backend-ts make logs     # Tail logs for a service

# Maintenance
make clean          # Remove build artifacts and node_modules
make prune          # Remove unused Podman containers/images/volumes
make release VERSION=v1.0.0  # Tag and push a release
make renovate-validate      # Validate Renovate configuration
```

### Backend (`app/backend-ts`)
```bash
npm run dev              # Hot reload dev server (runs DB migrations first)
npm run compile          # TypeScript compilation
npm run ci               # tsc --noEmit + lint + prettier
npm run test             # Unit tests (Vitest, watch mode)
npm run test:cov         # Unit tests with coverage (single run)
npm run test:integration # Integration tests (requires Postgres + Dapr sidecar)
npm run knex -- migrate:make <name>  # Create new DB migration
npm run knex -- migrate:latest       # Run pending migrations

# Run a single test file
cd app/backend-ts && npx vitest --config src/lib/test/vitest.config.ts run src/services/todo.test.ts
# Run a single integration test
cd app/backend-ts && NODE_ENV=test npx vitest --config src/lib/test/vitest.integration.config.ts run src/handlers/api/todo.integration.test.ts
```

### Frontend (`app/web-nextjs`)
```bash
npm run dev    # Next.js dev server
npm run build  # Production build (requires JWT_SECRET_KEY env var)
npm run lint   # eslint .
npm run test   # Vitest unit tests (watch mode)
npm run test:cov # Vitest unit tests with coverage (single run)
```

### Shared SDK (`packages/@sos/sdk`)
```bash
npm run compile  # tsc --build (must run before backend compiles/tests)
npm run test     # Vitest unit tests
npm run ci       # tsc --noEmit + lint + prettier
```

## Architecture

### Monorepo Layout
```
app/
  backend-ts/     Express 5 + Dapr sidecar backend
  web-nextjs/     Next.js 16 SSR frontend
packages/@sos/
  sdk/            Shared Dapr/DB/API utilities (must compile first — other packages depend on build/)
shared/
  dapr/           Dapr runtime config & components (Redis state/pubsub, Zipkin)
  db/             PostgreSQL 18 docker-compose + schema init
  otel/           OpenTelemetry collector + Grafana stack
  microservice/   Base Docker image for all services
infra/            Azure Terraform configs
scaffolds/        Code generators for new services
```

### Service Ports (when stack is running)

| Service | Host Port | Access |
|---|---|---|
| Next.js SSR frontend | 3000 | `http://localhost:3000` |
| Swagger UI | 3001 | `http://localhost:3001/docs` |
| Backend API (direct) | 3001 | `http://localhost:3001/api/v1/todos` |
| Backend API (via Dapr) | 3500 | `http://localhost:3500/v1.0/invoke/backend-ts/method/...` |
| PostgreSQL | 5432 | |
| Redis | 6379 | |
| Zipkin | 9411 | `http://localhost:9411` |
| Dapr Dashboard | 8888 | `http://localhost:8888` |
| Grafana OTEL (if enabled) | 3200 | `http://localhost:3200` |

### Dapr Sidecar Pattern
Every backend service runs as two containers: the app + a Dapr sidecar. The sidecar proxies all inter-service communication:
- **State**: Redis via `DAPR_HOST:DAPR_PORT` (default 3500)
- **Pub/Sub**: Redis topic `todo-data`, subscribers receive CloudEvents at `/consumer/*` endpoints
- **Service Invocation**: `http://DAPR_HOST:DAPR_PORT/v1.0/invoke/<app-id>/method/<path>`

In Docker Compose, `DAPR_HOST=0.0.0.0` for backends; `DAPR_HOST=127.0.0.1` for frontends (sharing a network namespace with their sidecar).

**Frontend → Backend calls**: Next.js does NOT call backend HTTP directly. It uses `DaprClient.invoker.invoke()` targeting the backend's Dapr app-id (`backend-ts`). See `app/web-nextjs/src/services/backend-ts.ts`.

### Shared SDK (`@sos/sdk`)
The SDK is the core abstraction layer. Key patterns:
- `buildServiceContext()` — creates context with logger, DB client, Dapr client; used at service startup. Fetches secrets from Dapr secretstore to configure DB credentials.
- `buildHandlerContext()` — enriches context per request handler (dependency injection pattern)
- `Context<K>` — generic type-safe service context parameterized by API kind (`K`)
- Modules: `Api`, `Dapr`, `Db`, `State`, `PubSub`, `Secrets`, `Cache`, `Consumer`, `Invoke`, `Metrics`

### Backend Layering (handler → service → model)
Each backend feature follows a strict three-layer architecture:
- **Handler** (`src/handlers/api/`) — express-zod-api endpoint. Defines Zod input/output schemas, calls service, wraps response with `buildResponse()`. Each handler function takes `Context` and returns an endpoint.
- **Service** (`src/services/`) — business logic. Orchestrates DB transactions, state cache invalidation (`State.destroy`), and pub/sub publishing (`PubSub.publish`). Write operations use Knex transactions with explicit commit/rollback.
- **Model** (`src/models/`) — database access via Knex query builder. Maps between DB column names (`snake_case`) and API model names (`camelCase`) via `asModel()` functions. Soft deletes via `deleted_at` column — queries filter `WHERE deleted_at IS NULL`.

### API Layer (backend-ts)
- `express-zod-api` for type-safe routing with Zod schemas for all input/output
- Express listens on a Unix socket (`/tmp/express-*.sock`); Dapr sidecar manages the external port
- `endpointsFactory` adds helmet, auth middleware, request ID, and metrics to every endpoint
- OpenAPI spec auto-generated at `/public/openapi.yaml`, Swagger UI at `/docs`
- JWT auth: tokens signed with `JWT_SECRET_KEY`, user extracted per-request via `AuthMiddleware`
- API responses use a standard envelope: `{ apiVersion, data, error }` — see `Api.buildResponse()`

### State & Pub/Sub Patterns
- **Read-through cache**: On `getById`, save to Redis state store after DB fetch. On writes, destroy the cache key to invalidate.
- **Event publishing**: All write operations (create/update/delete) publish to `todo-data` topic for downstream consumers.
- Cache keys follow format: `<stateName>:<tableName>:<id>`

### Database
- PostgreSQL 18 with Knex.js for migrations and query building
- Schema per service: `backend_ts` (prod), `backend_ts_test` (integration tests) — the `_test` suffix is auto-appended when `NODE_ENV=test`
- Migrations live in `app/backend-ts/src/db/migrations/`
- DB credentials come from Dapr secretstore (not env vars) — see `buildServiceContext()` in SDK

### Testing (three-layer pyramid)
- **Unit** (`make test`, seconds): `*.test.ts` — Vitest with mocked Dapr and SDK context (see `vitest.setup.ts`). Covers backend-ts, SDK, and web-nextjs (`services/backend-ts.test.ts` covers the Dapr invoker path with mocked `DaprClient`).
- **Integration** (`make test-integration`, tens of seconds): `*.integration.test.ts` — real Postgres + Dapr sidecar. Tables truncated between tests. `maxConcurrency: 1` to avoid DB race conditions.
- **E2E** (`make e2e`, minutes): `e2e/e2e-test.sh` — compose-based smoke. Brings up the full stack, exercises backend direct + via Dapr sidecar, verifies 5 service endpoints (Next.js SSR, Swagger, Dapr Dashboard, Zipkin, Grafana), asserts scheduler TCP reachability, covers negative cases (401 no-auth, 404 nonexistent). Optional browser layer: `make e2e-browser` (Playwright against `localhost:3000`).
- **Markdown / diagrams** (`make mermaid-lint`, seconds): validates every `` ```mermaid `` block in `README.md` / `CLAUDE.md` / `docs/*.md` via pinned `minlag/mermaid-cli` (same engine GitHub renders with). Wired into `make lint` — catches broken Mermaid diagrams before they silently break README rendering on github.com.
- Framework: Vitest 4 with supertest for HTTP testing
- Test helpers: `getAuthHeader()` generates JWT tokens, `expectApiDataResponse()`/`expectApiError()` for assertions

### CI Pipeline (`.github/workflows/ci.yml`)
Each CI job calls a dedicated Makefile target (`make sdk-ci`, `make backend-lint`, etc.). SDK compiles first and its `build/` artifact is shared with downstream jobs:
1. **SDK** (`make sdk-ci`): compile → lint → unit tests → upload `sdk-build` artifact
2. **Backend** (parallel, depends on SDK): `make backend-lint`, `make backend-test`, `make backend-test-integration` (with Postgres service + Dapr sidecar)
3. **Frontend** (parallel, no SDK dependency): `make web-nextjs-ci` (lint + Vitest + build)
4. **E2E** (depends on backend-integration + web-nextjs): builds service images, `docker compose up -d`, runs `e2e/e2e-test.sh`

### Port allocation in CI / parallel runs
Service ports default to the values in `.env.example` (3000, 3001, 3500, …). For parallel test runs on the same host (two local runs, parallel CI jobs), use `scripts/pick-port.sh` (returns one free port) or `scripts/write-env-ports.sh` (writes an env file or `$GITHUB_ENV` with free ports for every service). Node code reads all ports from `process.env.*` — see `app/backend-ts/src/config.ts` and `app/web-nextjs/src/config.ts`. Never hardcode a port in new code.

### Observability
- **Logging**: Pino with structured JSON; log level via `LOG_LEVEL` env var
- **Tracing**: OpenTelemetry SDK auto-instrumentation, exported to Zipkin (port 9411) and OTLP endpoint
- **Metrics**: Per-endpoint counters and timers via `@sos/sdk` metrics module, recorded in `apiResultsHandler`
- Instrumentation loaded via `--import ./src/lib/instrumentation.ts` flag (must be first)

## Key Environment Variables

| Variable | Service | Default | Notes |
|---|---|---|---|
| `SERVICE_NAME` | backend | `backend-ts` | Dapr app-id |
| `DAPR_HOST` | all | `localhost` | Sidecar host |
| `DAPR_PORT` | all | `3500` | Sidecar HTTP port |
| `JWT_SECRET_KEY` | backend, web-nextjs | `secret` | JWT signing key |
| `DB_HOST/PORT/NAME/SCHEMA` | backend | postgres/5432/postgres/backend_ts | |
| `OTLP_ENDPOINT` | all | — | OpenTelemetry collector URL |
| `NODE_ENV` | all | `development` | `test` appends `_test` to DB schema |

## Workflow Rules

### Before Every Commit
Always verify locally before committing and pushing. All Makefile targets must pass:
```bash
make compile           # compile SDK + backend TypeScript
make lint              # lint + typecheck + prettier across all workspaces
make test              # unit tests with coverage (SDK + backend)
make ci                # full local CI pipeline (lint + test + build)
make ci-run            # run GitHub Actions workflow locally via act
make build             # rebuild service containers
make up -d             # start the stack (detached)
make test-integration  # integration tests (requires running stack)
```
Verify all URLs from the README "Start, test, stop" section are reachable and return expected results:
- `http://localhost:3000` — Next.js SSR frontend loads HTML
- `http://localhost:3001/docs` — Swagger UI loads in browser
- `http://localhost:8888` — Dapr Dashboard loads
- `http://localhost:9411` — Zipkin tracing loads

Verify the "Calling the Backend API" section works:
```bash
TOKEN=$(node -e "console.log(require('jsonwebtoken').sign({sub:'dev-user'}, 'secret'))")
curl -sf -H "Authorization: Bearer $TOKEN" http://localhost:3001/api/v1/todos
curl -sf -H "Authorization: Bearer $TOKEN" http://localhost:3500/v1.0/invoke/backend-ts/method/api/v1/todos
```
Both should return a JSON response with `apiVersion` and `data`.

After pushing, watch the remote CI run to confirm it passes:
```bash
gh run watch           # watch the latest CI run
```

### Keep Documentation Up to Date
After any code or configuration change, review and update the project's `*.md` files if affected. This includes `README.md`, `CLAUDE.md`, service READMEs, and docs in `docs/`. Version numbers, command references, architecture descriptions, and environment variable tables must stay in sync with the code.

## Adding a New Service

See `docs/create-new-service.md` and use the scaffolds in `scaffolds/` directory. Each service needs: app container + Dapr sidecar container in its `docker-compose.yaml`.

### Dockerfile Base Image Strategy

Two patterns coexist by design:
- **Prod Dockerfiles** (`Dockerfile`) — use `node:24-alpine@sha256:...` pinned digest. Renovate auto-updates these. No `make setup` needed.
- **Dev Dockerfiles** (`Dockerfile.dev`) — use `microservice-build` or `microservice-sdk-build` local images (built via `make setup`). These inject corporate certificates and pre-compile the SDK for the monorepo workspace pattern.

## Upgrade Backlog

Items from upgrade analyses that need monitoring or future action:

- [ ] **Dapr Dashboard** — v0.15.0 (Sep 2024) is the latest stable release; no action until a newer version is published (carried from 2026-04-05)
- [ ] **pg (node-postgres)** — solo maintainer (Brian Carlson), 500+ open issues; healthy but bus-factor risk — monitor for succession or fork activity (carried from 2026-04-05)
- [ ] **Azure Postgres Flexible Server at PG 17** — local dev runs PG 18; bump the `infra/azure` default when Azure adds PG 18 support.
- [ ] **Next.js `/_global-error` prerender bug** — upstream [vercel/next.js#87719](https://github.com/vercel/next.js/issues/87719) (recurring across 16.0.3, 16.0.8, 16.1.1, 16.2.x). Worked around by defining `app/web-nextjs/src/app/global-error.tsx` — the existence of a user-defined `global-error.tsx` prevents Next.js from synthesizing the broken internal route. Bug manifests only on CI (3 workers) not locally (8 workers). Remove the workaround if Next.js publishes a fix with a "won't regress" commitment; until then keep the file — it's also best practice for prod error UX.

## Skills

Use the following skills when working on related files:

| File(s) | Skill |
|---------|-------|
| `Makefile` | `/makefile` |
| `renovate.json` | `/renovate` |
| `README.md` | `/readme` |
| `.github/workflows/*.{yml,yaml}` | `/ci-workflow` |

When spawning subagents, always pass conventions from the respective skill into the agent's prompt.
