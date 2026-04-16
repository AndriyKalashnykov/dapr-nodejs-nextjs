.DEFAULT_GOAL := help

APP_NAME       := dapr-nodejs-nextjs
CURRENTTAG     := $(shell git describe --tags --abbrev=0 2>/dev/null || echo "dev")

# ── Pinned tool versions ────────────────────────────────────────────────────
# Single source of truth for node, dapr CLI, act, hadolint is `.mise.toml`.
# System tools (podman, git) are installed via the OS package manager below.

# ── Project constants ───────────────────────────────────────────────────────
COMPOSE_PROJECT  := demo-ts
NETWORK          := $(COMPOSE_PROJECT)_dapr-net
ALPINE_IMAGE     := alpine:3.21
POSTGRES_IMAGE   := postgres:18-alpine
REDIS_IMAGE      := redis:7-alpine

#help: @ List available tasks
help:
	@echo "Usage: make COMMAND"
	@echo "Commands :"
	@grep -E '[a-zA-Z\.\-]+:.*?@ .*$$' $(MAKEFILE_LIST)| tr -d '#' | awk 'BEGIN {FS = ":.*?@ "}; {printf "\033[32m%-28s\033[0m - %s\n", $$1, $$2}'

# ── Dependencies ──────────────────────────────────────────────────────────────

#deps: @ Install mise-managed tools (node, dapr, act, hadolint) and system deps (podman, git)
deps:
	@echo "Checking dependencies..."
	@command -v mise >/dev/null 2>&1 || { \
		echo "ERROR: mise is required. Install: https://mise.jdx.dev/getting-started.html"; \
		echo "  Linux:  curl https://mise.run | sh"; \
		echo "  macOS:  brew install mise"; \
		exit 1; \
	}
	@mise install
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
	@echo "All dependencies ready."

#deps-check: @ Print installed tool versions
deps-check:
	@echo "node:    $$(node --version 2>/dev/null || echo 'not installed')"
	@echo "npm:     $$(npm --version 2>/dev/null || echo 'not installed')"
	@echo "podman:  $$(podman --version 2>/dev/null || echo 'not installed')"
	@echo "dapr:    $$(dapr version --output json 2>/dev/null | grep -o '"Cli version":"[^"]*"' || echo 'not installed')"
	@echo "git:     $$(git --version 2>/dev/null || echo 'not installed')"
	@echo "act:     $$(act --version 2>/dev/null || echo 'not installed')"
	@echo "hadolint: $$(hadolint --version 2>/dev/null || echo 'not installed')"

#install: @ Install npm dependencies
install: deps
	@npm ci

#clean: @ Remove build artifacts and node_modules
clean:
	@rm -rf node_modules/
	@rm -rf packages/@sos/sdk/build/
	@rm -rf app/backend-ts/dist/
	@rm -rf app/web-nextjs/.next/

# ── Build ─────────────────────────────────────────────────────────────────────

#setup: @ Build base Docker images (run once after clone)
setup: deps
	@echo "\n***Building microservice base image***\n"
	@podman build ./shared/microservice -t microservice-build --build-arg ADD_CERT=$$ADD_CERT
	@podman build -f Dockerfile.dev -t microservice-sdk-build .

#build: @ Build all service containers in parallel
build: deps
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

#format: @ Auto-format code with Prettier across all workspaces
format: install
	@npx prettier --write .

#lint: @ Run lint and typecheck across all workspaces + Terraform validate/tflint
lint: install infra-validate mermaid-lint
	@npm run ci -w packages/@sos/sdk
	@npm run ci -w app/backend-ts
	@npm run lint -w app/web-nextjs
	@find . -name 'Dockerfile*' -not -path '*/node_modules/*' -not -path '*/.next/*' | xargs hadolint

#vulncheck: @ Run npm audit for known vulnerabilities
vulncheck: install
	@npm audit --audit-level=moderate || true

#test: @ Run unit tests across SDK and backend
test: install
	@npm run test:cov -w packages/@sos/sdk
	@npm run test:cov -w app/backend-ts

#test-integration: @ Run backend integration tests (requires Postgres + Dapr sidecar)
test-integration: install
	@podman exec demo-ts-postgres-1 psql -U postgres -d postgres -c "CREATE SCHEMA IF NOT EXISTS backend_ts_test;" 2>/dev/null || true
	@NODE_ENV=test SERVICE_NAME=backend-ts DB_HOST=localhost DB_PORT=5432 DB_NAME=postgres DB_SCHEMA=backend_ts JWT_SECRET_KEY=secret DAPR_HOST=localhost DAPR_PORT=3500 npm run test:integration:cov -w app/backend-ts

#e2e: @ Run end-to-end smoke test against the full compose stack
e2e: build
	@echo "\n***Starting stack for e2e***\n"
	@podman compose up -d
	@echo "\n***Running e2e/e2e-test.sh***\n"
	@bash e2e/e2e-test.sh; status=$$?; \
	 echo "\n***Tearing down stack***\n"; \
	 podman compose down >/dev/null 2>&1 || true; \
	 exit $$status

#e2e-browser: @ Run Playwright browser e2e against the running stack (requires `make up` first)
e2e-browser: install
	@npx playwright install --with-deps chromium >/dev/null 2>&1 || true
	@npx playwright test --config e2e/playwright/playwright.config.ts

# renovate: datasource=docker depName=minlag/mermaid-cli
MERMAID_CLI_VERSION := 11.12.0

#mermaid-lint: @ Validate every ```mermaid block in markdown using minlag/mermaid-cli (same engine GitHub uses)
mermaid-lint:
	@files=$$(grep -lF '```mermaid' README.md CLAUDE.md docs/*.md 2>/dev/null); \
	 if [ -z "$$files" ]; then echo "No mermaid blocks found."; exit 0; fi; \
	 echo "Linting mermaid blocks in: $$files"; \
	 mkdir -p /tmp/mermaid-out; \
	 for f in $$files; do \
	   docker run --rm -u $$(id -u):$$(id -g) -v $$(pwd):/data -v /tmp/mermaid-out:/out \
	     minlag/mermaid-cli:$(MERMAID_CLI_VERSION) \
	     -i /data/$$f -o /out/$$(basename $$f .md).out.md >/dev/null \
	     || { echo "mermaid lint failed in $$f"; exit 1; }; \
	 done; \
	 rm -rf /tmp/mermaid-out; \
	 echo "All mermaid blocks valid."

#infra-validate: @ Offline Terraform validation — syntax, types, fmt, tflint (no Azure credentials needed)
infra-validate:
	@echo "\n***terraform fmt -check***\n"
	@cd infra/azure && mise exec -- terraform fmt -check -recursive
	@echo "\n***terraform init (no backend) + validate***\n"
	@cd infra/azure && mise exec -- terraform init -backend=false -input=false >/dev/null
	@cd infra/azure && mise exec -- terraform validate
	@rm -rf infra/azure/.terraform
	@echo "\n***tflint (azurerm ruleset)***\n"
	@docker run --rm -v $$(pwd)/infra/azure:/data -w /data -e TFLINT_PLUGIN_DIR=/data/.tflint.d/plugins ghcr.io/terraform-linters/tflint:latest --init >/dev/null
	@docker run --rm -v $$(pwd)/infra/azure:/data -w /data -e TFLINT_PLUGIN_DIR=/data/.tflint.d/plugins ghcr.io/terraform-linters/tflint:latest --recursive --minimum-failure-severity=error

#e2e-aca: @ Deploy to Azure Container Apps, run smoke test, destroy. INCURS AZURE COST (~$0.30–$1/run). Requires: az login (OIDC in CI), TF_VAR_AZURE_SUBSCRIPTION_ID, TF_VAR_jwt_secret_key, GIT_SHA.
e2e-aca:
	@: $${TF_VAR_AZURE_SUBSCRIPTION_ID:?required}
	@: $${TF_VAR_jwt_secret_key:?required — seeded into Key Vault}
	@SHA=$${GIT_SHA:-$$(git rev-parse --short HEAD)} ; \
	 echo "\n***Building + pushing images tag=$$SHA***\n" && \
	 cd infra/azure && terraform init -input=false && \
	 ACR=$$(terraform output -raw container_registry_login_server 2>/dev/null || echo "") && \
	 cd ../.. && \
	 if [ -z "$$ACR" ]; then \
	   echo "ACR not yet provisioned — running initial apply to create it"; \
	   cd infra/azure && terraform apply -input=false -auto-approve \
	     -target=module.container_registry && cd ../..; \
	   ACR=$$(cd infra/azure && terraform output -raw container_registry_login_server); \
	 fi && \
	 az acr login --name "$${ACR%%.*}" && \
	 docker build -t $$ACR/backend-ts:$$SHA -f app/backend-ts/Dockerfile . && \
	 docker build -t $$ACR/web-nextjs:$$SHA -f app/web-nextjs/Dockerfile app/web-nextjs && \
	 docker push $$ACR/backend-ts:$$SHA && \
	 docker push $$ACR/web-nextjs:$$SHA && \
	 echo "\n***terraform apply (tag=$$SHA)***\n" && \
	 cd infra/azure && terraform apply -input=false -auto-approve \
	   -var "backend_image_tag=$$SHA" -var "nextjs_image_tag=$$SHA" && cd ../.. && \
	 echo "\n***Running e2e/e2e-aca.sh***\n" && \
	 TF_DIR=infra/azure JWT_SECRET_KEY="$$TF_VAR_jwt_secret_key" bash e2e/e2e-aca.sh; \
	 status=$$? ; \
	 echo "\n***terraform destroy (always)***\n" && \
	 (cd infra/azure && terraform destroy -input=false -auto-approve \
	    -var "backend_image_tag=$$SHA" -var "nextjs_image_tag=$$SHA" >/dev/null 2>&1 || true) ; \
	 exit $$status

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

#web-nextjs-test: @ Next.js: unit tests with coverage
web-nextjs-test: install
	@npm run test:cov -w app/web-nextjs

#web-nextjs-ci: @ Next.js: lint, test, and build
web-nextjs-ci: install
	@npm run lint -w app/web-nextjs
	@npm run test:cov -w app/web-nextjs
	@JWT_SECRET_KEY=ci-build-placeholder npm run build -w app/web-nextjs

# ── Database ─────────────────────────────────────────────────────────────────

#psql: @ Connect to PostgreSQL CLI (default password: postgres)
psql:
	@echo "\n***Default user 'postgres' has default password 'postgres'***\n"
	@podman run -it --rm --network $(NETWORK) $(POSTGRES_IMAGE) psql -h postgres -U postgres

#migrate: @ Run pending database migrations in running backend-ts container
migrate:
	@podman compose exec backend-ts npm run knex -w app/backend-ts -- migrate:latest

# ── Diagnostics ──────────────────────────────────────────────────────────────

#redis-cli: @ Connect to Redis CLI
redis-cli:
	@podman run -it --rm --network $(NETWORK) $(REDIS_IMAGE) redis-cli -h redis

#shell: @ Open an alpine shell on the dapr-net network (for nc, ping, etc.)
shell:
	@podman run -it --rm --network $(NETWORK) $(ALPINE_IMAGE)

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

#ci: @ Run full CI pipeline locally (lint + vulncheck + test + build)
ci: lint vulncheck test build
	@echo "\n***CI pipeline passed.***\n"

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

#ci-run: @ Run GitHub Actions workflow locally using act (mise-managed)
ci-run: deps
	@act push --container-architecture linux/amd64 \
		--artifact-server-path /tmp/act-artifacts

# ── Renovate ────────────────────────────────────────────────────────────────

#renovate-validate: @ Validate Renovate configuration
renovate-validate: deps
	@if [ -n "$$GH_ACCESS_TOKEN" ]; then \
		GITHUB_COM_TOKEN=$$GH_ACCESS_TOKEN npx --yes renovate --platform=local; \
	else \
		echo "Warning: GH_ACCESS_TOKEN not set, some dependency lookups may fail"; \
		npx --yes renovate --platform=local; \
	fi

.PHONY: help deps deps-check install clean \
        setup build compile \
        up run up-db up-dapr up-otel up-infra down down-otel \
        debug terminal format lint vulncheck test test-integration \
        sdk-ci backend-lint backend-test backend-test-integration \
        web-nextjs-ci web-nextjs-test \
        e2e e2e-browser e2e-aca infra-validate mermaid-lint \
        psql migrate redis-cli shell logs \
        prune login update upgrade \
        ci check-version release ci-run renovate-validate
