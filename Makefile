.DEFAULT_GOAL := help

# Strict bash for every recipe — `set -eu -o pipefail` catches errors mid-recipe
# instead of silently swallowing them. Also enables `printf '\n...\n'` to be
# portable (literal `\n` in `echo` is dash-incompatible).
SHELL       := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

APP_NAME       := dapr-nodejs-nextjs
CURRENTTAG     := $(shell git describe --tags --abbrev=0 2>/dev/null || echo "dev")

# ── Pinned tool versions ────────────────────────────────────────────────────
# Single source of truth for node, pnpm, dapr CLI, act, hadolint, tflint,
# gitleaks, trivy, terraform is `.mise.toml` — see Renovate `customManagers`.
# System tools (podman, git) are installed via the OS package manager below.

# ── Project constants ───────────────────────────────────────────────────────
COMPOSE_PROJECT  := demo-ts
NETWORK          := $(COMPOSE_PROJECT)_dapr-net
ALPINE_IMAGE     := alpine:3.21
POSTGRES_IMAGE   := postgres:18-alpine
REDIS_IMAGE      := redis:7-alpine

# Container runtime — project standard is podman; fall back to docker for
# environments without podman (some CI runners). Used by every recipe that
# runs an OCI image.
CONTAINER_CMD    ?= $(shell command -v podman 2>/dev/null || echo docker)

# Mermaid CLI is consumed as an OCI image (no native binary). Renovate tracks
# the digest below; mise has no aqua entry for `minlag/mermaid-cli`.
# renovate: datasource=docker depName=minlag/mermaid-cli
MERMAID_CLI_VERSION := 11.12.0

#help: @ List available tasks
help:
	@echo "Usage: make COMMAND"
	@echo "Commands :"
	@grep -E '[a-zA-Z\.\-]+:.*?@ .*$$' $(MAKEFILE_LIST)| tr -d '#' | awk 'BEGIN {FS = ":.*?@ "}; {printf "\033[32m%-28s\033[0m - %s\n", $$1, $$2}'

# ── Dependencies ──────────────────────────────────────────────────────────────

#deps: @ Install mise-managed tools (.mise.toml) and system deps (podman, git)
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
	@echo "node:     $$(node --version 2>/dev/null || echo 'not installed')"
	@echo "pnpm:     $$(pnpm --version 2>/dev/null || echo 'not installed')"
	@echo "podman:   $$(podman --version 2>/dev/null || echo 'not installed')"
	@echo "dapr:     $$(dapr version --output json 2>/dev/null | grep -o '\"Cli version\":\"[^\"]*\"' || echo 'not installed')"
	@echo "git:      $$(git --version 2>/dev/null || echo 'not installed')"
	@echo "act:      $$(act --version 2>/dev/null || echo 'not installed')"
	@echo "hadolint: $$(hadolint --version 2>/dev/null || echo 'not installed')"
	@echo "tflint:   $$(tflint --version 2>/dev/null | head -1 || echo 'not installed')"
	@echo "gitleaks: $$(gitleaks version 2>/dev/null || echo 'not installed')"
	@echo "trivy:    $$(trivy --version 2>/dev/null | head -1 || echo 'not installed')"

#deps-prune: @ Remove unused npm/pnpm dependencies (depcheck)
deps-prune: install
	@printf '\n***depcheck — checking for unused dependencies***\n\n'
	@pnpm dlx depcheck@1.4.7 --skip-missing app/backend-ts || true
	@pnpm dlx depcheck@1.4.7 --skip-missing app/web-nextjs || true
	@pnpm dlx depcheck@1.4.7 --skip-missing packages/@sos/sdk || true

#deps-prune-check: @ Fail if depcheck reports unused dependencies (CI gate)
deps-prune-check: install
	@pnpm dlx depcheck@1.4.7 --skip-missing app/backend-ts
	@pnpm dlx depcheck@1.4.7 --skip-missing app/web-nextjs
	@pnpm dlx depcheck@1.4.7 --skip-missing packages/@sos/sdk

#install: @ Install pnpm dependencies
install: deps
	@pnpm install --frozen-lockfile

#clean: @ Remove build artifacts and node_modules
clean:
	@rm -rf node_modules/
	@rm -rf packages/@sos/sdk/build/
	@rm -rf app/backend-ts/dist/
	@rm -rf app/web-nextjs/.next/

# ── Build ─────────────────────────────────────────────────────────────────────

#setup: @ Build base Docker images (run once after clone)
setup: deps
	@printf '\n***Building microservice base image***\n\n'
	@$(CONTAINER_CMD) build ./shared/microservice -t microservice-build --build-arg ADD_CERT=$$ADD_CERT
	@$(CONTAINER_CMD) build -f Dockerfile.dev -t microservice-sdk-build .

#build: @ Build all service containers in parallel
build: deps
	@$(CONTAINER_CMD) compose --parallel 3 build

#compile: @ Compile SDK and backend TypeScript
compile: install
	@pnpm --filter @sos/sdk run compile
	@pnpm --filter backend-ts run compile

# ── Stack Management ─────────────────────────────────────────────────────────

#up: @ Bring up the full stack (Ctrl-C to stop)
up:
	@printf '\n***Bringing up the stack***\n\n'
	@$(CONTAINER_CMD) compose up

#run: @ Alias for 'up' – bring up the full stack
run: up

#up-db: @ Bring up PostgreSQL only
up-db:
	@printf '\n***Bringing up the db***\n\n'
	@$(CONTAINER_CMD) compose up postgres postgres-build-dbs

#up-dapr: @ Bring up Dapr infrastructure (Redis, Zipkin, placement, dashboard)
up-dapr:
	@printf '\n***Bringing up Dapr services***\n\n'
	@$(CONTAINER_CMD) compose up placement redis zipkin dapr-dashboard

#up-otel: @ Bring up Grafana OpenTelemetry stack (detached)
up-otel:
	@printf '\n***Bringing up the OpenTelemetry services***\n\n'
	@cd shared/otel && $(CONTAINER_CMD) compose up -d grafana-otel

#up-infra: @ Bring up OpenTelemetry + database
up-infra: up-otel up-db

#down: @ Tear down the full stack
down:
	@$(CONTAINER_CMD) compose down

#down-otel: @ Tear down Grafana OpenTelemetry stack
down-otel:
	@printf '\n***Shutting down the OpenTelemetry services***\n\n'
	@cd shared/otel && $(CONTAINER_CMD) compose down grafana-otel

# ── Development ──────────────────────────────────────────────────────────────

#debug: @ Start a service in debug mode (SERVICE=backend-ts make debug)
debug:
	@if [ -z "$$SERVICE" ]; then echo "ERROR: SERVICE is required. Usage: SERVICE=backend-ts make debug"; exit 1; fi
	@$(CONTAINER_CMD) image exists microservice-sdk-build 2>/dev/null || $(MAKE) setup
	@printf '\n***Starting %s in debug mode***\n\n' "$$SERVICE"
	@$(CONTAINER_CMD) compose -f docker-compose.yaml -f app/$$SERVICE/docker-compose.debug.yaml up

#terminal: @ Open a shell in a running service container (SERVICE=backend-ts make terminal)
terminal:
	@if [ -z "$$SERVICE" ]; then echo "ERROR: SERVICE is required. Usage: SERVICE=backend-ts make terminal"; exit 1; fi
	@$(CONTAINER_CMD) compose exec -it $$SERVICE /bin/sh

#format: @ Auto-format code with Prettier across all workspaces
format: install
	@pnpm exec prettier --write .

#lint: @ Run lint and typecheck across all workspaces (also: hadolint, scripts +x guard, terraform validate, mermaid)
lint: install lint-scripts-exec infra-validate mermaid-lint
	@pnpm --filter @sos/sdk run ci
	@pnpm --filter backend-ts run ci
	@pnpm --filter web-nextjs run lint
	@find . -name 'Dockerfile*' -not -path '*/node_modules/*' -not -path '*/.next/*' -print0 | xargs -0 -r hadolint

#lint-scripts-exec: @ Fail if any tracked shell script under scripts/ is missing the executable bit
lint-scripts-exec:
	@nonexec=$$(find scripts -name '*.sh' -not -executable 2>/dev/null); \
	 if [ -n "$$nonexec" ]; then \
	   printf 'ERROR: shell scripts missing +x bit:\n%s\n' "$$nonexec"; \
	   echo "Fix: chmod +x <file> && git add --chmod=+x <file>"; \
	   exit 1; \
	 fi

#vulncheck: @ Run pnpm audit for known vulnerabilities (fails on moderate+)
vulncheck: install
	@pnpm audit --audit-level=moderate

#secrets: @ Scan repo for committed secrets via gitleaks
secrets: deps
	@printf '\n***gitleaks — scanning for secrets***\n\n'
	@if [ -f .gitleaks.toml ]; then \
	   gitleaks detect --source . --redact --no-banner --no-git --exit-code 1 --config=.gitleaks.toml; \
	 else \
	   gitleaks detect --source . --redact --no-banner --no-git --exit-code 1; \
	 fi

#trivy-fs: @ Trivy filesystem scan (CVEs + secrets + misconfigs) on the repo
trivy-fs: deps
	@printf '\n***trivy — filesystem scan (CRITICAL,HIGH)***\n\n'
	@trivy fs \
	   --scanners vuln,secret,misconfig \
	   --severity CRITICAL,HIGH \
	   --ignore-unfixed \
	   --skip-dirs node_modules,.next,build,dist,coverage,packages/@sos/sdk/build,scaffolds \
	   --ignorefile .trivyignore.yaml \
	   --exit-code 1 \
	   .

#static-check: @ Composite quality gate: lint + vulncheck + secrets + trivy-fs + mermaid-lint
static-check: lint vulncheck secrets trivy-fs

#test: @ Run unit tests across SDK and backend
test: install
	@pnpm --filter @sos/sdk run test:cov
	@pnpm --filter backend-ts run test:cov

#ci-dapr-up: @ Bring up Dapr sidecar in slim mode (CI: integration-test job)
ci-dapr-up:
	@printf '\n***Initializing Dapr (slim, no Docker)***\n\n'
	@dapr init --slim 2>&1 | tail -5
	@mkdir -p "$$HOME/.dapr/components"
	@sed "s|__HOME__|$$HOME|g" scripts/ci-dapr/local-secretstore.yaml \
	   > "$$HOME/.dapr/components/local-secretstore.yaml"
	@cp scripts/ci-dapr/secrets.json "$$HOME/.dapr/secrets.json"
	@printf '\n***Starting Dapr sidecar (port 3500)***\n\n'
	@PATH="$$HOME/.dapr/bin:$$PATH" daprd \
	   --app-id backend-ts \
	   --dapr-http-port 3500 \
	   --resources-path "$$HOME/.dapr/components" \
	   --log-level error \
	   > /tmp/daprd.log 2>&1 &
	@printf 'Waiting for Dapr sidecar on :3500...\n'
	@timeout 30 bash -c \
	   'until curl -sf http://localhost:3500/v1.0/healthz > /dev/null; do sleep 1; done' \
	   || { echo "=== daprd log ==="; cat /tmp/daprd.log; exit 1; }
	@printf 'Dapr sidecar ready.\n'

#ci-db-prepare: @ Create the integration-test schema (CI: integration-test job)
ci-db-prepare:
	@printf '\n***Creating backend_ts_test schema***\n\n'
	@PGPASSWORD=postgres psql -h localhost -U postgres -d postgres \
	   -c "CREATE SCHEMA IF NOT EXISTS backend_ts_test;"

#integration-test: @ Run backend integration tests (requires Postgres + Dapr sidecar)
integration-test: install
	@$(CONTAINER_CMD) exec demo-ts-postgres-1 psql -U postgres -d postgres -c "CREATE SCHEMA IF NOT EXISTS backend_ts_test;" 2>/dev/null || true
	@NODE_ENV=test SERVICE_NAME=backend-ts DB_HOST=localhost DB_PORT=5432 DB_NAME=postgres DB_SCHEMA=backend_ts JWT_SECRET_KEY=secret DAPR_HOST=localhost DAPR_PORT=3500 pnpm --filter backend-ts run test:integration:cov

#test-integration: @ Deprecated alias for integration-test (kept for compatibility)
test-integration: integration-test

#e2e: @ Run end-to-end smoke test against the full compose stack
e2e: build
	@printf '\n***Starting stack for e2e***\n\n'
	@$(CONTAINER_CMD) compose up -d
	@printf '\n***Running e2e/e2e-test.sh***\n\n'
	@bash e2e/e2e-test.sh; status=$$?; \
	 printf '\n***Tearing down stack***\n\n'; \
	 $(CONTAINER_CMD) compose down >/dev/null 2>&1 || true; \
	 exit $$status

#e2e-browser: @ Run Playwright browser e2e against the running stack (requires `make up` first)
e2e-browser: install
	@pnpm exec playwright install --with-deps chromium >/dev/null 2>&1 || true
	@pnpm exec playwright test --config e2e/playwright/playwright.config.ts

#mermaid-lint: @ Validate every ```mermaid block in markdown using minlag/mermaid-cli (same engine GitHub uses)
mermaid-lint:
	@command -v $(CONTAINER_CMD) >/dev/null 2>&1 || { echo "ERROR: $(CONTAINER_CMD) is required for mermaid-lint"; exit 1; }
	@files=$$(grep -lF '```mermaid' README.md CLAUDE.md docs/*.md 2>/dev/null || true); \
	 if [ -z "$$files" ]; then echo "No mermaid blocks found."; exit 0; fi; \
	 echo "Linting mermaid blocks in: $$files"; \
	 image="docker.io/minlag/mermaid-cli:$(MERMAID_CLI_VERSION)"; \
	 attempt=1; until $(CONTAINER_CMD) image inspect "$$image" >/dev/null 2>&1; do \
	   echo "Pulling $$image (attempt $$attempt/3)..."; \
	   if $(CONTAINER_CMD) pull "$$image"; then break; fi; \
	   attempt=$$((attempt+1)); [ $$attempt -gt 3 ] && { echo "ERROR: failed to pull $$image"; exit 1; }; \
	   sleep 2; \
	 done; \
	 outdir=$$(mktemp -d); chmod 777 "$$outdir"; trap "rm -rf $$outdir" EXIT; \
	 errlog=$$(mktemp); \
	 status=0; \
	 for f in $$files; do \
	   if ! $(CONTAINER_CMD) run --rm \
	        -v "$$PWD:/data:ro" -v "$$outdir:/out" \
	        "$$image" \
	        -i "/data/$$f" -o "/out/$$(basename $$f .md).out.md" \
	        >"$$errlog" 2>&1; \
	   then \
	     echo "ERROR: mermaid lint failed in $$f"; \
	     cat "$$errlog"; \
	     status=1; break; \
	   fi; \
	 done; \
	 rm -f "$$errlog"; \
	 [ $$status -eq 0 ] && echo "All mermaid blocks valid."; \
	 exit $$status

#infra-validate: @ Offline Terraform validation — syntax, types, fmt, tflint (no Azure credentials needed)
infra-validate: deps
	@printf '\n***terraform fmt -check***\n\n'
	@cd infra/azure && mise exec -- terraform fmt -check -recursive
	@printf '\n***terraform init (no backend) + validate***\n\n'
	@cd infra/azure && mise exec -- terraform init -backend=false -input=false >/dev/null
	@cd infra/azure && mise exec -- terraform validate
	@rm -rf infra/azure/.terraform
	@printf '\n***tflint (azurerm ruleset)***\n\n'
	@mkdir -p "$$HOME/.cache/tflint/plugins"
	@cd infra/azure && TFLINT_PLUGIN_DIR=$$HOME/.cache/tflint/plugins mise exec -- tflint --init >/dev/null
	@cd infra/azure && TFLINT_PLUGIN_DIR=$$HOME/.cache/tflint/plugins mise exec -- tflint --recursive --minimum-failure-severity=error

# ── Terraform (Azure stack) ──────────────────────────────────────────────────

#tf-init: @ terraform init in infra/azure (no backend prompt)
tf-init:
	@cd infra/azure && terraform init -input=false

#tf-apply-acr: @ Targeted apply: provision only the Azure Container Registry
tf-apply-acr: tf-init
	@cd infra/azure && terraform apply -input=false -auto-approve -target=module.container_registry

#tf-acr-login-server: @ Print the ACR login server FQDN (requires `make tf-init`)
tf-acr-login-server:
	@cd infra/azure && terraform output -raw container_registry_login_server

#tf-apply: @ Full apply (requires GIT_SHA and provisioned ACR)
tf-apply: tf-init
	@: $${GIT_SHA:?required — image tag to deploy}
	@cd infra/azure && terraform apply -input=false -auto-approve \
	   -var "backend_image_tag=$$GIT_SHA" \
	   -var "nextjs_image_tag=$$GIT_SHA"

#tf-destroy: @ Destroy the ACA stack (requires GIT_SHA used at apply time)
tf-destroy: tf-init
	@: $${GIT_SHA:?required — image tag used at apply time}
	@cd infra/azure && terraform destroy -input=false -auto-approve \
	   -var "backend_image_tag=$$GIT_SHA" \
	   -var "nextjs_image_tag=$$GIT_SHA"

# ── Image build + scan (CI: docker job) ──────────────────────────────────────

#image-build-prod: @ Build a production image for SERVICE (backend-ts | web-nextjs); requires SERVICE + IMAGE_TAG
image-build-prod:
	@: $${SERVICE:?required — backend-ts or web-nextjs}
	@: $${IMAGE_TAG:?required — image tag}
	@docker buildx build --load \
	   --tag "$$SERVICE:$$IMAGE_TAG" \
	   -f app/$$SERVICE/Dockerfile .

#image-scan-prod: @ Trivy-scan an image built by image-build-prod (CRITICAL,HIGH blocking)
image-scan-prod:
	@: $${SERVICE:?required — backend-ts or web-nextjs}
	@: $${IMAGE_TAG:?required — image tag}
	@trivy image \
	   --scanners vuln,secret,misconfig \
	   --severity CRITICAL,HIGH \
	   --ignore-unfixed \
	   --ignorefile .trivyignore.yaml \
	   --exit-code 1 \
	   "$$SERVICE:$$IMAGE_TAG"

#image-push-multi-arch: @ Build + push multi-arch (linux/amd64,linux/arm64) to REGISTRY; requires SERVICE + IMAGE_TAG + REGISTRY
image-push-multi-arch:
	@: $${SERVICE:?required — backend-ts or web-nextjs}
	@: $${IMAGE_TAG:?required — image tag}
	@: $${REGISTRY:?required — fully-qualified registry FQDN (e.g. myacr.azurecr.io)}
	@docker buildx build \
	   --platform linux/amd64,linux/arm64 \
	   --push \
	   --tag "$$REGISTRY/$$SERVICE:$$IMAGE_TAG" \
	   -f app/$$SERVICE/Dockerfile .

#e2e-aca: @ Deploy to Azure Container Apps, run smoke test, destroy. INCURS AZURE COST (~$0.30–$1/run). Requires: az login (OIDC in CI), TF_VAR_AZURE_SUBSCRIPTION_ID, TF_VAR_jwt_secret_key, GIT_SHA.
e2e-aca:
	@: $${TF_VAR_AZURE_SUBSCRIPTION_ID:?required}
	@: $${TF_VAR_jwt_secret_key:?required — seeded into Key Vault}
	@SHA=$${GIT_SHA:-$$(git rev-parse --short HEAD)} ; \
	 printf '\n***Building + pushing images tag=%s***\n\n' "$$SHA" && \
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
	 docker build -t $$ACR/web-nextjs:$$SHA -f app/web-nextjs/Dockerfile . && \
	 docker push $$ACR/backend-ts:$$SHA && \
	 docker push $$ACR/web-nextjs:$$SHA && \
	 printf '\n***terraform apply (tag=%s)***\n\n' "$$SHA" && \
	 cd infra/azure && terraform apply -input=false -auto-approve \
	   -var "backend_image_tag=$$SHA" -var "nextjs_image_tag=$$SHA" && cd ../.. && \
	 printf '\n***Running e2e/e2e-aca.sh***\n\n' && \
	 TF_DIR=infra/azure JWT_SECRET_KEY="$$TF_VAR_jwt_secret_key" bash e2e/e2e-aca.sh; \
	 status=$$? ; \
	 printf '\n***terraform destroy (always)***\n\n' && \
	 (cd infra/azure && terraform destroy -input=false -auto-approve \
	    -var "backend_image_tag=$$SHA" -var "nextjs_image_tag=$$SHA" >/dev/null 2>&1 || true) ; \
	 exit $$status

# ── Per-workspace CI targets (used by GitHub Actions) ────────────────────────

#sdk-ci: @ SDK: compile, lint, and test
sdk-ci: install
	@pnpm --filter @sos/sdk run compile
	@pnpm --filter @sos/sdk run ci
	@pnpm --filter @sos/sdk run test:cov

#backend-lint: @ Backend: lint and typecheck
backend-lint: install
	@pnpm --filter backend-ts run ci

#backend-test: @ Backend: unit tests with coverage
backend-test: install
	@pnpm --filter backend-ts run test:cov

#backend-test-integration: @ Backend: integration tests with coverage (requires Postgres + Dapr)
backend-test-integration: install
	@NODE_ENV=test SERVICE_NAME=backend-ts DB_HOST=localhost DB_PORT=5432 DB_NAME=postgres DB_SCHEMA=backend_ts JWT_SECRET_KEY=secret DAPR_HOST=localhost DAPR_PORT=3500 pnpm --filter backend-ts run test:integration:cov

#web-nextjs-test: @ Next.js: unit tests with coverage
web-nextjs-test: install
	@pnpm --filter web-nextjs run test:cov

#web-nextjs-ci: @ Next.js: lint, test, and build
web-nextjs-ci: install
	@pnpm --filter web-nextjs run lint
	@pnpm --filter web-nextjs run test:cov
	@JWT_SECRET_KEY=ci-build-placeholder pnpm --filter web-nextjs run build

# ── Database ─────────────────────────────────────────────────────────────────

#psql: @ Connect to PostgreSQL CLI (default password: postgres)
psql:
	@printf '\n***Default user '\''postgres'\'' has default password '\''postgres'\''***\n\n'
	@$(CONTAINER_CMD) run -it --rm --network $(NETWORK) $(POSTGRES_IMAGE) psql -h postgres -U postgres

#migrate: @ Run pending database migrations in running backend-ts container
migrate:
	@$(CONTAINER_CMD) compose exec backend-ts pnpm run knex -- migrate:latest

# ── Diagnostics ──────────────────────────────────────────────────────────────

#redis-cli: @ Connect to Redis CLI
redis-cli:
	@$(CONTAINER_CMD) run -it --rm --network $(NETWORK) $(REDIS_IMAGE) redis-cli -h redis

#shell: @ Open an alpine shell on the dapr-net network (for nc, ping, etc.)
shell:
	@$(CONTAINER_CMD) run -it --rm --network $(NETWORK) $(ALPINE_IMAGE)

#logs: @ Tail logs for a specific service (SERVICE=backend-ts make logs)
logs:
	@if [ -z "$$SERVICE" ]; then echo "ERROR: SERVICE is required. Usage: SERVICE=backend-ts make logs"; exit 1; fi
	@$(CONTAINER_CMD) compose logs -f $$SERVICE

# ── Maintenance ──────────────────────────────────────────────────────────────

#prune: @ Remove unused Podman containers, images, and volumes
prune:
	@$(CONTAINER_CMD) system prune -f
	@$(CONTAINER_CMD) volume prune -f --filter label!=io.podman.compose.project=$(COMPOSE_PROJECT)

#login: @ Login to Docker Hub via Podman
login:
	@$(CONTAINER_CMD) login docker.io

#update: @ Update pnpm dependencies to latest allowed versions
update: deps
	@pnpm update

# renovate: datasource=npm depName=npm-check-updates
NPM_CHECK_UPDATES_VERSION := 22.0.1

#upgrade: @ Upgrade pnpm dependencies to latest versions (ignoring ranges)
upgrade: deps
	@pnpm dlx npm-check-updates@$(NPM_CHECK_UPDATES_VERSION) -u
	@pnpm install

# ── CI / Release ─────────────────────────────────────────────────────────────

#ci: @ Run full CI pipeline locally (static-check + test + build)
ci: static-check test build
	@printf '\n***CI pipeline passed.***\n\n'

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

# Jobs that work cleanly under act (no docker-in-docker required).
ACT_JOBS ?= changes static-check build test web-nextjs

#ci-run: @ Run GitHub Actions workflow locally using act (mise-managed). Skips e2e (DinD).
ci-run: deps
	@port=$$(shuf -i 40000-59999 -n 1); \
	 artifacts=$$(mktemp -d); \
	 secret_arg=""; \
	 if [ -n "$${GH_ACCESS_TOKEN:-}" ]; then \
	   secret_arg="--secret GH_ACCESS_TOKEN=$$GH_ACCESS_TOKEN"; \
	 fi; \
	 trap "rm -rf $$artifacts" EXIT; \
	 status=0; \
	 for j in $(ACT_JOBS); do \
	   echo "==> act push --job $$j"; \
	   if ! act push --job "$$j" \
	        --container-architecture linux/amd64 \
	        --artifact-server-port "$$port" \
	        --artifact-server-path "$$artifacts" \
	        $$secret_arg; then \
	     echo "act job $$j failed"; status=1; break; \
	   fi; \
	 done; \
	 exit $$status

# ── Renovate ────────────────────────────────────────────────────────────────

# renovate: datasource=npm depName=renovate
RENOVATE_VERSION := 43.150.0

#renovate-validate: @ Validate Renovate configuration
renovate-validate: deps
	@if [ -n "$${GH_ACCESS_TOKEN:-}" ]; then \
		GITHUB_COM_TOKEN=$$GH_ACCESS_TOKEN pnpm dlx renovate@$(RENOVATE_VERSION) --platform=local; \
	else \
		echo "Warning: GH_ACCESS_TOKEN not set, some dependency lookups may fail"; \
		pnpm dlx renovate@$(RENOVATE_VERSION) --platform=local; \
	fi

.PHONY: help deps deps-check deps-prune deps-prune-check install clean \
        setup build compile \
        up run up-db up-dapr up-otel up-infra down down-otel \
        debug terminal format \
        lint lint-scripts-exec vulncheck secrets trivy-fs static-check \
        test integration-test test-integration \
        ci-dapr-up ci-db-prepare \
        sdk-ci backend-lint backend-test backend-test-integration \
        web-nextjs-ci web-nextjs-test \
        e2e e2e-browser e2e-aca infra-validate mermaid-lint \
        tf-init tf-apply-acr tf-acr-login-server tf-apply tf-destroy \
        image-build-prod image-scan-prod image-push-multi-arch \
        psql migrate redis-cli shell logs \
        prune login update upgrade \
        ci check-version release ci-run renovate-validate
