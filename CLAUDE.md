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
make lint           # Lint + typecheck (also: hadolint, scripts +x guard, terraform validate, dockerfile runtime-pnpm guard)
make mermaid-lint   # Validate every ```mermaid block in markdown via pinned minlag/mermaid-cli
make vulncheck      # pnpm audit (fails on moderate+)
make secrets        # gitleaks scan
make trivy-fs       # Trivy filesystem CVE/secret/misconfig scan
make cve-check      # CVE scans (vulncheck + trivy-fs) — tag-gated in CI + daily on main; NOT on every PR
make deps-prune-check # Fail if any workspace has unused dependencies (depcheck)
make static-check   # PR-path gate — check-toolchain-alignment + lint + mermaid-lint + diagrams-check + secrets + deps-prune-check (no CVE scan)
make test           # Unit tests across SDK + backend (with coverage)
make ci             # Full CI pipeline locally (format-check + static-check + cve-check + test + build)

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
pnpm run build  # Production build
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
- **Markdown / diagrams** (`make mermaid-lint`, seconds): validates every ` ```mermaid ` block in `README.md` / `CLAUDE.md` / `docs/*.md` via pinned `minlag/mermaid-cli` (same engine GitHub renders with). Wired into `make static-check` as a sibling of `lint` — catches broken Mermaid diagrams before they silently break README rendering on github.com.
- **C4 architecture diagrams** (`make diagrams` / `make diagrams-check`): the C4 **Context**, **Container**, and **Deployment** views are [C4-PlantUML](https://github.com/plantuml-stdlib/C4-PlantUML) sources in `docs/diagrams/*.puml`, rendered to committed PNGs under `docs/diagrams/out/` by `make diagrams` (pinned `plantuml/plantuml`, `PLANTUML_VERSION`). `make diagrams-check` (in `static-check`) is the drift gate: it re-renders and fails if the committed PNGs differ from current `.puml` source. C4-PlantUML gives proper C4 fidelity that Mermaid's experimental C4 renderer lacks; the **sequence diagram** stays inline Mermaid (GitHub renders it natively, no build step). `PLANTUML_VERSION` is intentionally NOT Renovate-tracked — the hosted app can't run `make diagrams` to regenerate the PNGs, so a tracked bump would sit RED on the drift gate; bump it manually (edit tag → `make diagrams` → commit source + PNGs together).
- Framework: Vitest 4 with supertest for HTTP testing
- Test helpers: `getAuthHeader()` generates JWT tokens, `expectApiDataResponse()`/`expectApiError()` for assertions

### CI Pipeline (`.github/workflows/ci.yml`)

Each CI job delegates to a Makefile target. The `changes` detector (using `dorny/paths-filter`) gates heavy jobs so doc-only PRs skip the build/test matrix while still triggering the workflow (Repository Rulesets gating on `ci-pass` are satisfied either way). Job order:

1. **changes**: detect whether the PR touches code (vs. docs/images only). Emits `code` and `docs` outputs; `docs/diagrams/**/*.puml` is re-included into `code` so a diagram-source edit runs `diagrams-check`
2. **build** (`make sdk-ci`): compile + lint + unit-test the SDK; upload `sdk-build` artifact
3. **static-check** (`make static-check`, depends on changes): PR-path gate — `check-toolchain-alignment` + `lint` + `mermaid-lint` + `diagrams-check` + `secrets` (gitleaks) + `deps-prune-check`. **No CVE scan** — CVE scanning is tag-gated (see job 8)
4. **test** (`make backend-test`, depends on build): backend unit tests with coverage
5. **integration-test** (`make backend-test-integration`, depends on build): Postgres service + Dapr sidecar, real DB, real Dapr
6. **web-nextjs** (`make web-nextjs-ci`, depends on changes): lint + Vitest + Next.js production build
7. **e2e** (depends on integration-test + web-nextjs): docker compose build/up/test/down via `e2e/e2e-test.sh`, then an OWASP ZAP baseline **DAST** scan (`make dast`) against the running stack
8. **cve-check** (**tag pushes only**): `make cve-check` — `pnpm audit` + Trivy **filesystem** scan. PRs skip it for speed; `main-rot.yml` runs it daily on `main` so vuln-advisory decay still surfaces within 24h
9. **docker** (**tag pushes only**; depends on changes + static-check + build + test + cve-check): matrix (`backend-ts`, `web-nextjs`) — build (amd64) → Trivy **image** scan → `make image-test` (container-structure-test) → `make image-smoke-test` → **push to `ghcr.io/<owner>/<repo>/<service>`** → cosign keyless sign → SBOM + SLSA provenance attestations (referrer-based). `provenance/sbom` stay `false` on the build-push so the GHCR "OS / Arch" tab renders
10. **mermaid-lint** (docs-only fast path): runs `make mermaid-lint` when a markdown-only change skips `static-check`, so README/CLAUDE Mermaid blocks stay validated
11. **ci-pass**: aggregate gate — fails if any of the above failed or was cancelled (tag-gated jobs are `skipped`, not failed, on non-tag pushes)

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
make lint              # lint + typecheck + prettier + hadolint + scripts +x guard + dockerfile runtime-pnpm guard + terraform validate
make static-check      # PR-path gate (check-toolchain-alignment + lint + mermaid-lint + diagrams-check + secrets + deps-prune-check; no CVE scan)
make cve-check         # CVE scans (pnpm audit + trivy-fs) — tag-gated in CI + daily on main
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

When `make vulncheck` (`pnpm audit --audit-level=moderate`) flags a CVE in a **transitive** dependency (the vulnerable package is pulled in by some other dep, not declared directly), the fastest fix is an `overrides` entry in **`pnpm-workspace.yaml`**. This forces every workspace's lockfile resolution to use the patched version, without waiting for the parent dep to bump its own range.

> **pnpm 11 moved overrides out of `package.json`.** The legacy
> `"pnpm": { "overrides": { … } }` block in `package.json` is **silently
> ignored** by pnpm 11 (`pnpm install` prints a one-line WARN and the
> override never applies — `pnpm audit` still fails). The live home is the
> `overrides:` map in `pnpm-workspace.yaml` (alongside `allowBuilds` and
> `publicHoistPattern`). See the header comment in that file.

```yaml
# pnpm-workspace.yaml
overrides:
  # semver-range key: any version matching the LHS resolves to the RHS
  'protobufjs@<8.0.2': '>=8.0.2'
```

Then `pnpm install` regenerates the lockfile with the patched transitive. `pnpm audit` (i.e. `make vulncheck`) confirms the clearance.

When to use:
- **Use override** when the CVE is in a transitive (e.g., `protobufjs` reached via `@opentelemetry/exporter-metrics-otlp-proto → @opentelemetry/otlp-transformer`) and the parent hasn't shipped a bump yet, OR the parent's bump would be a major upgrade you're not ready for.
- **Bump directly** when the CVE is in a workspace's own direct dependency (e.g., `next` in `app/web-nextjs/package.json`). An override hides the bump from Renovate and dependency-dashboard surfacing; bumping directly keeps the version visible.

Drop the override after the next routine Renovate bump pulls in the patched version organically; otherwise it sticks around forever as dead config. Renovate's `replacements:all` preset (already in our `config:best-practices`) helps surface these.

Real examples: PR #198 (2026-05-13) added `protobufjs@<8.0.2` to clear three @opentelemetry/* CVEs at once; @opentelemetry's own bumps to 0.217.0 superseded the override on the same PR, so the override served only as a defense-in-depth pin against future regressions. PR #375 (2026-06-13) added `esbuild@<0.28.1` (GHSA-gv7w-rqvm-qjhr HIGH + GHSA-g7r4-m6w7-qqqr LOW, reached via `tsx>esbuild` and `vitest>vite>esbuild`) to `pnpm-workspace.yaml` — a reminder that the `package.json` form would have been silently ignored by pnpm 11.

### Main-branch rot detection

Project CI (`.github/workflows/ci.yml`) runs only on `pull_request` / push-to-main / tag-push events. Without a periodic main-only run, two failure modes accumulate invisibly:

1. **Vuln advisory decay** — `pnpm audit` finds new upstream advisories for packages already in the lockfile.
2. **Latent regression decay** — a bug already on main only surfaces when a PR triggers a rebuild (e.g., the corepack/pnpm trap in `app/backend-ts/Dockerfile` was already wrong on `main` for ~10 days before any PR's image rebuild revealed it).

`.github/workflows/main-rot.yml` runs `make static-check cve-check` against `main` daily (07:00 UTC) plus on-demand via `workflow_dispatch`. It includes `cve-check` (which the PR/push `static-check` no longer does — CVE scanning is tag-gated) so vuln-advisory decay on `main` still surfaces within 24h. A failure surfaces via GitHub workflow-failure email; no PR required.

To trigger manually: `gh workflow run main-rot.yml`.

Also, **GitHub Dependabot Alerts MUST stay enabled on this repo** (Settings → Security → Dependabot alerts). Renovate's `vulnerabilityAlerts` config block (with `automerge: true`, `minimumReleaseAge: "0 days"`) only fires when GitHub's Dependabot surfaces the CVE — if Alerts is disabled, Renovate has no trigger and CVEs sit unpatched indefinitely. Verify state via `gh api -X GET repos/AndriyKalashnykov/dapr-nodejs-nextjs/vulnerability-alerts` (204 = enabled).

**`platformAutomerge` is intentionally `false` (do NOT flip it back to `true`).** `main` is gated by a Repository Ruleset requiring the `ci-pass` check. With GitHub-native platform automerge, Renovate arms the merge within ~1s and GitHub can complete it in the window *before* `ci-pass` registers as a pending check — so a red bump auto-merges and reddens `main` (the check-registration race). With `platformAutomerge: false` + `automerge: true`, Renovate merges via its own later run after re-confirming `ci-pass` is green. Prove any change here with a deliberately-red PR (it must NOT merge). Paired safety net: `check-toolchain-alignment` (first `static-check` gate) blocks a merge if a bump splits a mirrored version (Node/pnpm) across `.mise.toml` / `package.json` / Dockerfiles, and the `mise` manager now carries a 3-day `minimumReleaseAge` so grouped pnpm bumps land atomically.

## Adding a New Service

See `docs/create-new-service.md` and use the scaffolds in `scaffolds/` directory. Each service needs: app container + Dapr sidecar container in its `docker-compose.yaml`.

### Dockerfile Base Image Strategy

Two patterns coexist by design:

- **Prod Dockerfiles** (`Dockerfile`) — use `node:24-alpine@sha256:...` pinned digest. Renovate auto-updates these. No `make setup` needed.
- **Dev Dockerfiles** (`Dockerfile.dev`) — use `microservice-build` or `microservice-sdk-build` local images (built via `make setup`). These inject corporate certificates and pre-compile the SDK for the monorepo workspace pattern.

## Upgrade Backlog

Items genuinely waiting on upstream or scheduled for future revisit. Resolved items live in git history.

- [ ] **Dapr Dashboard** — v0.15.0 (Sep 2024) is the latest stable; no action until a newer version is published.
- [ ] **pg (node-postgres) bus-factor watch** — solo-maintained by Brian Carlson with 500+ open issues; sponsorship (Medplum, Timescale, GitHub) and `charmander` as de-facto co-committer keep it healthy. `postgres.js` is the credible #2 driver if succession stalls. Next quarterly check ~2026-08.
- [ ] **Next.js prerender regression watch** — upstream [vercel/next.js#87719](https://github.com/vercel/next.js/issues/87719) still open. `.mise.toml` carries a defensive comment to never set `NODE_ENV` (otherwise `next build`'s internal `NODE_ENV=production` is overridden and `/_global-error` / `/_not-found` crash at prerender). Watch for regressions in future Next.js minors.
- [ ] **act-skip parity watch** — `make mermaid-lint`, `make secrets`, and the `download-artifact` step in `ci.yml` short-circuit when `$ACT == 'true'` to work around DinD bind-mount, gitleaks-allowlist, and local-artifact-server limitations. All guards are no-ops on real GitHub runners. Watch for parity drift if real CI starts failing where act passes.

## Roadmap (discretionary — not upstream-blocked)

- **Drop Knex for Kysely** — researched + planned, deferred (a discretionary refactor, not waiting on upstream). Phased plan in [`docs/migration-knex-to-kysely.md`](docs/migration-knex-to-kysely.md): Kysely on top of `pg` (driver swap to `postgres.js` optional Phase 6). ~14h effort core, ~18h with driver swap. Only `models/todo.ts` + `services/todo.ts` are Knex consumers.

## Skills

Use the following skills when working on related files:

| File(s)                          | Skill          |
| -------------------------------- | -------------- |
| `Makefile`                       | `/makefile`    |
| `renovate.json`                  | `/renovate`    |
| `README.md`                      | `/readme`      |
| `.github/workflows/*.{yml,yaml}` | `/ci-workflow` |

When spawning subagents, always pass conventions from the respective skill into the agent's prompt.
