# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Dapr-based microservices platform using Node.js/TypeScript with pnpm workspaces (monorepo). Services communicate through Dapr sidecars for state management, pub/sub, and service invocation. Container runtime is Podman (Docker-compatible).

## Common Commands

### Workspace Commands

This is a pnpm workspace monorepo. Run commands from repo root using `--filter`:

```bash
pnpm --filter backend-ts run test         # Run in specific workspace
pnpm --filter @sos/sdk run compile        # SDK must be compiled before backend
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
make lint           # Lint + typecheck (also: hadolint, scripts +x, terraform validate, mermaid, dockerfile runtime-pnpm guard)
make vulncheck      # pnpm audit (fails on moderate+)
make secrets        # gitleaks scan
make trivy-fs       # Trivy filesystem CVE/secret/misconfig scan
make static-check   # Composite gate — lint (includes mermaid-lint) + vulncheck + secrets + trivy-fs
make test           # Unit tests across SDK + backend (with coverage)
make ci             # Full CI pipeline locally (static-check + test + build)

# Test (containers needed)
make integration-test # Backend integration tests (requires Postgres + Dapr)
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
pnpm run dev              # Hot reload dev server (runs DB migrations first)
pnpm run compile          # TypeScript compilation
pnpm run ci               # tsc --noEmit + lint + prettier
pnpm run test             # Unit tests (Vitest, watch mode)
pnpm run test:cov         # Unit tests with coverage (single run)
pnpm run test:integration # Integration tests (requires Postgres + Dapr sidecar)
pnpm run knex -- migrate:make <name>  # Create new DB migration
pnpm run knex -- migrate:latest       # Run pending migrations

# Run a single test file
cd app/backend-ts && pnpm exec vitest --config src/lib/test/vitest.config.ts run src/services/todo.test.ts
# Run a single integration test
cd app/backend-ts && NODE_ENV=test pnpm exec vitest --config src/lib/test/vitest.integration.config.ts run src/handlers/api/todo.integration.test.ts
```

### Frontend (`app/web-nextjs`)

```bash
pnpm run dev    # Next.js dev server
pnpm run build  # Production build (requires JWT_SECRET_KEY env var)
pnpm run lint   # eslint .
pnpm run test   # Vitest unit tests (watch mode)
pnpm run test:cov # Vitest unit tests with coverage (single run)
```

### Shared SDK (`packages/@sos/sdk`)

```bash
pnpm run compile  # tsc --build (must run before backend compiles/tests)
pnpm run test     # Vitest unit tests
pnpm run ci       # tsc --noEmit + lint + prettier
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

| Service                   | Host Port | Access                                                    |
| ------------------------- | --------- | --------------------------------------------------------- |
| Next.js SSR frontend      | 3000      | `http://localhost:3000`                                   |
| Swagger UI                | 3001      | `http://localhost:3001/docs`                              |
| Backend API (direct)      | 3001      | `http://localhost:3001/api/v1/todos`                      |
| Backend API (via Dapr)    | 3500      | `http://localhost:3500/v1.0/invoke/backend-ts/method/...` |
| PostgreSQL                | 5432      |                                                           |
| Redis                     | 6379      |                                                           |
| Zipkin                    | 9411      | `http://localhost:9411`                                   |
| Dapr Dashboard            | 8888      | `http://localhost:8888`                                   |
| Grafana OTEL (if enabled) | 3200      | `http://localhost:3200`                                   |

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
- **Integration** (`make integration-test`, tens of seconds): `*.integration.test.ts` — real Postgres + Dapr sidecar. Tables truncated between tests. `maxConcurrency: 1` to avoid DB race conditions.
- **E2E** (`make e2e`, minutes): `e2e/e2e-test.sh` — compose-based smoke. Brings up the full stack, exercises backend direct + via Dapr sidecar, verifies 5 service endpoints (Next.js SSR, Swagger, Dapr Dashboard, Zipkin, Grafana), asserts scheduler TCP reachability, covers negative cases (401 no-auth, 404 nonexistent). Optional browser layer: `make e2e-browser` (Playwright against `localhost:3000`).
- **Markdown / diagrams** (`make mermaid-lint`, seconds): validates every ` ```mermaid ` block in `README.md` / `CLAUDE.md` / `docs/*.md` via pinned `minlag/mermaid-cli` (same engine GitHub renders with). Wired into `make lint` — catches broken Mermaid diagrams before they silently break README rendering on github.com.
- Framework: Vitest 4 with supertest for HTTP testing
- Test helpers: `getAuthHeader()` generates JWT tokens, `expectApiDataResponse()`/`expectApiError()` for assertions

### CI Pipeline (`.github/workflows/ci.yml`)

Each CI job delegates to a Makefile target. The `changes` detector (using `dorny/paths-filter`) gates heavy jobs so doc-only PRs skip the build/test matrix while still triggering the workflow (Repository Rulesets gating on `ci-pass` are satisfied either way). Job order:

1. **changes**: detect whether the PR touches code (vs. docs/images only)
2. **build** (`make sdk-ci`): compile + lint + unit-test the SDK; upload `sdk-build` artifact
3. **static-check** (`make static-check`, depends on build): composite gate — `lint` (which includes `mermaid-lint`) + `vulncheck` + `secrets` (gitleaks) + `trivy-fs`
4. **test** (`make backend-test`, depends on build): backend unit tests with coverage
5. **integration-test** (`make backend-test-integration`, depends on build): Postgres service + Dapr sidecar, real DB, real Dapr
6. **web-nextjs** (`make web-nextjs-ci`, depends on changes): lint + Vitest + Next.js production build
7. **e2e** (depends on integration-test + web-nextjs): docker compose build/up/test/down via `e2e/e2e-test.sh`
8. **ci-pass**: aggregate gate — fails if any of the above failed or was cancelled

### Port allocation in CI / parallel runs

Service ports default to the values in `.env.example` (3000, 3001, 3500, …). For parallel test runs on the same host (two local runs, parallel CI jobs), use `scripts/pick-port.sh` (returns one free port) or `scripts/write-env-ports.sh` (writes an env file or `$GITHUB_ENV` with free ports for every service). Node code reads all ports from `process.env.*` — see `app/backend-ts/src/config.ts` and `app/web-nextjs/src/config.ts`. Never hardcode a port in new code.

### Observability

- **Logging**: Pino with structured JSON; log level via `LOG_LEVEL` env var
- **Tracing**: OpenTelemetry SDK auto-instrumentation, exported to Zipkin (port 9411) and OTLP endpoint
- **Metrics**: Per-endpoint counters and timers via `@sos/sdk` metrics module, recorded in `apiResultsHandler`
- Instrumentation loaded via `--import ./src/lib/instrumentation.ts` flag (must be first)

## Key Environment Variables

| Variable                   | Service             | Default                           | Notes                               |
| -------------------------- | ------------------- | --------------------------------- | ----------------------------------- |
| `SERVICE_NAME`             | backend             | `backend-ts`                      | Dapr app-id                         |
| `DAPR_HOST`                | all                 | `localhost`                       | Sidecar host                        |
| `DAPR_PORT`                | all                 | `3500`                            | Sidecar HTTP port                   |
| `JWT_SECRET_KEY`           | backend, web-nextjs | `secret`                          | JWT signing key                     |
| `DB_HOST/PORT/NAME/SCHEMA` | backend             | postgres/5432/postgres/backend_ts |                                     |
| `OTLP_ENDPOINT`            | all                 | —                                 | OpenTelemetry collector URL         |
| `NODE_ENV`                 | all                 | `development`                     | `test` appends `_test` to DB schema |

## Workflow Rules

### Before Every Commit

Always verify locally before committing and pushing. All Makefile targets must pass:

```bash
make compile           # compile SDK + backend TypeScript
make lint              # lint + typecheck + prettier + hadolint + mermaid + scripts +x guard + dockerfile runtime-pnpm guard
make static-check      # composite gate (lint [includes mermaid-lint] + vulncheck + secrets + trivy-fs)
make test              # unit tests with coverage (SDK + backend)
make ci                # full local CI pipeline (static-check + test + build)
make ci-run            # run GitHub Actions workflow locally via act (skips e2e/mermaid-lint/secrets — see notes)
make build             # rebuild service containers
make up -d             # start the stack (detached)
make integration-test  # integration tests (requires running stack)
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

### Fast-track a transitive CVE without waiting for the parent ecosystem

When `make vulncheck` (`pnpm audit --audit-level=moderate`) flags a CVE in a **transitive** dependency (the vulnerable package is pulled in by some other dep, not declared directly), the fastest fix is a `pnpm.overrides` entry in the root `package.json`. This forces every workspace's lockfile resolution to use the patched version, without waiting for the parent dep to bump its own range.

```jsonc
// package.json
{
  "pnpm": {
    "overrides": {
      // semver-range key: any version matching the LHS resolves to the RHS
      "protobufjs@<8.0.2": ">=8.0.2"
    }
  }
}
```

Then `pnpm install` regenerates the lockfile with the patched transitive. `pnpm audit` confirms the clearance.

When to use:
- **Use override** when the CVE is in a transitive (e.g., `protobufjs` reached via `@opentelemetry/exporter-metrics-otlp-proto → @opentelemetry/otlp-transformer`) and the parent hasn't shipped a bump yet, OR the parent's bump would be a major upgrade you're not ready for.
- **Bump directly** when the CVE is in a workspace's own direct dependency (e.g., `next` in `app/web-nextjs/package.json`). An override hides the bump from Renovate and dependency-dashboard surfacing; bumping directly keeps the version visible.

Drop the override after the next routine Renovate bump pulls in the patched version organically; otherwise it sticks around forever as dead config. Renovate's `replacements:all` preset (already in our `config:best-practices`) helps surface these.

Real example: PR #198 (2026-05-13) added `protobufjs@<8.0.2` to clear three @opentelemetry/* CVEs at once; @opentelemetry's own bumps to 0.217.0 superseded the override on the same PR, so the override served only as a defense-in-depth pin against future regressions.

### Main-branch rot detection

Project CI (`.github/workflows/ci.yml`) runs only on `pull_request` / push-to-main / tag-push events. Without a periodic main-only run, two failure modes accumulate invisibly:

1. **Vuln advisory decay** — `pnpm audit` finds new upstream advisories for packages already in the lockfile.
2. **Latent regression decay** — a bug already on main only surfaces when a PR triggers a rebuild (e.g., the corepack/pnpm trap in `app/backend-ts/Dockerfile` was already wrong on `main` for ~10 days before any PR's image rebuild revealed it).

`.github/workflows/main-rot.yml` runs `make static-check` against `main` daily (07:00 UTC) plus on-demand via `workflow_dispatch`. A failure surfaces within 24h via GitHub workflow-failure email; no PR required.

To trigger manually: `gh workflow run main-rot.yml`.

Also, **GitHub Dependabot Alerts MUST stay enabled on this repo** (Settings → Security → Dependabot alerts). Renovate's `vulnerabilityAlerts` config block (with `automerge: true`, `minimumReleaseAge: "0 days"`) only fires when GitHub's Dependabot surfaces the CVE — if Alerts is disabled, Renovate has no trigger and CVEs sit unpatched indefinitely. Verify state via `gh api -X GET repos/AndriyKalashnykov/dapr-nodejs-nextjs/vulnerability-alerts` (204 = enabled).

## Adding a New Service

See `docs/create-new-service.md` and use the scaffolds in `scaffolds/` directory. Each service needs: app container + Dapr sidecar container in its `docker-compose.yaml`.

### Dockerfile Base Image Strategy

Two patterns coexist by design:

- **Prod Dockerfiles** (`Dockerfile`) — use `node:24-alpine@sha256:...` pinned digest. Renovate auto-updates these. No `make setup` needed.
- **Dev Dockerfiles** (`Dockerfile.dev`) — use `microservice-build` or `microservice-sdk-build` local images (built via `make setup`). These inject corporate certificates and pre-compile the SDK for the monorepo workspace pattern.

## Upgrade Backlog

Items from upgrade analyses that need monitoring or future action:

- [ ] **Dapr Dashboard** — v0.15.0 (Sep 2024) is the latest stable release; no action until a newer version is published (carried from 2026-04-05)
- [ ] **pg (node-postgres)** — solo maintainer (Brian Carlson), 500+ open issues; healthy but bus-factor risk — monitor for succession or fork activity (carried from 2026-04-05). **Re-checked 2026-05-02**: status materially unchanged; `charmander` continues as de-facto co-committer; sponsorship (Medplum, Timescale, GitHub) intact; `postgres.js` is the credible #2 driver. Next quarterly check: ~2026-08.
- [ ] **Drop Knex for typed query builder (Kysely)** — researched + planned 2026-05-02, deferred. Full phased plan in [`docs/migration-knex-to-kysely.md`](docs/migration-knex-to-kysely.md): Kysely on top of `pg` (driver swap to `postgres.js` is optional Phase 6). Total effort ~14h core, ~18h with driver swap. Codebase only has `models/todo.ts` + `services/todo.ts` as Knex consumers, so scope is small. Revisit triggers documented in the plan.
- [x] **Azure Postgres Flexible Server bumped to PG 18 (2026-05-02)** — Azure Flexible Server PG 18 GA'd 2025-12-01; `azurerm` provider accepts `version = "18"`. Bumped `infra/azure/variables.tf` + `infra/azure/modules/postgresql_flexible/variables.tf` defaults from `17` to `18` so Terraform-deployed infra now matches local dev. Project doesn't use blocked features (`io_method = io_uring` not set; no exotic extensions in migrations).
- [x] **Next.js `/_global-error` / `/_not-found` prerender crashes** — fixed 2026-04-16 by removing `NODE_ENV=development` from `.mise.toml [env]` (jdx/mise-action was leaking it into CI job env, overriding `next build`'s internal `NODE_ENV=production`). User-defined `app/global-error.tsx` + `app/not-found.tsx` kept as defense-in-depth + prod error UX. Upstream [vercel/next.js#87719](https://github.com/vercel/next.js/issues/87719) still open; watch for regressions in future Next.js minors.
- [x] **web-nextjs integration test layer** — added 2026-05-01 as the compose-attached pattern (option B). Tests live in `app/web-nextjs/src/**/*.integration.test.ts`, run via `make web-nextjs-integration` (or directly: `pnpm --filter web-nextjs run test:integration`), and `fetch()` against `http://localhost:${NEXTJS_PORT:-3000}` with a session cookie minted via `/api/auth`. Each suite probes the stack first via `isStackReachable()` and skips cleanly if `make up -d` hasn't been run. This exercises Next.js route → `verifySession()` → `BackendTs.getAll()` (real DaprClient) → web-nextjs sidecar → backend-ts sidecar → Express → Postgres — closes the gap between unit-mocked tests and Playwright e2e.
- [x] **PR #153 — comprehensive hardening pass — MERGED** ([d78d720](https://github.com/AndriyKalashnykov/dapr-nodejs-nextjs/commit/d78d720)) — squash-merged 2026-05-02 with all 9 CI jobs green. Final root cause: `app/backend-ts/dapr/components/subscriptions.yaml` had `apiVersion: dapr.io/v2alpha`; Dapr 1.17.6 only recognises `dapr.io/v2alpha1`. Silent 0-subscription load was masking pub/sub for a long time — the new probe was the first thing to exercise the round-trip end-to-end. (Originally noted here that the trace-propagation probe stayed WARN; verified PASSing end-to-end on 2026-05-13 — see "OTel trace propagation" entry below.)
- [ ] **act-skip guards** — added 2026-05-02 to `make mermaid-lint` (DinD bind-mount limitation), `make secrets` (gitleaks allowlist regex behaves differently in act runner), and `download-artifact` step in `ci.yml` (act's local artifact server panics on download). All guards are no-ops on real GitHub runners; they only short-circuit when `$ACT == 'true'` or `vars.ACT == 'true'`. Watch for parity drift if real CI starts failing where act now passes.
- [x] **GH_ACCESS_TOKEN argv exposure fixed (2026-05-02) + token rotated (user-confirmed 2026-05-13)** — Makefile `ci-run` recipe now passes `--secret GH_ACCESS_TOKEN` (env-only form) instead of `--secret GH_ACCESS_TOKEN=$VALUE`. The previous form put the token value into argv, where `ps -ef` exposed it to any local user. Exposure window: ~2026-04-29 (PR #120 introduced the leaky pattern) → 2026-05-02 (PR #158 fixed it). User rotated the credential ~2026-05-04; the previously-leaked value is invalid.
- [x] **e2e pub/sub probes — apiVersion typo (2026-05-02)** — fixed: `app/backend-ts/dapr/components/subscriptions.yaml` had `apiVersion: dapr.io/v2alpha` (the scaffold template correctly uses `v2alpha1`). Dapr 1.17.6 silently ignored the file because the apiVersion didn't match anything it recognized — `Loading Declarative Subscriptions…` was followed by zero subscription registrations, so the consumer endpoint was never bound to the `todo-data` topic. Both the round-trip and pub/sub-negative probes failed in CI for this reason; both are now restored to FAIL since they're real signals once the subscription works. (Originally noted here that the trace-propagation probe remained a separate WARN; verified PASSing 2026-05-13 — see "OTel trace propagation" entry below.) Separately, the probes' log-grep used a hardcoded `docker compose logs` invocation that returned 0 lines under local podman — fixed via PR #207 by resolving `CONTAINER_CMD` runtime-agnostically, restoring `bash e2e/e2e-test.sh` to 32/32 locally.
- [x] **Main-rot incident — landed 2026-05-13 (#198, #199, #200, #202)** — between 2026-05-02 (last green main) and 2026-05-13, two latent issues blocked 16 consecutive Renovate PRs. (1) Upstream advisories landed for `next` <16.2.5 (7 CVEs) + `protobufjs` <8.0.2 (prototype injection) + `@opentelemetry/{auto-instrumentations-node,sdk-node,exporter-prometheus}` <0.217.0 (3 CVEs). `pnpm audit` reported 23 vulns; `make vulncheck` rejected every PR. (2) A latent corepack-per-user trap in `app/backend-ts/Dockerfile` (runtime `CMD ["pnpm", "run", "start"]` after `USER node`) caused EACCES → exit 243 on every PR that triggered a docker rebuild. **Fix path**: #198 dropped pnpm from backend-ts runtime + bumped Next + OTel + added `pnpm.overrides.protobufjs@<8.0.2`. #199 dropped the redundant `.mise.toml` custom-regex (collisions with native `mise` manager) + derived Makefile `*_IMAGE` from compose at runtime (eliminated alpine 3.21 → 3.23 silent drift). #200 added nightly `main-rot.yml` (07:00 UTC `make static-check` against main + `workflow_dispatch`), enabled GitHub Dependabot Alerts via `gh api PUT vulnerability-alerts` (Renovate's `vulnerabilityAlerts` block was inert without this trigger), documented `pnpm.overrides` fast-path in CLAUDE.md, and added a `lint-docker-no-runtime-pnpm` Makefile guard wired into `make lint` (caught 3 latent scaffold-template bugs). #202 completed the pnpm v10 → v11 migration that Renovate's PR #182 left undone — moved `allowBuilds` + `overrides` from `package.json` to `pnpm-workspace.yaml`, replaced `.npmrc shamefully-hoist=true` with `publicHoistPattern: ['*']` (v11 silently ignores legacy locations).
- [x] **pnpm v10 → v11 migration (2026-05-13, #202)** — root `package.json packageManager` + 6 Dockerfiles + per-service `.npmrc` cleanup. Three v11 silent-ignore behaviors caught during this migration are documented as memories (`feedback_pnpm_major_migration.md`) and propagated to portfolio skills (claude-config PR #10 — `/upgrade-analysis`, `/harden-image-pipeline`, `/makefile`, `/ci-workflow`, `/renovate`).

## Session resume — 2026-05-13

End-of-session checkpoint for next session pickup. Working tree clean on `main` (tip: PR #202).

**Main is healthy.** All session PRs merged: #198 (unblock), #199 (renovate cleanup), #200 (prevention infrastructure), #202 (pnpm v11 migration). The 16-PR Renovate backlog drained — 10 PRs auto-merged after #198 lifted the block; the remaining stale PR (#190 OpenTelemetry) was closed as superseded.

**Prevention infrastructure** active:
- `.github/workflows/main-rot.yml` runs `make static-check` against `main` daily at 07:00 UTC + on-demand via `workflow_dispatch`. Triggered once manually 2026-05-13 to confirm end-to-end execution.
- GitHub Dependabot Alerts enabled (`gh api -X GET .../vulnerability-alerts` returns 204) — Renovate's `vulnerabilityAlerts` fast-track block is now actually firing-capable.
- `make lint` includes `lint-docker-no-runtime-pnpm` — blocks the corepack-trap pattern at lint-time.

**OTel trace propagation through Dapr invoker — RESOLVED 2026-05-13** (was carry-over). End-to-end verification via `bash e2e/e2e-test.sh` shows probe [7/8] passes: `✓ Trace propagation web-nextjs → backend-ts (W3C traceparent)`. Two mechanisms cooperate — `app/web-nextjs/src/services/backend-ts.ts` already calls `propagation.inject(otelContext.active(), headers)` and passes the headers through `DaprClient.invoker.invoke()`, AND the Dapr sidecars themselves propagate W3C traceparent natively between each other (verified: a single Zipkin trace contains a CLIENT span from web-nextjs's sidecar and a SERVER child span from backend-ts's sidecar). The earlier "still WARN / not urgent / gap is documented" notes were written before `propagation.inject` was wired into `services/backend-ts.ts`.

**Carry-over items still open**:
- **Dapr Dashboard v0.15.0 (Sep 2024)** is still latest stable — no action until a newer version publishes.
- **pg (node-postgres)** bus-factor — re-checked 2026-05-02; healthy. Next quarterly check ~2026-08.
- **Drop Knex for Kysely** — planned in [`docs/migration-knex-to-kysely.md`](docs/migration-knex-to-kysely.md), deferred. ~14h effort.

**Portfolio skill changes** (claude-config PR #10, 2026-05-13) ship five lessons from this incident to all projects using these skills: `/harden-image-pipeline` (no pnpm at production runtime CMD), `/makefile` (lint-docker-no-runtime-pnpm sub-target), `/ci-workflow` (main-rot detection workflow pattern + Dependabot Alerts requirement), `/upgrade-analysis` (pnpm major bump config-location audit), `/renovate` (cross-file dual-tracking-with-different-currentValues silent drift).

## Skills

Use the following skills when working on related files:

| File(s)                          | Skill          |
| -------------------------------- | -------------- |
| `Makefile`                       | `/makefile`    |
| `renovate.json`                  | `/renovate`    |
| `README.md`                      | `/readme`      |
| `.github/workflows/*.{yml,yaml}` | `/ci-workflow` |

When spawning subagents, always pass conventions from the respective skill into the agent's prompt.
