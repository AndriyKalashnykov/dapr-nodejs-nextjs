# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Dapr-based microservices platform using Node.js/TypeScript with npm workspaces (monorepo). Services communicate through Dapr sidecars for state management, pub/sub, and service invocation. Container runtime is Podman (Docker-compatible).

## Common Commands

### Development Stack (Podman/Docker Compose)
```bash
make setup          # Build base Docker images (run once)
make up             # Bring up full stack
make up-db          # Database only
make up-dapr        # Dapr infrastructure (Redis, Zipkin, placement, dashboard)
make up-infra       # OpenTelemetry + database
make down           # Tear down full stack
make build          # Build all services (parallel)

# Per-service debugging
SERVICE=backend-ts make debug    # Debug mode with Node inspector
SERVICE=backend-ts make terminal # Shell into running container
```

### Backend (`app/backend-ts`)
```bash
npm run dev              # Hot reload dev server (runs DB migrations first)
npm run compile          # TypeScript compilation
npm run ci               # tsc --noEmit + lint + prettier
npm run lint             # ESLint
npm run prettier         # Prettier check
npm run test             # Unit tests (Vitest)
npm run test:cov         # Unit tests with coverage
npm run test:integration # Integration tests (runs DB migrations first)
npm run knex -- migrate:make <name>  # Create new DB migration
npm run knex -- migrate:latest       # Run pending migrations
```

### Frontend (`app/web-nextjs`)
```bash
npm run dev    # Next.js dev server (WATCHPACK_POLLING=true for Docker)
npm run build  # Production build
npm run lint   # next lint (Biome-based)
```

### Frontend (`app/web-react`)
```bash
npm run dev    # Vite dev server
npm run build  # tsc + Vite build
```

### Shared SDK (`packages/@sos/sdk`)
```bash
npm run compile  # tsc --build
npm run test     # Vitest unit tests
npm run ci       # tsc --noEmit + lint + prettier
```

## Architecture

### Monorepo Layout
```
app/
  backend-ts/     Express 5 + Dapr sidecar backend
  web-nextjs/     Next.js 15 SSR frontend
  web-react/      Vite/React SPA frontend
packages/@sos/
  sdk/            Shared Dapr/DB/API utilities
shared/
  dapr/           Dapr runtime config & components (Redis state/pubsub, Zipkin)
  db/             PostgreSQL 17 docker-compose + schema init
  otel/           OpenTelemetry collector + Grafana stack
  microservice/   Base Docker image for all services
infra/            Azure Terraform configs
scaffolds/        Code generators for new services
```

### Dapr Sidecar Pattern
Every backend service runs as two containers: the app + a Dapr sidecar. The sidecar proxies all inter-service communication:
- **State**: Redis via `DAPR_HOST:DAPR_PORT` (default 3500)
- **Pub/Sub**: Redis topic `todo-data`, subscribers receive CloudEvents at `/consumer/*` endpoints
- **Service Invocation**: `http://DAPR_HOST:DAPR_PORT/v1.0/invoke/<app-id>/method/<path>`

In Docker Compose, `DAPR_HOST=0.0.0.0` for backends; `DAPR_HOST=127.0.0.1` for frontends (sharing a network namespace with their sidecar).

### Shared SDK (`@sos/sdk`)
The SDK is the core abstraction layer. Key patterns:
- `buildServiceContext()` — creates context with logger, DB client, Dapr client; used at service startup
- `buildHandlerContext()` — enriches context per request handler (dependency injection pattern)
- `Context<K>` — generic type-safe service context parameterized by API kind
- Modules: `api`, `dapr`, `database`, `state`, `pubsub`, `secrets`, `cache`, `consumer`, `invoke`, `metrics`

### API Layer (backend-ts)
Uses `express-zod-api` for type-safe routing. All endpoints define Zod schemas for input/output. OpenAPI docs served via swagger-ui-express. JWT authentication via `jsonwebtoken`. Security headers via `helmet`.

### Database
- PostgreSQL 17 with Knex.js for migrations and query building
- Schema per service: `backend_ts` (prod), `backend_ts_test` (integration tests)
- Migrations live in `app/backend-ts/src/db/migrations/`
- Connection configured via `DB_HOST`, `DB_PORT`, `DB_NAME`, `DB_SCHEMA` env vars

### Testing
- **Unit tests**: `*.test.ts` — run with `npm run test`
- **Integration tests**: `*.integration.test.ts` — run with `npm run test:integration` (requires DB)
- Framework: Vitest 3 with supertest for HTTP testing
- Coverage excludes: instrumentation, OpenAPI specs, seed data, DB config files

### Observability
- **Logging**: Pino with structured JSON; log level via `LOG_LEVEL` env var
- **Tracing**: OpenTelemetry SDK auto-instrumentation, exported to Zipkin (port 9411) and OTLP endpoint
- **Metrics**: OpenTelemetry metrics via `@sos/sdk` metrics module
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
| `VITE_API_GATEWAY_BASE_URL` | web-react | — | Backend API URL |
| `NODE_ENV` | all | `development` | `test` disables some features |

## Adding a New Service
See `docs/create-new-service.md` and use the scaffolds in `scaffolds/` directory. Each service needs: app container + Dapr sidecar container in its `docker-compose.yaml`.
