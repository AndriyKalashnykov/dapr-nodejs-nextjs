# syntax=docker/dockerfile:1@sha256:2780b5c3bab67f1f76c781860de469442999ed1a0d7992a5efdf2cffc0e3d769
# Build context is the repo root.
FROM docker.io/node:24-alpine@sha256:01743339035a5c3c11a373cd7c83aeab6ed1457b55da6a69e014a95ac4e4700b AS build
ENV NODE_ENV=production
RUN corepack enable && corepack prepare pnpm@10.33.0 --activate
WORKDIR /workspace
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
# hadolint ignore=DL3021
COPY app/<%= name %> ./app/<%= name %>
RUN pnpm install --frozen-lockfile --filter <%= name %>...
WORKDIR /workspace/app/<%= name %>
RUN pnpm run build

# Runtime
FROM docker.io/node:24-alpine@sha256:01743339035a5c3c11a373cd7c83aeab6ed1457b55da6a69e014a95ac4e4700b AS runtime
RUN corepack enable && corepack prepare pnpm@10.33.0 --activate
ENV NODE_ENV=production
WORKDIR /app
# hadolint ignore=DL3021
COPY --from=build /workspace/app/<%= name %> /app
EXPOSE 3001
CMD [ "pnpm", "run", "preview" ]
