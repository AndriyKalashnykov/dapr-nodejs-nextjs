.DEFAULT_GOAL := help

# ── Pinned tool versions ────────────────────────────────────────────────────
NVM_VERSION  := 0.40.4
NODE_VERSION := 22
ACT_VERSION  := 0.2.86

# ── Project constants ───────────────────────────────────────────────────────
COMPOSE_PROJECT := demo-ts
NETWORK := $(COMPOSE_PROJECT)_dapr-net

# ── Phony targets ──────────────────────────────────────────────────────────
.PHONY: help deps install clean setup build compile \
        up up-db up-dapr up-otel up-infra down down-otel \
        run debug terminal lint test test-integration \
        sdk-ci backend-lint backend-test backend-test-integration \
        web-nextjs-ci web-react-ci \
        psql migrate redis-cli shell logs \
        prune login update upgrade \
        ci ci-run check-version release \
        deps-act renovate-validate

#help: @ List available tasks
help:
	@clear
	@echo "Usage: make COMMAND"
	@echo "Commands :"
	@grep -E '[a-zA-Z\.\-]+:.*?@ .*$$' $(MAKEFILE_LIST)| tr -d '#' | awk 'BEGIN {FS = ":.*?@ "}; {printf "\033[32m%-20s\033[0m - %s\n", $$1, $$2}'

# ── Dependencies ──────────────────────────────────────────────────────────────

#deps: @ Check and install required dependencies (node, npm, podman, dapr, git)
deps:
	@echo "Checking dependencies..."
	@command -v node >/dev/null 2>&1 || { echo "Installing Node.js via nvm..."; \
		if [ -s "$$HOME/.nvm/nvm.sh" ]; then \
			. "$$HOME/.nvm/nvm.sh" && nvm install $(NODE_VERSION); \
		else \
			echo "Installing nvm..."; \
			curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v$(NVM_VERSION)/install.sh | bash; \
			export NVM_DIR="$$HOME/.nvm"; \
			. "$$NVM_DIR/nvm.sh" && nvm install $(NODE_VERSION); \
		fi; \
	}
	@command -v podman >/dev/null 2>&1 || { echo "Installing Podman..."; \
		if command -v apt-get >/dev/null 2>&1; then \
			sudo apt-get update && sudo apt-get install -y podman; \
		elif command -v dnf >/dev/null 2>&1; then \
			sudo dnf install -y podman; \
		elif command -v brew >/dev/null 2>&1; then \
			brew install podman; \
		else \
			echo "ERROR: Could not install podman. Install manually from https://podman.io/docs/installation"; exit 1; \
		fi; \
	}
	@command -v dapr >/dev/null 2>&1 || { echo "Installing Dapr CLI..."; \
		curl -fsSL https://raw.githubusercontent.com/dapr/cli/master/install/install.sh | /bin/bash; \
	}
	@command -v git >/dev/null 2>&1 || { echo "Installing git..."; \
		if command -v apt-get >/dev/null 2>&1; then \
			sudo apt-get update && sudo apt-get install -y git; \
		elif command -v dnf >/dev/null 2>&1; then \
			sudo dnf install -y git; \
		elif command -v brew >/dev/null 2>&1; then \
			brew install git; \
		else \
			echo "ERROR: Could not install git. Install manually from https://git-scm.com/downloads"; exit 1; \
		fi; \
	}
	@echo "All dependencies checked."

#install: @ Install npm dependencies
install: deps
	@npm ci

#clean: @ Remove build artifacts and node_modules
clean:
	@rm -rf node_modules/
	@rm -rf packages/@sos/sdk/build/
	@rm -rf app/backend-ts/dist/
	@rm -rf app/web-nextjs/.next/
	@rm -rf app/web-react/dist/

# ── Build ─────────────────────────────────────────────────────────────────────

#setup: @ Build base Docker images (run once after clone)
setup:
	@echo "\n***Building microservice base image***\n"
	@podman build ./shared/microservice -t microservice-build --build-arg ADD_CERT=$$ADD_CERT
	@podman build -f Dockerfile.dev -t microservice-sdk-build .

#build: @ Build all service containers in parallel
build:
	@podman compose --parallel 3 build

#compile: @ Compile SDK and backend TypeScript
compile: install
	@npm run compile -w packages/@sos/sdk
	@npm run compile -w app/backend-ts

# ── Stack Management ─────────────────────────────────────────────────────────

#up: @ Bring up the full stack (Ctrl-C to stop)
up:
	@echo "\n***Bringing up the stack***\n"
	@podman compose up

#run: @ Alias for 'up' – bring up the full stack
run: up

#up-db: @ Bring up PostgreSQL only
up-db:
	@echo "\n***Bringing up the db***\n"
	@podman compose up postgres postgres-build-dbs

#up-dapr: @ Bring up Dapr infrastructure (Redis, Zipkin, placement, dashboard)
up-dapr:
	@echo "\n***Bringing up Dapr services***\n"
	@podman compose up placement redis zipkin dapr-dashboard

#up-otel: @ Bring up Grafana OpenTelemetry stack (detached)
up-otel:
	@echo "\n***Bringing up the OpenTelemetry services***\n"
	@cd shared/otel && podman compose up -d grafana-otel

#up-infra: @ Bring up OpenTelemetry + database
up-infra: up-otel up-db

#down: @ Tear down the full stack
down:
	@podman compose down

#down-otel: @ Tear down Grafana OpenTelemetry stack
down-otel:
	@echo "\n***Shutting down the OpenTelemetry services***\n"
	@cd shared/otel && podman compose down grafana-otel

# ── Development ──────────────────────────────────────────────────────────────

#debug: @ Start a service in debug mode (SERVICE=backend-ts make debug)
debug: setup
	@if [ -z "$$SERVICE" ]; then echo "ERROR: SERVICE is required. Usage: SERVICE=backend-ts make debug"; exit 1; fi
	@echo "\n***Starting $$SERVICE in debug mode***\n"
	@podman compose -f docker-compose.yaml -f app/$$SERVICE/docker-compose.debug.yaml up

#terminal: @ Open a shell in a running service container (SERVICE=backend-ts make terminal)
terminal:
	@if [ -z "$$SERVICE" ]; then echo "ERROR: SERVICE is required. Usage: SERVICE=backend-ts make terminal"; exit 1; fi
	@podman compose exec -it $$SERVICE /bin/sh

#lint: @ Run lint and typecheck across all workspaces
lint: install
	@npm run ci -w packages/@sos/sdk
	@npm run ci -w app/backend-ts
	@npm run lint -w app/web-nextjs
	@npm run lint -w app/web-react

#test: @ Run unit tests across SDK and backend
test: install
	@npm run test:cov -w packages/@sos/sdk
	@npm run test:cov -w app/backend-ts

#test-integration: @ Run backend integration tests (requires Postgres + Dapr sidecar)
test-integration: install
	@podman exec demo-ts-postgres-1 psql -U postgres -d postgres -c "CREATE SCHEMA IF NOT EXISTS backend_ts_test;" 2>/dev/null || true
	@NODE_ENV=test SERVICE_NAME=backend-ts DB_HOST=localhost DB_PORT=5432 DB_NAME=postgres DB_SCHEMA=backend_ts JWT_SECRET_KEY=secret DAPR_HOST=localhost DAPR_PORT=3500 npm run test:integration:cov -w app/backend-ts

# ── Per-workspace CI targets (used by GitHub Actions) ────────────────────────

#sdk-ci: @ SDK: compile, lint, and test
sdk-ci: install
	@npm run compile -w packages/@sos/sdk
	@npm run ci -w packages/@sos/sdk
	@npm run test:cov -w packages/@sos/sdk

#backend-lint: @ Backend: lint and typecheck
backend-lint: install
	@npm run ci -w app/backend-ts

#backend-test: @ Backend: unit tests with coverage
backend-test: install
	@npm run test:cov -w app/backend-ts

#backend-test-integration: @ Backend: integration tests with coverage (requires Postgres + Dapr)
backend-test-integration: install
	@NODE_ENV=test SERVICE_NAME=backend-ts DB_HOST=localhost DB_PORT=5432 DB_NAME=postgres DB_SCHEMA=backend_ts JWT_SECRET_KEY=secret DAPR_HOST=localhost DAPR_PORT=3500 npm run test:integration:cov -w app/backend-ts

#web-nextjs-ci: @ Next.js: lint and build
web-nextjs-ci: install
	@npm run lint -w app/web-nextjs
	@JWT_SECRET_KEY=ci-build-placeholder npm run build -w app/web-nextjs

#web-react-ci: @ React: lint and build
web-react-ci: install
	@npm run lint -w app/web-react
	@npm run build -w app/web-react

# ── Database ─────────────────────────────────────────────────────────────────

#psql: @ Connect to PostgreSQL CLI (default password: postgres)
psql:
	@echo "\n***Default user 'postgres' has default password 'postgres'***\n"
	@podman run -it --rm --network $(NETWORK) postgres:17-alpine psql -h postgres -U postgres

#migrate: @ Run pending database migrations in running backend-ts container
migrate:
	@podman compose exec backend-ts npm run knex -w app/backend-ts -- migrate:latest

# ── Diagnostics ──────────────────────────────────────────────────────────────

#redis-cli: @ Connect to Redis CLI
redis-cli:
	@podman run -it --rm --network $(NETWORK) redis:7-alpine redis-cli -h redis

#shell: @ Open an alpine shell on the dapr-net network (for nc, ping, etc.)
shell:
	@podman run -it --rm --network $(NETWORK) alpine:latest

#logs: @ Tail logs for a specific service (SERVICE=backend-ts make logs)
logs:
	@if [ -z "$$SERVICE" ]; then echo "ERROR: SERVICE is required. Usage: SERVICE=backend-ts make logs"; exit 1; fi
	@podman compose logs -f $$SERVICE

# ── Maintenance ──────────────────────────────────────────────────────────────

#prune: @ Remove unused Podman containers, images, and volumes
prune:
	@podman system prune -f
	@podman volume prune -f --filter label!=io.podman.compose.project=$(COMPOSE_PROJECT)

#login: @ Login to Docker Hub via Podman
login:
	@podman login docker.io

#update: @ Update npm dependencies to latest allowed versions
update: deps
	@npm update

#upgrade: @ Upgrade npm dependencies to latest versions (ignoring ranges)
upgrade: deps
	@npx npm-check-updates -u
	@npm install

# ── CI / Release ─────────────────────────────────────────────────────────────

#ci: @ Run full CI pipeline locally (lint + typecheck + unit tests)
ci: install
	@echo "\n***Running CI pipeline***\n"
	@npm run compile -w packages/@sos/sdk
	@npm run ci -w packages/@sos/sdk
	@npm run test:cov -w packages/@sos/sdk
	@npm run ci -w app/backend-ts
	@npm run test:cov -w app/backend-ts
	@npm run lint -w app/web-nextjs
	@JWT_SECRET_KEY=ci-build-placeholder npm run build -w app/web-nextjs
	@npm run lint -w app/web-react
	@npm run build -w app/web-react

#check-version: @ Ensure VERSION variable is set and follows semver (vX.Y.Z)
check-version:
ifndef VERSION
	$(error VERSION is undefined. Usage: make release VERSION=v1.0.0)
endif
	@echo "$(VERSION)" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$$' \
		|| { echo "ERROR: VERSION must match semver format vX.Y.Z (got: $(VERSION))"; exit 1; }

#release: @ Create and push a release tag (requires VERSION=vX.Y.Z)
release: check-version
	@echo -n "Are you sure to create and push ${VERSION} tag? [y/N] " && read ans && [ $${ans:-N} = y ]
	@git commit -a -s -m "Cut ${VERSION} release"
	@git tag ${VERSION}
	@git push origin ${VERSION}
	@git push
	@echo "Done."

# ── Local CI with act ───────────────────────────────────────────────────────

#deps-act: @ Install act for local GitHub Actions testing
deps-act: deps
	@command -v act >/dev/null 2>&1 || { echo "Installing act $(ACT_VERSION)..."; \
		curl -sSfL https://raw.githubusercontent.com/nektos/act/master/install.sh | sudo bash -s -- -b /usr/local/bin v$(ACT_VERSION); \
	}

#ci-run: @ Run GitHub Actions workflow locally using act
ci-run: deps-act
	@act push --container-architecture linux/amd64 \
		--artifact-server-path /tmp/act-artifacts

# ── Renovate ────────────────────────────────────────────────────────────────

#renovate-validate: @ Validate Renovate configuration
renovate-validate:
	@npx --yes renovate --platform=local
