# syntax=docker/dockerfile:1@sha256:87999aa3d42bdc6bea60565083ee17e86d1f3339802f543c0d03998580f9cb89
# Build context is the repo root.
FROM docker.io/node:24-alpine@sha256:2bdb65ed1dab192432bc31c95f94155ca5ad7fc1392fb7eb7526ab682fa5bf14 AS build
ENV NODE_ENV=production
RUN corepack enable && corepack prepare pnpm@11.5.1 --activate
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
FROM docker.io/node:24-alpine@sha256:2bdb65ed1dab192432bc31c95f94155ca5ad7fc1392fb7eb7526ab682fa5bf14 AS runtime
ENV NODE_ENV=production
WORKDIR /app
COPY --from=build --chown=node:node /deploy ./
USER node
EXPOSE 3001
CMD ["./node_modules/.bin/tsx", "--import", "./src/lib/instrumentation.ts", "src/main.ts"]
