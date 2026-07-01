# syntax=docker/dockerfile:1@sha256:87999aa3d42bdc6bea60565083ee17e86d1f3339802f543c0d03998580f9cb89
# Build context is the repo root.
FROM docker.io/node:24-alpine@sha256:fb71d01345f11b708a3553c66e7c74074f2d506400ea81973343d915cb64eef0 AS build
ENV NODE_ENV=production
RUN corepack enable && corepack prepare pnpm@11.6.0 --activate
WORKDIR /workspace
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
# hadolint ignore=DL3021
COPY app/<%= name %> ./app/<%= name %>
RUN pnpm install --frozen-lockfile --filter <%= name %>...
WORKDIR /workspace/app/<%= name %>
RUN pnpm run build

# Runtime — Next.js standalone output. The build stage emits a self-contained
# tree at .next/standalone (with hoisted pnpm deps included via
# outputFileTracingRoot in next.config.ts), plus .next/static and public/.
# No pnpm/corepack at runtime; entry is `node server.js`. Mirrors
# app/web-nextjs/Dockerfile; corepack-at-runtime tripped the per-user
# activation trap (PR #198).
FROM docker.io/node:24-alpine@sha256:fb71d01345f11b708a3553c66e7c74074f2d506400ea81973343d915cb64eef0 AS runtime
ENV NODE_ENV=production
WORKDIR /app
# Patch base-image system libs that lag the pinned digest (run as root before
# dropping to `node`). A real upgrade, not a Trivy waiver; mirrors
# app/web-nextjs/Dockerfile so scaffolded services don't reintroduce a
# fixable base-image CVE (e.g. libcrypto3/libssl3 CVE-2026-45447).
#
# Also strip the globally-installed npm + corepack: the runtime entry is
# `node server.js` and never shells out to a package manager, and npm bundles
# its own `undici` at /usr/local/lib/node_modules/npm/node_modules/undici (a
# base-image copy, NOT a project dependency — a pnpm override cannot reach it),
# which has carried HIGH CVEs (e.g. CVE-2026-12151). Removing npm eliminates
# that class at the source — attack-surface reduction, not a Trivy waiver.
RUN apk --no-cache upgrade && rm -rf /var/cache/apk/* \
    && rm -rf /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/corepack \
              /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack
# hadolint ignore=DL3021
COPY --from=build --chown=node:node /workspace/app/<%= name %>/.next/standalone /app
# hadolint ignore=DL3021
COPY --from=build --chown=node:node /workspace/app/<%= name %>/.next/static /app/app/<%= name %>/.next/static
# hadolint ignore=DL3021
COPY --from=build --chown=node:node /workspace/app/<%= name %>/public /app/app/<%= name %>/public
USER node
EXPOSE 3000
CMD ["node", "app/<%= name %>/server.js"]
