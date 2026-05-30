# syntax=docker/dockerfile:1@sha256:87999aa3d42bdc6bea60565083ee17e86d1f3339802f543c0d03998580f9cb89
# Build context is the repo root.
FROM docker.io/node:24-alpine@sha256:2bdb65ed1dab192432bc31c95f94155ca5ad7fc1392fb7eb7526ab682fa5bf14 AS build
ENV NODE_ENV=production
RUN corepack enable && corepack prepare pnpm@11.4.0 --activate
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
FROM docker.io/node:24-alpine@sha256:2bdb65ed1dab192432bc31c95f94155ca5ad7fc1392fb7eb7526ab682fa5bf14 AS runtime
ENV NODE_ENV=production
WORKDIR /app
# hadolint ignore=DL3021
COPY --from=build --chown=node:node /workspace/app/<%= name %>/.next/standalone /app
# hadolint ignore=DL3021
COPY --from=build --chown=node:node /workspace/app/<%= name %>/.next/static /app/app/<%= name %>/.next/static
# hadolint ignore=DL3021
COPY --from=build --chown=node:node /workspace/app/<%= name %>/public /app/app/<%= name %>/public
USER node
EXPOSE 3000
CMD ["node", "app/<%= name %>/server.js"]
