# syntax=docker/dockerfile:1@sha256:87999aa3d42bdc6bea60565083ee17e86d1f3339802f543c0d03998580f9cb89
# Build context is the repo root.
FROM docker.io/node:24-alpine@sha256:fb71d01345f11b708a3553c66e7c74074f2d506400ea81973343d915cb64eef0 AS build
ENV NODE_ENV=production
RUN corepack enable && corepack prepare pnpm@11.7.0 --activate
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
FROM docker.io/node:24-alpine@sha256:fb71d01345f11b708a3553c66e7c74074f2d506400ea81973343d915cb64eef0 AS runtime
ENV NODE_ENV=production
WORKDIR /app
# Patch base-image system libs that lag the pinned digest. node:24-alpine
# ships libcrypto3/libssl3 3.5.6-r0 (CVE-2026-45447, HIGH); alpine v3.24/main
# publishes the fixed 3.5.7-r0. Run as root before dropping to `node`. This
# is a real upgrade (the CVE is gone from the image), not a Trivy waiver, and
# becomes a near no-op once the upstream digest rebases onto patched alpine.
#
# Also strip the globally-installed npm + corepack. The runtime entry is
# `node server.js` (Next.js standalone) and never shells out to a package
# manager, so both are dead weight — and npm bundles its own `undici` at
# /usr/local/lib/node_modules/npm/node_modules/undici (6.25.0 in this base),
# which carries CVE-2026-12151 (HIGH, unbounded-memory DoS; fixed in 6.27.0).
# That undici is part of the npm CLI, NOT a project dependency, so a pnpm
# override cannot reach it — removing npm eliminates the finding at the source
# (attack-surface reduction, not a Trivy waiver). Re-evaluate once the base
# image ships an npm whose bundled undici is >= 6.27.0.
RUN apk --no-cache upgrade && rm -rf /var/cache/apk/* \
    && rm -rf /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/corepack \
              /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack
COPY --from=build --chown=node:node /workspace/app/web-nextjs/.next/standalone /app
COPY --from=build --chown=node:node /workspace/app/web-nextjs/.next/static /app/app/web-nextjs/.next/static
COPY --from=build --chown=node:node /workspace/app/web-nextjs/public /app/app/web-nextjs/public
USER node
EXPOSE 3000
CMD ["node", "app/web-nextjs/server.js"]
