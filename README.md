[![CI](https://github.com/AndriyKalashnykov/dapr-nodejs-nextjs/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/AndriyKalashnykov/dapr-nodejs-nextjs/actions/workflows/ci.yml)
[![Hits](https://hits.sh/github.com/AndriyKalashnykov/dapr-nodejs-nextjs.svg?view=today-total&style=plastic)](https://hits.sh/github.com/AndriyKalashnykov/dapr-nodejs-nextjs/)
[![License: MIT](https://img.shields.io/badge/License-MIT-brightgreen.svg)](https://opensource.org/licenses/MIT)
[![Renovate enabled](https://img.shields.io/badge/renovate-enabled-brightgreen.svg)](https://app.renovatebot.com/dashboard#github/AndriyKalashnykov/dapr-nodejs-nextjs)

# Dapr Node.js + Next.js Microservices Platform

A reference implementation for building microservices with Node.js, TypeScript, and [Dapr](https://dapr.io/). The project ships a todo-list API backend (Express 5), two frontends (Next.js SSR and React SPA), and a shared SDK — all wired together through Dapr sidecars for state management (Redis), pub/sub messaging, and service-to-service invocation. The monorepo uses npm workspaces, containerized with [Podman](https://podman.io/) (Docker-compatible), and includes PostgreSQL for persistence, OpenTelemetry for observability, and Knex.js for database migrations.

## Quick Start

```bash
make deps && make install && make setup   # install tools, npm packages, base images
make build                                # build service containers
make up                                   # start the full stack (Ctrl-C to stop)
```

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| [GNU Make](https://www.gnu.org/software/make/) | 3.81+ | Build orchestration |
| [Git](https://git-scm.com/) | latest | Version control |
| [Node.js](https://nodejs.org/) | 24+ (tracks `NODE_VERSION` in Makefile) | JavaScript runtime |
| [Podman](https://podman.io/docs/installation) | 4.9+ | Container runtime (Docker-compatible) with Compose |
| [Dapr CLI](https://docs.dapr.io/getting-started/install-dapr-cli/) | 1.17+ (tracks `DAPR_VERSION` in Makefile) | Distributed application runtime |

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
<summary>Windows: Podman setup</summary>

Install [Podman Desktop](https://podman-desktop.io/) and enable the "Compose" extension.
</details>

## Start, test, stop

```bash
# First time only
make deps           # Check and install required dependencies (node, npm, podman, dapr, git)
make install        # Install npm dependencies
make setup          # Build base Docker images (run once after clone)

# Start
make build          # Build all service containers in parallel
make up             # Bring up the full stack (Ctrl-C to stop)

# Test (no containers needed)
make test           # Run unit tests across SDK and backend
make lint           # Run lint and typecheck across all workspaces
make ci             # Run full CI pipeline locally (lint + vulncheck + test + build)

# Test (containers needed)
make test-integration  # Run backend integration tests (requires Postgres + Dapr sidecar)

# Stop
make down           # Tear down the full stack
```

Once running, services are available at:

| Service | URL |
|---|---|
| Next.js frontend | http://localhost:3000 |
| React frontend | http://localhost:3100 |
| Swagger UI | http://localhost:3001/docs |
| Backend API (direct) | http://localhost:3001/api/v1/todos |
| Backend API (via Dapr) | http://localhost:3500/v1.0/invoke/backend-ts/method/api/v1/todos |
| Dapr Dashboard | http://localhost:8888 |
| Zipkin tracing | http://localhost:9411 |
| PostgreSQL | localhost:5432 (user/pass: `postgres`) |

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

## Available Make Targets

Run `make help` to see all targets.

### Setup & Build

| Target | Description |
|--------|-------------|
| `make help` | List available tasks |
| `make deps` | Check and install required dependencies (node, npm, podman, dapr, git) |
| `make deps-check` | Print installed tool versions |
| `make install` | Install npm dependencies |
| `make clean` | Remove build artifacts and node_modules |
| `make setup` | Build base Docker images (run once after clone) |
| `make build` | Build all service containers in parallel |
| `make compile` | Compile SDK and backend TypeScript |

### Stack Management

| Target | Description |
|--------|-------------|
| `make up` | Bring up the full stack (Ctrl-C to stop) |
| `make run` | Alias for 'up' – bring up the full stack |
| `make down` | Tear down the full stack |
| `make up-db` | Bring up PostgreSQL only |
| `make up-dapr` | Bring up Dapr infrastructure (Redis, Zipkin, placement, dashboard) |
| `make up-otel` | Bring up Grafana OpenTelemetry stack (detached) |
| `make up-infra` | Bring up OpenTelemetry + database |
| `make down-otel` | Tear down Grafana OpenTelemetry stack |

### Development

| Target | Description |
|--------|-------------|
| `make format` | Auto-format code with Prettier across all workspaces |
| `make lint` | Run lint and typecheck across all workspaces |
| `make vulncheck` | Run npm audit for known vulnerabilities |
| `make test` | Run unit tests across SDK and backend |
| `make test-integration` | Run backend integration tests (requires Postgres + Dapr sidecar) |
| `make migrate` | Run pending database migrations in running backend-ts container |
| `SERVICE=backend-ts make debug` | Start a service in debug mode (Node inspector on :9229) |
| `SERVICE=backend-ts make terminal` | Open a shell in a running service container |
| `SERVICE=backend-ts make logs` | Tail logs for a specific service |

### Per-workspace CI

| Target | Description |
|--------|-------------|
| `make sdk-ci` | SDK: compile, lint, and test |
| `make backend-lint` | Backend: lint and typecheck |
| `make backend-test` | Backend: unit tests with coverage |
| `make backend-test-integration` | Backend: integration tests with coverage (requires Postgres + Dapr) |
| `make web-nextjs-ci` | Next.js: lint and build |
| `make web-react-ci` | React: lint and build |

### Diagnostics

| Target | Description |
|--------|-------------|
| `make psql` | Connect to PostgreSQL CLI (default password: postgres) |
| `make redis-cli` | Connect to Redis CLI |
| `make shell` | Open an alpine shell on the dapr-net network (for nc, ping, etc.) |

### Maintenance

| Target | Description |
|--------|-------------|
| `make prune` | Remove unused Podman containers, images, and volumes |
| `make login` | Login to Docker Hub via Podman |
| `make update` | Update npm dependencies to latest allowed versions |
| `make upgrade` | Upgrade npm dependencies to latest versions (ignoring ranges) |

### CI / Release

| Target | Description |
|--------|-------------|
| `make ci` | Run full CI pipeline locally (lint + vulncheck + test + build) |
| `make ci-run` | Run GitHub Actions workflow locally using [act](https://github.com/nektos/act) |
| `make deps-act` | Install act for local GitHub Actions testing |
| `make check-version` | Ensure VERSION variable is set and follows semver (vX.Y.Z) |
| `make release VERSION=v1.0.0` | Create and push a release tag |
| `make renovate-validate` | Validate Renovate configuration |

## Database migrations

Migrations run inside the backend container (DB credentials come from Dapr secretstore):

```bash
make up                              # Start the stack
make migrate                         # Run pending migrations
SERVICE=backend-ts make terminal     # Or shell in and create new ones:
npm run knex -- migrate:make my-migration
```

Migrations also run automatically on backend startup via `npm run dev`.

## CI/CD

GitHub Actions runs on every push to `main`, tags `v*`, and pull requests.

| Job | Triggers | Steps |
|-----|----------|-------|
| **sdk** | push, PR, tags | Compile, lint & test SDK; upload build artifact |
| **backend-ci** | after sdk | Lint & typecheck backend |
| **backend-unit** | after sdk + backend-ci | Unit tests with coverage |
| **backend-integration** | after sdk + backend-ci | Integration tests with Postgres + Dapr sidecar |
| **web-nextjs** | push, PR, tags | Lint & build Next.js frontend |
| **web-react** | push, PR, tags | Lint & build React frontend |

[Renovate](https://docs.renovatebot.com/) keeps dependencies up to date with platform automerge enabled.

## Further reading

- [Create a new service](./docs/create-new-service.md)
- [Setup an Azure Sandbox](./docs/setup-azure-sandbox.md)
- [Backend service details](./app/backend-ts/README.md)
