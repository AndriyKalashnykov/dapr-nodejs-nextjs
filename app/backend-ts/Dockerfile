# syntax=docker/dockerfile:1@sha256:2780b5c3bab67f1f76c781860de469442999ed1a0d7992a5efdf2cffc0e3d769
# Build context is the repo root (see Makefile e2e-aca target).
FROM docker.io/node:24-alpine@sha256:d1b3b4da11eefd5941e7f0b9cf17783fc99d9c6fc34884a665f40a06dbdfc94f AS build
ENV NODE_ENV=production
RUN corepack enable && corepack prepare pnpm@11.0.9 --activate
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
# activation cache (the build-stage `corepack prepare pnpm@11.0.9 --activate`
# runs as root and is per-user). At container start, corepack as `node`
# fell back to the base image's default pnpm (11.0.9), downloaded it, and
# pnpm 11's `depsStatusCheck` then tried to write a tmp file to /app which
# is owned root:root → EACCES → exit 243 → smoke-test failure on every PR.
# Mirrors the web-nextjs runtime (also pnpm-free).
FROM docker.io/node:24-alpine@sha256:d1b3b4da11eefd5941e7f0b9cf17783fc99d9c6fc34884a665f40a06dbdfc94f AS runtime
ENV NODE_ENV=production
WORKDIR /app
# `node:*-alpine` ships with a non-root `node` user (UID 1000). Copy the
# deploy artifact owned by that user, then drop privileges before CMD.
COPY --from=build --chown=node:node /deploy ./
USER node
EXPOSE 3001
CMD ["./node_modules/.bin/tsx", "--import", "./src/lib/instrumentation.ts", "src/main.ts"]
