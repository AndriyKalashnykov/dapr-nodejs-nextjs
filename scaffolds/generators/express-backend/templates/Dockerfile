# syntax=docker/dockerfile:1@sha256:87999aa3d42bdc6bea60565083ee17e86d1f3339802f543c0d03998580f9cb89
# Build context is the repo root.
FROM docker.io/node:24-alpine@sha256:a0b9bf06e4e6193cf7a0f58816cc935ff8c2a908f81e6f1a95432d679c54fbfd AS build
ENV NODE_ENV=production
RUN corepack enable && corepack prepare pnpm@11.15.1 --activate
WORKDIR /workspace
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc tsconfig.json ./
COPY packages ./packages
# hadolint ignore=DL3021
COPY app/<%= name %> ./app/<%= name %>
RUN pnpm install --frozen-lockfile --filter <%= name %>...
RUN pnpm --filter @sos/sdk run compile && \
    pnpm --filter <%= name %> run compile && \
    pnpm deploy --legacy --filter <%= name %> --prod /deploy

# Runtime — no pnpm/corepack at runtime. Invoke tsx directly via the
# deploy artifact's .bin/tsx shim. Mirrors app/backend-ts/Dockerfile; the
# previous `CMD ["pnpm","run","start"]` form tripped corepack's per-user
# activation trap (see PR #198) when the runtime USER (`node`) had no
# activated pin and fell back to the base image's default pnpm.
FROM docker.io/node:24-alpine@sha256:a0b9bf06e4e6193cf7a0f58816cc935ff8c2a908f81e6f1a95432d679c54fbfd AS runtime
ENV NODE_ENV=production
WORKDIR /app
# Patch base-image system libs that lag the pinned digest (run as root before
# dropping to `node`). A real upgrade, not a Trivy waiver; mirrors
# app/backend-ts/Dockerfile so scaffolded services don't reintroduce a
# fixable base-image CVE (e.g. libcrypto3/libssl3 CVE-2026-45447).
#
# Also strip the globally-installed npm + corepack: the runtime invokes tsx
# directly (./node_modules/.bin/tsx) and never shells out to a package manager,
# and npm bundles its own `undici` at
# /usr/local/lib/node_modules/npm/node_modules/undici (a base-image copy, NOT a
# project dependency — a pnpm override cannot reach it), which has carried HIGH
# CVEs (e.g. CVE-2026-12151). Removing npm eliminates that class at the source —
# attack-surface reduction, not a Trivy waiver.
RUN apk --no-cache upgrade && rm -rf /var/cache/apk/* \
    && rm -rf /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/corepack \
              /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack
COPY --from=build --chown=node:node /deploy ./
USER node
EXPOSE 3001
CMD ["./node_modules/.bin/tsx", "--import", "./src/lib/instrumentation.ts", "src/main.ts"]
