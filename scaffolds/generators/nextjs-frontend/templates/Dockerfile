# syntax=docker/dockerfile:1@sha256:2780b5c3bab67f1f76c781860de469442999ed1a0d7992a5efdf2cffc0e3d769
# Build context is the repo root.
FROM docker.io/node:24-alpine@sha256:d1b3b4da11eefd5941e7f0b9cf17783fc99d9c6fc34884a665f40a06dbdfc94f AS build
ENV NODE_ENV=production
RUN corepack enable && corepack prepare pnpm@10.33.4 --activate
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
FROM docker.io/node:24-alpine@sha256:d1b3b4da11eefd5941e7f0b9cf17783fc99d9c6fc34884a665f40a06dbdfc94f AS runtime
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
