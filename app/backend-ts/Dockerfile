# syntax=docker/dockerfile:1@sha256:2780b5c3bab67f1f76c781860de469442999ed1a0d7992a5efdf2cffc0e3d769
# Build context is the repo root (see Makefile e2e-aca target).
FROM docker.io/node:24-alpine@sha256:d1b3b4da11eefd5941e7f0b9cf17783fc99d9c6fc34884a665f40a06dbdfc94f AS build
ENV NODE_ENV=production
RUN corepack enable && corepack prepare pnpm@10.33.0 --activate
WORKDIR /workspace
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc tsconfig.json ./
COPY packages ./packages
COPY app/backend-ts ./app/backend-ts
RUN pnpm install --frozen-lockfile --filter backend-ts...
RUN pnpm --filter @sos/sdk run compile && \
    pnpm --filter backend-ts run compile && \
    pnpm deploy --legacy --filter backend-ts --prod /deploy

# Runtime
FROM docker.io/node:24-alpine@sha256:d1b3b4da11eefd5941e7f0b9cf17783fc99d9c6fc34884a665f40a06dbdfc94f AS runtime
RUN corepack enable && corepack prepare pnpm@10.33.0 --activate
ENV NODE_ENV=production
WORKDIR /app
# `node:*-alpine` ships with a non-root `node` user (UID 1000). Copy the
# deploy artifact owned by that user, then drop privileges before CMD.
COPY --from=build --chown=node:node /deploy ./
USER node
EXPOSE 3001
CMD [ "pnpm", "run", "start" ]
