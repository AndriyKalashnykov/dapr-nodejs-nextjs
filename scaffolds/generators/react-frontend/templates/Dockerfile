# syntax=docker/dockerfile:1@sha256:87999aa3d42bdc6bea60565083ee17e86d1f3339802f543c0d03998580f9cb89
# Build context is the repo root.
FROM docker.io/node:24-alpine@sha256:2bdb65ed1dab192432bc31c95f94155ca5ad7fc1392fb7eb7526ab682fa5bf14 AS build
ENV NODE_ENV=production
RUN corepack enable && corepack prepare pnpm@11.5.1 --activate
WORKDIR /workspace
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
# hadolint ignore=DL3021
COPY app/<%= name %> ./app/<%= name %>
RUN pnpm install --frozen-lockfile --filter <%= name %>...
WORKDIR /workspace/app/<%= name %>
RUN pnpm run build

# Runtime — invoke vite preview's binary directly. No pnpm/corepack at
# runtime (the previous `CMD ["pnpm","run","preview"]` form tripped the
# corepack per-user activation trap — see PR #198). `vite preview` is the
# scaffold default for a quick local prod-mode boot; replace with a
# proper static server (nginx, caddy, serve) for production deployments.
FROM docker.io/node:24-alpine@sha256:2bdb65ed1dab192432bc31c95f94155ca5ad7fc1392fb7eb7526ab682fa5bf14 AS runtime
ENV NODE_ENV=production
WORKDIR /app
# hadolint ignore=DL3021
COPY --from=build --chown=node:node /workspace/app/<%= name %> /app
USER node
EXPOSE 3001
CMD ["./node_modules/.bin/vite", "preview", "--host", "0.0.0.0", "--port", "3001"]
