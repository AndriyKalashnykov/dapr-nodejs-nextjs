# syntax=docker/dockerfile:1@sha256:87999aa3d42bdc6bea60565083ee17e86d1f3339802f543c0d03998580f9cb89
# Build context is the repo root (see Makefile e2e-aca target).
FROM docker.io/node:24-alpine@sha256:a0b9bf06e4e6193cf7a0f58816cc935ff8c2a908f81e6f1a95432d679c54fbfd AS build
ENV NODE_ENV=production
RUN corepack enable && corepack prepare pnpm@11.14.0 --activate
WORKDIR /workspace
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc tsconfig.json ./
COPY packages ./packages
COPY app/backend-ts ./app/backend-ts
RUN pnpm install --frozen-lockfile --filter backend-ts...
RUN pnpm --filter @sos/sdk run compile && \
    pnpm --filter backend-ts run compile && \
    pnpm deploy --legacy --filter backend-ts --prod /deploy

# Runtime — no pnpm/corepack at runtime. Invoke tsx directly via node.
#
# Why: when CMD was `pnpm run start`, the `node` user's corepack had no
# activation cache (the build-stage `corepack prepare pnpm@11.14.0 --activate`
# runs as root and is per-user). At container start, corepack as `node`
# fell back to the base image's default pnpm (11.0.9), downloaded it, and
# pnpm 11's `depsStatusCheck` then tried to write a tmp file to /app which
# is owned root:root → EACCES → exit 243 → smoke-test failure on every PR.
# Mirrors the web-nextjs runtime (also pnpm-free).
FROM docker.io/node:24-alpine@sha256:a0b9bf06e4e6193cf7a0f58816cc935ff8c2a908f81e6f1a95432d679c54fbfd AS runtime
ENV NODE_ENV=production
# APP_INTERNAL_PORT externalizes the EXPOSE below (documentation of the Dapr
# app-port). No HEALTHCHECK: this backend listens on a Unix socket
# (/tmp/express-*.sock) and is fronted by its Dapr sidecar — nothing binds TCP
# on this port standalone, so a TCP/HTTP probe would mark the container
# unhealthy forever. Liveness is covered by the smoke test + the sidecar.
ARG APP_INTERNAL_PORT=3001
ENV APP_INTERNAL_PORT=${APP_INTERNAL_PORT}
WORKDIR /app
# Patch base-image system libs that lag the pinned digest. node:24-alpine
# ships libcrypto3/libssl3 3.5.6-r0 (CVE-2026-45447, HIGH); alpine v3.24/main
# publishes the fixed 3.5.7-r0. Run as root before dropping to `node`. This
# is a real upgrade (the CVE is gone from the image), not a Trivy waiver, and
# becomes a near no-op once the upstream digest rebases onto patched alpine.
#
# Also strip the globally-installed npm + corepack. The runtime invokes tsx
# directly via node (see CMD) and never shells out to a package manager, so
# both are dead weight — and npm bundles its own `undici` at
# /usr/local/lib/node_modules/npm/node_modules/undici (6.25.0 in this base),
# which carries CVE-2026-12151 (HIGH, unbounded-memory DoS; fixed in 6.27.0).
# That undici is part of the npm CLI, NOT a project dependency, so a pnpm
# override cannot reach it — removing npm eliminates the finding at the source
# (attack-surface reduction, not a Trivy waiver). Re-evaluate once the base
# image ships an npm whose bundled undici is >= 6.27.0.
# Cache-bust so the apk upgrade re-executes even when the layer is gha-cached
# (CI passes APK_UPGRADE_DATE=${{ github.run_id }} for per-run freshness; the
# Makefile passes a daily date). Without this a mid-week apk CVE fix is served
# stale from the cached layer. A changed in-scope ARG busts the FOLLOWING RUN.
ARG APK_UPGRADE_DATE=manual
RUN apk --no-cache upgrade && rm -rf /var/cache/apk/* \
    && rm -rf /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/corepack \
              /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack
# `node:*-alpine` ships with a non-root `node` user (UID 1000). Copy the
# deploy artifact owned by that user, then drop privileges before CMD.
COPY --from=build --chown=node:node /deploy ./
USER node
EXPOSE ${APP_INTERNAL_PORT}
CMD ["./node_modules/.bin/tsx", "--import", "./src/lib/instrumentation.ts", "src/main.ts"]
