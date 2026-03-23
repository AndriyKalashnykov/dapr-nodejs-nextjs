# Dapr Node.js + Next.js Microservices Platform

A reference implementation for building microservices with Node.js, TypeScript, and [Dapr](https://dapr.io/). The project ships a todo-list API backend (Express 5), two frontends (Next.js SSR and React SPA), and a shared SDK — all wired together through Dapr sidecars for state management (Redis), pub/sub messaging, and service-to-service invocation. The monorepo uses npm workspaces, containerized with [Podman](https://podman.io/) (Docker-compatible), and includes PostgreSQL for persistence, OpenTelemetry for observability, and Knex.js for database migrations.

## Prerequisites

- [Node.js 22+](https://nodejs.org/)
- [Podman](https://podman.io/docs/installation) with Compose
- [Dapr CLI](https://docs.dapr.io/getting-started/install-dapr-cli/)

Run `make deps` to check and auto-install missing dependencies.

**Linux setup:**
```bash
sudo apt-get -y install podman docker-compose-plugin
systemctl --user enable --now podman.socket
export DOCKER_HOST="unix://$XDG_RUNTIME_DIR/podman/podman.sock"
```

**Windows:** Install [Podman Desktop](https://podman-desktop.io/) and enable the "Compose" extension.

## Start, test, stop

```bash
# First time only
make deps           # Check dependencies
make install        # Install npm packages
make setup          # Build base Docker images

# Start
make build          # Build service containers
make up             # Start the full stack (Ctrl-C to stop)

# Test (no containers needed)
make test           # Unit tests with coverage (SDK + backend)
make lint           # Lint + typecheck all workspaces
make ci             # Full CI pipeline (lint + test + build)

# Test (containers needed)
make test-integration  # Integration tests (requires Postgres + Dapr)

# Stop
make down           # Tear down all containers
```

Once running, services are available at:

| Service | URL |
|---|---|
| Next.js frontend | http://localhost:3000 |
| React frontend | http://localhost:3100 |
| Backend (via Dapr sidecar) | http://localhost:3500 |
| Swagger UI | http://localhost:3500/docs |
| Dapr Dashboard | http://localhost:8888 |
| Zipkin tracing | http://localhost:9411 |
| PostgreSQL | localhost:5432 (user/pass: `postgres`) |

## Makefile reference

Run `make help` to see all targets. Key commands:

| Command | Description |
|---|---|
| **Setup** | |
| `make deps` | Check/install dependencies (node, podman, dapr) |
| `make install` | `npm ci` |
| `make setup` | Build base Docker images (once after clone) |
| `make build` | Build all service containers |
| `make clean` | Remove node_modules and build artifacts |
| **Stack** | |
| `make up` | Start the full stack |
| `make down` | Stop the full stack |
| `make up-db` | Start PostgreSQL only |
| `make up-dapr` | Start Dapr infra (Redis, Zipkin, placement, dashboard) |
| **Development** | |
| `make compile` | Compile SDK + backend TypeScript |
| `make lint` | Lint + typecheck all workspaces |
| `make test` | Unit tests with coverage |
| `make test-integration` | Integration tests (needs running DB + Dapr) |
| `make ci` | Full CI pipeline locally |
| `make migrate` | Run DB migrations in running backend container |
| **Per-service** | |
| `SERVICE=backend-ts make debug` | Start service with Node inspector on :9229 |
| `SERVICE=backend-ts make terminal` | Shell into running container |
| `SERVICE=backend-ts make logs` | Tail service logs |
| **Diagnostics** | |
| `make psql` | Connect to PostgreSQL CLI |
| `make redis-cli` | Connect to Redis CLI |
| **Release** | |
| `make release VERSION=v1.0.0` | Tag and push a release |

## Database migrations

Migrations run inside the backend container (DB credentials come from Dapr secretstore):

```bash
make up                              # Start the stack
make migrate                         # Run pending migrations
SERVICE=backend-ts make terminal     # Or shell in and create new ones:
npm run knex -- migrate:make my-migration
```

Migrations also run automatically on backend startup via `npm run dev`.

## Further reading

- [Create a new service](./docs/create-new-service.md)
- [Setup an Azure Sandbox](./docs/setup-azure-sandbox.md)
- [Backend service details](./app/backend-ts/README.md)
