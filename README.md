[![CI](https://github.com/AndriyKalashnykov/dapr-nodejs-nextjs/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/AndriyKalashnykov/dapr-nodejs-nextjs/actions/workflows/ci.yml)
[![Hits](https://hits.sh/github.com/AndriyKalashnykov/dapr-nodejs-nextjs.svg?view=today-total&style=plastic)](https://hits.sh/github.com/AndriyKalashnykov/dapr-nodejs-nextjs/)
[![License: MIT](https://img.shields.io/badge/License-MIT-brightgreen.svg)](https://opensource.org/licenses/MIT)
[![Renovate enabled](https://img.shields.io/badge/renovate-enabled-brightgreen.svg)](https://app.renovatebot.com/dashboard#github/AndriyKalashnykov/dapr-nodejs-nextjs)

# Dapr Reference Stack — Node.js + Next.js + Azure Container Apps

Reference implementation of a Dapr-based stack on Node.js and TypeScript. A todo-list REST API backend (Express 5 + Postgres) and a Next.js SSR frontend are wired together through Dapr sidecars for state management (Redis), pub/sub messaging, and service-to-service invocation. Azure Container Apps is the production target (see `infra/azure/`); Docker Compose via Podman is the local dev loop.

```mermaid
C4Context
    title System Context — Dapr Node.js + Next.js

    Person(user, "End user", "Browser")
    System(sys, "Dapr Node.js + Next.js stack", "Reference Dapr-on-Node platform: SSR frontend + REST backend + Postgres + Redis (state/pubsub)")
    System_Ext(zipkin, "Zipkin", "Distributed tracing UI (OTel ingest)")
    System_Ext(otel, "Grafana OTEL stack", "Optional logs + metrics + traces (`make up-otel`)")

    Rel(user, sys, "Uses", "HTTPS / HTML / JSON")
    Rel(sys, zipkin, "Spans", "OTLP/HTTP")
    Rel(sys, otel, "Logs + metrics + traces", "OTLP/HTTP")

    UpdateLayoutConfig($c4ShapeInRow="3", $c4BoundaryInRow="1")
```

The hero diagram is intentionally Context-level (one box): "what is this and who uses it?". The internal containers (`web-nextjs`, `backend-ts`, Dapr sidecars, Postgres, Redis) are drawn at Container level under [Architecture](#architecture).

## Tech Stack

| Component          | Technology                                                                     |
| ------------------ | ------------------------------------------------------------------------------ |
| Language           | TypeScript 6 / Node.js 24                                                      |
| Backend framework  | Express 5 + `express-zod-api`                                                  |
| Frontend framework | Next.js 16 (App Router, SSR)                                                   |
| Database           | PostgreSQL 18 + Knex.js migrations                                             |
| Dapr runtime       | Dapr 1.17.6 runtime, CLI 1.17.1 (placement + scheduler + sidecar per service)  |
| State / pub/sub    | Redis 8                                                                        |
| Auth               | JWT via `jsonwebtoken` (dev secret in `.env`)                                  |
| Observability      | OpenTelemetry SDK → Zipkin + Grafana OTEL stack                                |
| Tests              | Vitest 4 (unit + integration), shell-based compose e2e, Playwright browser e2e |
| Container runtime  | Podman 4.9+ (Docker-compatible); `docker compose` in CI                        |
| Monorepo           | pnpm workspaces (`app/*`, `packages/@sos/*`)                                   |
| Production target  | Azure Container Apps (`infra/azure/`, Terraform)                               |

## Quick Start

```bash
make deps && make install && make setup   # install tools, pnpm packages, base images
make build                                # build service containers
make up                                   # start the full stack (Ctrl-C to stop)
```

## Prerequisites

| Tool                                           | Version | Purpose                                                                                                                       |
| ---------------------------------------------- | ------- | ----------------------------------------------------------------------------------------------------------------------------- |
| [GNU Make](https://www.gnu.org/software/make/) | 3.81+   | Build orchestration                                                                                                           |
| [Git](https://git-scm.com/)                    | 2.30+   | Version control                                                                                                               |
| [mise](https://mise.jdx.dev/)                  | latest  | Cross-language version manager (single source of truth: `.mise.toml`). Manages Node, pnpm, Dapr CLI, act, hadolint, terraform |
| [Podman](https://podman.io/docs/installation)  | 4.9+    | Container runtime (Docker-compatible) with Compose                                                                            |

Install mise once with `curl https://mise.run | sh` (Linux) or `brew install mise` (macOS); then `make deps` runs `mise install` to fetch all mise-managed tools and installs podman + git via the OS package manager.

Install all required dependencies:

```bash
make deps
```

<details>
<summary>Linux: Podman setup</summary>

```bash
sudo apt-get -y install podman docker-compose-plugin
systemctl --user enable --now podman.socket
export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/podman/podman.sock"
```

</details>

<details>
<summary>macOS: Podman setup</summary>

Podman on macOS runs inside a lightweight VM. Install via Homebrew, initialize and start the VM, then point Docker-compatible tools at the Podman socket:

```bash
brew install podman
podman machine init --cpus 4 --memory 8192 --disk-size 50
podman machine start

# Expose the VM's socket as a Docker-compatible endpoint
export DOCKER_HOST="unix://$(podman machine inspect --format '{{.ConnectionInfo.PodmanSocket.Path}}')"
```

Optional: install Podman Desktop (`brew install --cask podman-desktop`) for a GUI. For `docker compose` parity install the compose plugin: `brew install docker-compose`.

Apple Silicon (M1/M2/M3): the above works natively; the VM defaults to `arm64`. If an image only ships `amd64`, prefix with `podman --arch=amd64` or pull with `--platform linux/amd64`.

</details>

<details>
<summary>Windows: Podman setup</summary>

Install [Podman Desktop](https://podman-desktop.io/) and enable the "Compose" extension.

</details>

## Architecture

Each service runs as **two containers**: the app + a Dapr sidecar (`daprd`) in a shared network namespace. All cross-service communication goes through the sidecar — never directly app-to-app.

```mermaid
C4Container
    title Container View — Dapr microservices stack

    Person(user, "End user", "Browser")

    System_Boundary(sys, "Dapr microservices") {
        Container(nextjs, "web-nextjs", "Next.js 16, Node.js 24", "SSR frontend, REST proxy via Dapr invoker")
        Container(nextjs_dapr, "Dapr sidecar (web-nextjs)", "Dapr 1.17.6", "State + pub/sub + service invocation")
        Container(backend, "backend-ts", "Express 5, Node.js 24", "REST API with express-zod-api, layered handler/service/model")
        Container(backend_dapr, "Dapr sidecar (backend-ts)", "Dapr 1.17.6", "State + pub/sub + service invocation")
        ContainerDb(postgres, "Postgres", "PostgreSQL 18", "Primary datastore (Knex migrations, soft delete)")
        ContainerDb(redis, "Redis", "Redis 8", "State store + pub/sub broker (todo-data topic)")
    }

    System_Ext(zipkin, "Zipkin", "Distributed tracing UI (W3C traceparent)")

    Rel(user, nextjs, "HTTPS / HTML", "browser → SSR")
    Rel(nextjs, nextjs_dapr, "DaprClient.invoker.invoke()", "HTTP")
    Rel(nextjs_dapr, backend_dapr, "v1.0/invoke/backend-ts/method/...", "HTTP")
    Rel(backend_dapr, backend, "Routes invoke + consumer", "HTTP")
    Rel(backend, postgres, "Read/write todos", "TCP/pgwire (knex)")
    Rel(backend_dapr, redis, "State + pub/sub", "TCP")
    Rel(nextjs, zipkin, "Spans", "OTLP/HTTP")
    Rel(backend, zipkin, "Spans", "OTLP/HTTP")

    UpdateLayoutConfig($c4ShapeInRow="3", $c4BoundaryInRow="1")
```

A few facts not visible on the picture:

- All cross-service traffic flows **app → sidecar → sidecar → app**, never direct app-to-app — the Dapr sidecar handles service discovery, retries, mTLS in cluster modes, and W3C traceparent propagation. See [ADR-0001](./docs/adr/0001-dapr-sidecar.md).
- `backend-ts` is the only writer of Postgres. The sidecar's `redis-statestore` component implements a read-through cache; on writes the cache key is invalidated and a `todo-data` CloudEvent is published. See [ADR-0003](./docs/adr/0003-redis-state-pubsub.md).
- `web-nextjs` does **not** call `backend-ts` HTTP directly. See `app/web-nextjs/src/services/backend-ts.ts` for the Dapr invoker shape.

### Key patterns

- **Service invocation**: `web-nextjs` calls `backend-ts` via `context.dapr.invoker.invoke('backend-ts', 'api/v1/todos', ...)`. The sidecar handles discovery, retries, and tracing — no direct HTTP.
- **State + read-through cache**: On `GET /todos/:id`, the backend fetches from Postgres, then writes to Redis via the Dapr state store. On writes, the cache key is invalidated.
- **Pub/sub**: Write operations publish a `todo-data` CloudEvent via Redis. The consumer subscribes via `app/backend-ts/dapr/components/subscriptions.yaml` and receives at `/consumer/todo-data`.
- **Auth**: JWT bearer tokens signed with `JWT_SECRET_KEY`. Backend extracts the user per request via `AuthMiddleware`.
- **Layered backend**: handler (`express-zod-api` route) → service (business logic, state invalidation, pub/sub) → model (Knex query builder).

### Write path: `POST /todos`

The most non-obvious runtime behaviour — JWT auth, Dapr invocation, state-cache invalidation, and pub/sub fan-out — happens on a single create. The sequence below traces a `POST /todos` from the SSR frontend through to the consumer; ADR notes for the broker choice are in [docs/adr/](./docs/adr/README.md).

```mermaid
sequenceDiagram
    autonumber
    participant U as Browser
    participant N as web-nextjs
    participant Nd as Dapr sidecar (web-nextjs)
    participant Bd as Dapr sidecar (backend-ts)
    participant B as backend-ts
    participant P as Postgres
    participant R as Redis (state + pub/sub)
    participant C as todo-consumer

    U->>N: POST /api/todos { title } (cookie-auth)
    N->>N: AuthMiddleware → JWT(sub=userId)
    N->>Nd: dapr.invoker.invoke('backend-ts', 'api/v1/todos')
    Nd->>Bd: HTTP /v1.0/invoke/backend-ts/method/api/v1/todos
    Bd->>B: forward + W3C traceparent
    B->>P: INSERT todo (knex transaction)
    P-->>B: row
    B->>Bd: PubSub.publish('todo-data', cloudevent)
    Bd->>R: XADD todo-data
    B->>Bd: State.destroy('state.todos:{id}')
    Bd->>R: DEL state.todos:{id}
    B-->>Bd: 200 { apiVersion, data: { id, title, completed:false, createdAt } }
    Bd-->>Nd: 200
    Nd-->>N: 200
    N-->>U: 200 (proxied)

    R-->>Bd: deliver todo-data CloudEvent (subscription)
    Bd->>C: POST /consumer/todo (cloudevents+json)
    C-->>Bd: 200 { status: SUCCESS }
```

### Calling the Backend API

The backend requires a JWT token. Generate one and call the API:

```bash
# Generate a dev token (JWT_SECRET_KEY matches docker-compose: "secret")
TOKEN=$(node -e "console.log(require('jsonwebtoken').sign({sub:'dev-user'}, 'secret'))")

# Direct access (port 3001)
curl -H "Authorization: Bearer $TOKEN" http://localhost:3001/api/v1/todos
curl -X POST -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"title":"My todo"}' http://localhost:3001/api/v1/todos

# Via Dapr service invocation (port 3500)
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:3500/v1.0/invoke/backend-ts/method/api/v1/todos
```

## Operations

```bash
# First time only
make deps           # Bootstrap mise + check podman + git
make install        # Install pnpm dependencies
make setup          # Build base Docker images (run once after clone)

# Start
make build          # Build all service containers in parallel
make up             # Bring up the full stack (Ctrl-C to stop)

# Test — three-layer pyramid
#   unit (seconds, no containers)
make test              # Vitest unit tests — SDK + backend + web-nextjs
make lint              # Lint + typecheck across all workspaces
make static-check      # Composite quality gate (lint [includes mermaid-lint] + vulncheck + secrets + trivy-fs + deps-prune-check)
make ci                # Full local CI (format-check + static-check + test + build)

#   integration (tens of seconds, needs Postgres + Dapr sidecar)
make integration-test  # Backend integration tests (real DB + real sidecar)

#   e2e (minutes, full compose stack)
make e2e               # `make up -d` + e2e/e2e-test.sh + `make down`
make e2e-browser       # Playwright browser tests (stack must already be up)
make dast              # ZAP baseline DAST scan against the running stack

# Stop
make down           # Tear down the full stack
```

Once running, services are available at:

| Service                | URL                                                              |
| ---------------------- | ---------------------------------------------------------------- |
| Next.js SSR frontend   | http://localhost:3000                                            |
| Swagger UI             | http://localhost:3001/docs                                       |
| Backend API (direct)   | http://localhost:3001/api/v1/todos                               |
| Backend API (via Dapr) | http://localhost:3500/v1.0/invoke/backend-ts/method/api/v1/todos |
| Dapr Dashboard         | http://localhost:8888                                            |
| Zipkin tracing         | http://localhost:9411                                            |
| PostgreSQL             | localhost:5432 (user/pass: `postgres`)                           |

### Environment configuration

Every port, host, and feature flag the services read comes from env vars. For local dev, copy `.env.example` → `.env` (both at repo root) and edit as needed. The defaults match what `docker-compose.yaml` exposes (3000, 3001, 3500, 5432, 6379, 9411, 8888, 50005, 50006, 3200, 4318). Never hardcode ports in new code — read `process.env.*` with a documented default.

For parallel test runs on the same host, `scripts/pick-port.sh` returns one free port and `scripts/write-env-ports.sh` writes an env file with free ports for every service (safe to append to `$GITHUB_ENV` in CI).

## Deployment (Azure Container Apps)

Production target is Azure Container Apps, defined in `infra/azure/`. Terraform provisions: ACA environment + two Container Apps (`backend-ts`, `web-nextjs`, both Dapr-enabled, both external ingress), Azure Cache for Redis, PostgreSQL Flexible Server, Key Vault (with Dapr `azure.keyvault` secretstore component), ACR, VNet + private endpoints, and Application Insights.

```bash
# One-time OIDC federation setup — see docs/deploy-aca.md
# Then:
make e2e-aca   # terraform apply → deploy → smoke → terraform destroy
```

The matching workflow (`.github/workflows/e2e-aca.yml`) runs on `workflow_dispatch` only (Actions → "E2E (ACA)" → Run workflow). It is not triggered on push/PR because each run incurs Azure cost (low single-digit USD per cycle — see [docs/deploy-aca.md](./docs/deploy-aca.md) for the breakdown) and serializes on Terraform state.

```mermaid
C4Deployment
    title Deployment View — Azure Container Apps

    Deployment_Node(rg, "Azure Resource Group", "azurerm_resource_group") {
        Deployment_Node(vnet, "Virtual Network", "azurerm_virtual_network") {
            Deployment_Node(aca_env, "ACA Managed Environment", "Container Apps + built-in Dapr placement + scheduler") {
                Container(nextjs_aca, "web-nextjs", "Next.js 16, Node.js 24, Dapr 1.17.6 sidecar", "External ingress :3000")
                Container(backend_aca, "backend-ts", "Express 5, Node.js 24, Dapr 1.17.6 sidecar", "External ingress :3001")
            }
            Deployment_Node(pe_subnet, "PrivateEndpoints subnet") {
                ContainerDb(redis_aca, "Azure Cache for Redis", "Standard tier, TLS 1.2", "State + pub/sub")
            }
            Deployment_Node(pg_subnet, "Postgres delegated subnet") {
                ContainerDb(pg_aca, "Postgres Flexible Server", "PostgreSQL 17, private DNS", "Primary datastore")
            }
        }
        Container(kv, "Key Vault", "azurerm_key_vault", "jwt-secret-key, postgres-password, redis-password, app-insights-connection-string")
        Container(acr, "Container Registry", "azurerm_container_registry", "backend-ts + web-nextjs images, signed via cosign")
        Container(appins, "Application Insights", "OTLP-compatible APM", "Traces + logs + metrics")
    }

    Person(user, "End user", "Browser")

    Rel(user, nextjs_aca, "HTTPS", "ACA-managed FQDN + cert")
    Rel(nextjs_aca, backend_aca, "Dapr service invocation", "HTTP via sidecar")
    Rel(backend_aca, pg_aca, "Knex/pg", "TCP/pgwire over private link")
    Rel(backend_aca, redis_aca, "Dapr state + pub/sub", "TCP/TLS")
    Rel(nextjs_aca, kv, "Dapr secretstore via MI", "HTTPS")
    Rel(backend_aca, kv, "Dapr secretstore via MI", "HTTPS")
    Rel(nextjs_aca, acr, "Image pull via MI", "HTTPS")
    Rel(backend_aca, acr, "Image pull via MI", "HTTPS")
    Rel(nextjs_aca, appins, "OTLP", "HTTPS")
    Rel(backend_aca, appins, "OTLP", "HTTPS")
```

- **Ingress**: both container apps have `external_enabled = true` → public HTTPS endpoints auto-issued by ACA
- **Secrets**: each app has a user-assigned managed identity with `Key Vault Secrets User` role on the KV. Dapr's `azure-keyvault-secretstore` component uses that MI at runtime — no client secrets in app config
- **Private network**: Postgres and Redis are private-endpoint-only; only the ACA subnet can reach them
- **Dapr control plane**: ACA provides placement + scheduler built-in; no separate Helm install or self-hosted services needed

See [ADR-0002: Choice of ACA as production target](./docs/adr/0002-aca-as-prod-target.md) for the rationale (vs AKS, Container Instances, or App Service).

See [docs/deploy-aca.md](./docs/deploy-aca.md) for: OIDC setup, GitHub secrets, what the smoke test does / doesn't validate, cost breakdown, troubleshooting.

## Available Make Targets

Run `make help` to see all targets.

### Setup & Build

| Target                  | Description                                                             |
| ----------------------- | ----------------------------------------------------------------------- |
| `make help`             | List available tasks                                                    |
| `make deps`             | Check and install required dependencies (node, pnpm, podman, dapr, git) |
| `make deps-check`       | Print installed tool versions                                           |
| `make deps-prune`       | Report unused dependencies via `depcheck` (per workspace)               |
| `make deps-prune-check` | Fail if any workspace has unused dependencies (CI gate)                 |
| `make install`          | Install pnpm dependencies                                               |
| `make clean`            | Remove build artifacts and node_modules                                 |
| `make setup`            | Build base Docker images (run once after clone)                         |
| `make build`            | Build all service containers in parallel                                |
| `make compile`          | Compile SDK and backend TypeScript                                      |
| `make sdk-compile`      | Compile only `@sos/sdk` so backend-ts can resolve its types             |

### Stack Management

| Target           | Description                                                        |
| ---------------- | ------------------------------------------------------------------ |
| `make up`        | Bring up the full stack (Ctrl-C to stop)                           |
| `make run`       | Alias for 'up' – bring up the full stack                           |
| `make down`      | Tear down the full stack                                           |
| `make up-db`     | Bring up PostgreSQL only                                           |
| `make up-dapr`   | Bring up Dapr infrastructure (Redis, Zipkin, placement, dashboard) |
| `make up-otel`   | Bring up Grafana OpenTelemetry stack (detached)                    |
| `make up-infra`  | Bring up OpenTelemetry + database                                  |
| `make down-otel` | Tear down Grafana OpenTelemetry stack                              |

### Code Quality

| Target                   | Description                                                                                                  |
| ------------------------ | ------------------------------------------------------------------------------------------------------------ |
| `make format`            | Auto-format code with Prettier across all workspaces                                                         |
| `make lint`              | Run lint and typecheck across all workspaces (also: hadolint, scripts +x guard, terraform validate, mermaid) |
| `make lint-scripts-exec` | Fail if any tracked shell script under `scripts/` is missing the executable bit                              |
| `make vulncheck`         | Run pnpm audit for known vulnerabilities (fails on moderate+)                                                |
| `make secrets`           | Scan repo for committed secrets via `gitleaks`                                                               |
| `make trivy-fs`          | Trivy filesystem scan — CVEs + secrets + Dockerfile misconfigs (CRITICAL,HIGH)                               |
| `make mermaid-lint`      | Validate every ` ```mermaid ` block in markdown via pinned `minlag/mermaid-cli`                              |
| `make static-check`      | Composite quality gate: `lint` (which includes `mermaid-lint`) + `vulncheck` + `secrets` + `trivy-fs`        |

### Testing (three-layer pyramid)

| Target                        | Description                                                                     | Runtime         |
| ----------------------------- | ------------------------------------------------------------------------------- | --------------- |
| `make test`                   | Unit tests across SDK and backend (mocked Dapr/SDK context)                     | seconds         |
| `make integration-test`       | Backend integration tests (real Postgres + Dapr sidecar)                        | tens of seconds |
| `make web-nextjs-integration` | Next.js route → real Dapr → real backend (compose-attached; needs `make up -d`) | tens of seconds |
| `make test-integration`       | Deprecated alias for `integration-test`                                         | —               |
| `make e2e`                    | Compose-based e2e smoke (full stack up → curl → down)                           | minutes         |
| `make e2e-browser`            | Playwright browser e2e against running stack                                    | minutes         |
| `make e2e-aca`                | Deploy to Azure Container Apps, smoke, destroy (**incurs Azure cost**)          | ~10–20 min      |

### Service operations

| Target                             | Description                                                     |
| ---------------------------------- | --------------------------------------------------------------- |
| `make migrate`                     | Run pending database migrations in running backend-ts container |
| `SERVICE=backend-ts make debug`    | Start a service in debug mode (Node inspector on :9229)         |
| `SERVICE=backend-ts make terminal` | Open a shell in a running service container                     |
| `SERVICE=backend-ts make logs`     | Tail logs for a specific service                                |

### Per-workspace CI

| Target                          | Description                                                          |
| ------------------------------- | -------------------------------------------------------------------- |
| `make sdk-ci`                   | SDK: compile, lint, and test                                         |
| `make backend-lint`             | Backend: lint and typecheck                                          |
| `make backend-test`             | Backend: unit tests with coverage                                    |
| `make backend-test-integration` | Backend: integration tests with coverage (requires Postgres + Dapr)  |
| `make web-nextjs-test`          | Next.js: unit tests with coverage                                    |
| `make web-nextjs-integration`   | Next.js: compose-attached integration tests (needs `make up -d`)     |
| `make web-nextjs-ci`            | Next.js: lint, test, and build                                       |
| `make infra-validate`           | Terraform: `fmt -check` + `validate` + tflint (offline, no Azure)    |
| `make ci-dapr-up`               | Bring up a Dapr sidecar in slim mode for the integration-test CI job |
| `make ci-db-prepare`            | Prepare the test schema in the CI Postgres service container         |

### Terraform / ACA images

| Target                                                        | Description                                                   |
| ------------------------------------------------------------- | ------------------------------------------------------------- |
| `make tf-init`                                                | `terraform init` in `infra/azure/` (no backend prompt)        |
| `make tf-apply-acr`                                           | Targeted apply: provision only the Azure Container Registry   |
| `make tf-acr-login-server`                                    | Print the ACR login server FQDN (requires `make tf-init`)     |
| `make tf-apply`                                               | Full Terraform apply (requires `GIT_SHA` and provisioned ACR) |
| `make tf-destroy`                                             | Destroy the ACA stack (requires `GIT_SHA` used at apply time) |
| `SERVICE=… IMAGE_TAG=… make image-build-prod`                 | Build a production image (single-arch, `--load` for scan)     |
| `SERVICE=… IMAGE_TAG=… make image-scan-prod`                  | Trivy scan a previously built production image                |
| `SERVICE=… IMAGE_TAG=… REGISTRY=… make image-push-multi-arch` | Build multi-arch (amd64+arm64) and push to ACR                |

### Diagnostics

| Target           | Description                                                       |
| ---------------- | ----------------------------------------------------------------- |
| `make psql`      | Connect to PostgreSQL CLI (default password: postgres)            |
| `make redis-cli` | Connect to Redis CLI                                              |
| `make shell`     | Open an alpine shell on the dapr-net network (for nc, ping, etc.) |

### Maintenance

| Target         | Description                                                    |
| -------------- | -------------------------------------------------------------- |
| `make prune`   | Remove unused Podman containers, images, and volumes           |
| `make login`   | Login to Docker Hub via Podman                                 |
| `make update`  | Update pnpm dependencies to latest allowed versions            |
| `make upgrade` | Upgrade pnpm dependencies to latest versions (ignoring ranges) |

### CI / Release

| Target                        | Description                                                                    |
| ----------------------------- | ------------------------------------------------------------------------------ |
| `make ci`                     | Run full CI pipeline locally (`static-check` + `test` + `build`)               |
| `make ci-run`                 | Run GitHub Actions workflow locally using [act](https://github.com/nektos/act) |
| `make check-version`          | Ensure VERSION variable is set and follows semver (vX.Y.Z)                     |
| `make release VERSION=v1.0.0` | Create and push a release tag                                                  |
| `make renovate-validate`      | Validate Renovate configuration                                                |
| `make e2e`                    | Compose-based e2e smoke (local)                                                |
| `make e2e-browser`            | Playwright browser e2e (local)                                                 |
| `make e2e-aca`                | Deploy to ACA, smoke, destroy (**incurs Azure cost**)                          |

## Database migrations

Migrations run inside the backend container (DB credentials come from Dapr secretstore):

```bash
make up                              # Start the stack
make migrate                         # Run pending migrations
SERVICE=backend-ts make terminal     # Or shell in and create new ones:
pnpm run knex -- migrate:make my-migration
```

Migrations also run automatically on backend startup via `pnpm run dev`.

## CI/CD

GitHub Actions runs on every push to `main`, tags `v*`, and pull requests.

| Job                  | Triggers                            | Steps                                                                                                                     |
| -------------------- | ----------------------------------- | ------------------------------------------------------------------------------------------------------------------------- |
| **changes**          | push, PR, tags                      | Detect code changes (skips heavy jobs on docs-only PRs via [`dorny/paths-filter`](https://github.com/dorny/paths-filter)) |
| **build**            | after changes                       | Compile SDK, lint & test SDK, upload `sdk-build` artifact                                                                 |
| **static-check**     | after build                         | Composite gate: `make static-check` (lint [includes mermaid-lint] + vulncheck + gitleaks + Trivy fs scan)                 |
| **test**             | after build                         | Unit tests across SDK + backend (with coverage)                                                                           |
| **integration-test** | after build                         | Backend integration tests with Postgres service + Dapr sidecar                                                            |
| **web-nextjs**       | after changes                       | Lint, test & build Next.js SSR frontend                                                                                   |
| **e2e**              | after integration-test + web-nextjs | Full-stack compose smoke test (`e2e/e2e-test.sh`)                                                                         |
| **ci-pass**          | after all above                     | Gate job — fails if any required job failed or was cancelled                                                              |

The `changes` detector keeps doc-only changes from running heavy jobs while still triggering the workflow (so Repository Rulesets gating on `ci-pass` are satisfied).

[Renovate](https://docs.renovatebot.com/) keeps dependencies up to date with platform automerge enabled.

### Required secrets and variables

The `ci.yml` workflow needs no secrets — all jobs run with the default `GITHUB_TOKEN`. The `e2e-aca.yml` workflow (manual `workflow_dispatch` only) needs:

| Name                    | Type   | Used by                                                                       | How to obtain                                                                          |
| ----------------------- | ------ | ----------------------------------------------------------------------------- | -------------------------------------------------------------------------------------- |
| `AZURE_CLIENT_ID`       | Secret | `e2e-aca` job (OIDC login)                                                    | AAD app registration Client ID — see [docs/deploy-aca.md](./docs/deploy-aca.md) step 1 |
| `AZURE_TENANT_ID`       | Secret | `e2e-aca` job (OIDC login)                                                    | Azure AD tenant ID (`az account show --query tenantId -o tsv`)                         |
| `AZURE_SUBSCRIPTION_ID` | Secret | `e2e-aca` job (OIDC login)                                                    | Azure subscription ID                                                                  |
| `JWT_SECRET_KEY`        | Secret | `e2e-aca` job (seeded into Key Vault; smoke script signs JWT with same value) | Generate via `openssl rand -hex 32`                                                    |

Set secrets via **Settings → Secrets and variables → Actions → New repository secret**. OIDC federation setup (no long-lived SP secret) is documented in [docs/deploy-aca.md](./docs/deploy-aca.md).

### Supply-chain gates

`make static-check` (run by the `static-check` CI job on every push and PR) bundles:

| Gate        | Catches                                                                                           | Tool                                                                          |
| ----------- | ------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| `lint`      | Code style, type errors, Dockerfile lints, `scripts/*.sh` missing +x bit, broken Mermaid diagrams | ESLint, `tsc --noEmit`, Prettier, hadolint, `mermaid-cli`                     |
| `vulncheck` | Known npm CVEs (moderate+)                                                                        | `pnpm audit`                                                                  |
| `secrets`   | Committed credentials                                                                             | [gitleaks](https://github.com/gitleaks/gitleaks) — config in `.gitleaks.toml` |
| `trivy-fs`  | Filesystem CVEs, secrets, Dockerfile misconfigs (CRITICAL,HIGH)                                   | [Trivy](https://github.com/aquasecurity/trivy) — allowlist in `.trivyignore`  |

### Pre-push image hardening

The `ci.yml` `docker` job and the `e2e-aca.yml` ACA-deploy workflow run the following gates **before** pushing any image. Any failure blocks the push.

| #   | Gate                                          | Catches                                                                                          | Tool                                                            |
| --- | --------------------------------------------- | ------------------------------------------------------------------------------------------------ | --------------------------------------------------------------- |
| 1   | Build local single-arch image                 | Build regressions on amd64                                                                       | `docker buildx build --load --cache-from type=gha`              |
| 2   | **Trivy image scan** (CRITICAL/HIGH blocking) | CVEs in the base image, OS packages, build layers; misconfigs; secret leaks in layers            | `aquasecurity/trivy-action` with `image-ref:`                   |
| 3   | **Smoke test**                                | Image boots cleanly on its own (boot-marker `listening`/`Ready in`/`started on port` within 30s) | `make image-smoke-test`                                         |
| 4   | Multi-arch build + push (ACA only)            | Publishes for both `linux/amd64` and `linux/arm64`                                               | `docker buildx build --platform linux/amd64,linux/arm64 --push` |
| 5   | **Cosign keyless OIDC signing** (ACA only)    | Sigstore signature on the manifest digest                                                        | `sigstore/cosign-installer` + `cosign sign --yes`               |

`ignore-unfixed: true` skips CVEs with no upstream fix available. Buildkit in-manifest attestations (`provenance` and `sbom`) are explicitly disabled (`--provenance=false --sbom=false`) so the OCI image index stays free of `unknown/unknown` platform entries — supply-chain verification comes from cosign keyless signing instead.

The `e2e` CI job additionally runs an **OWASP ZAP baseline scan** against the running compose stack (`http://localhost:3000`):

| Gate                    | Catches                                                 | Tool                                                                                                           |
| ----------------------- | ------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| **DAST (ZAP baseline)** | Missing security headers, info leaks, common misconfigs | `make dast` (warn-only via `-I`; only FAIL severity blocks; report uploaded as `zap-baseline-report` artifact) |

The DAST scan is **inlined into `e2e`** (rather than running as a separate `dast` job per the `/harden-image-pipeline` skill default) because Next.js fronted by web-nextjs:3000 only boots correctly when the full Dapr-enabled compose stack is up — Dapr sidecar + Postgres + Redis + backend-ts. Spinning up a duplicate stack in a parallel `dast` job would double the e2e cost; reusing the existing one is cheaper at the price of slight serialization within `e2e`.

Verify a published image's signature:

```bash
cosign verify <acr-server>/backend-ts:<git-sha> \
  --certificate-identity-regexp 'https://github\.com/<owner>/<repo>/.*' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com
```

## Contributing

Contributions welcome — open a PR. Before pushing, run `make ci` for the fast local pipeline and `make e2e` for a full-stack smoke test.

## Further reading

- [Architecture Decision Records](./docs/adr/README.md) — Dapr sidecar, ACA target, Redis broker
- [Deploy to Azure Container Apps](./docs/deploy-aca.md)
- [Create a new service](./docs/create-new-service.md)
- [Setup an Azure Sandbox VM (for running local stack in the cloud)](./docs/setup-azure-sandbox.md)
- [Backend service details](./app/backend-ts/README.md)
