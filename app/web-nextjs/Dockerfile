# syntax=docker/dockerfile:1@sha256:87999aa3d42bdc6bea60565083ee17e86d1f3339802f543c0d03998580f9cb89
# Build context is the repo root.
FROM docker.io/node:24-alpine@sha256:2bdb65ed1dab192432bc31c95f94155ca5ad7fc1392fb7eb7526ab682fa5bf14 AS build
ENV NODE_ENV=production
RUN corepack enable && corepack prepare pnpm@11.5.2 --activate
WORKDIR /workspace
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY app/web-nextjs ./app/web-nextjs
RUN pnpm install --frozen-lockfile --filter web-nextjs...
WORKDIR /workspace/app/web-nextjs
RUN pnpm run build

# Runtime — Next.js standalone output. The build stage emits a self-contained
# tree at .next/standalone (with hoisted pnpm deps included via
# outputFileTracingRoot in next.config.ts), plus .next/static and public/.
# No pnpm/corepack at runtime; entry is `node server.js`.
FROM docker.io/node:24-alpine@sha256:2bdb65ed1dab192432bc31c95f94155ca5ad7fc1392fb7eb7526ab682fa5bf14 AS runtime
ENV NODE_ENV=production
WORKDIR /app
# Patch base-image system libs that lag the pinned digest. node:24-alpine
# ships libcrypto3/libssl3 3.5.6-r0 (CVE-2026-45447, HIGH); alpine v3.24/main
# publishes the fixed 3.5.7-r0. Run as root before dropping to `node`. This
# is a real upgrade (the CVE is gone from the image), not a Trivy waiver, and
# becomes a near no-op once the upstream digest rebases onto patched alpine.
RUN apk --no-cache upgrade && rm -rf /var/cache/apk/*
COPY --from=build --chown=node:node /workspace/app/web-nextjs/.next/standalone /app
COPY --from=build --chown=node:node /workspace/app/web-nextjs/.next/static /app/app/web-nextjs/.next/static
COPY --from=build --chown=node:node /workspace/app/web-nextjs/public /app/app/web-nextjs/public
USER node
EXPOSE 3000
CMD ["node", "app/web-nextjs/server.js"]
