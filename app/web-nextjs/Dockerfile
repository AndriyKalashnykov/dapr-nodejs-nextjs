# syntax=docker/dockerfile:1@sha256:87999aa3d42bdc6bea60565083ee17e86d1f3339802f543c0d03998580f9cb89
# Build context is the repo root.
FROM docker.io/node:24-alpine@sha256:a0b9bf06e4e6193cf7a0f58816cc935ff8c2a908f81e6f1a95432d679c54fbfd AS build
ENV NODE_ENV=production
RUN corepack enable && corepack prepare pnpm@11.15.0 --activate
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
FROM docker.io/node:24-alpine@sha256:a0b9bf06e4e6193cf7a0f58816cc935ff8c2a908f81e6f1a95432d679c54fbfd AS runtime
ENV NODE_ENV=production
# Operator-tunable runtime knobs (externalized per configuration rules).
# HEALTHCHECK_HOST is 127.0.0.1 (not localhost) to dodge alpine's IPv6-first
# `[::1]` resolution against an IPv4-bound server.
ARG APP_INTERNAL_PORT=3000
ARG HEALTHCHECK_HOST=127.0.0.1
ENV APP_INTERNAL_PORT=${APP_INTERNAL_PORT} \
    HEALTHCHECK_HOST=${HEALTHCHECK_HOST}
# Next.js standalone reads $HOSTNAME as its bind address; unset it resolves to
# the container hostname (binds eth0 only, not loopback) so the HEALTHCHECK's
# 127.0.0.1 probe is refused. Bind 0.0.0.0 (all interfaces) — the documented
# Next-standalone-in-Docker setting; compose service DNS still reaches it.
ENV HOSTNAME=0.0.0.0
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
# Cache-bust so the apk upgrade re-executes even when the layer is gha-cached
# (CI passes APK_UPGRADE_DATE=${{ github.run_id }} for per-run freshness; the
# Makefile passes a daily date). A changed in-scope ARG busts the FOLLOWING RUN.
ARG APK_UPGRADE_DATE=manual
RUN apk --no-cache upgrade && rm -rf /var/cache/apk/* \
    && rm -rf /usr/local/lib/node_modules/npm /usr/local/lib/node_modules/corepack \
              /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/corepack
COPY --from=build --chown=node:node /workspace/app/web-nextjs/.next/standalone /app
COPY --from=build --chown=node:node /workspace/app/web-nextjs/.next/static /app/app/web-nextjs/.next/static
COPY --from=build --chown=node:node /workspace/app/web-nextjs/public /app/app/web-nextjs/public
USER node
EXPOSE ${APP_INTERNAL_PORT}
# TCP-connect liveness probe via node's net. Flag durations are literal —
# HEALTHCHECK flags are parsed at build time and do NOT expand ARG/ENV.
HEALTHCHECK --interval=30s --timeout=3s --start-period=20s --retries=3 \
    CMD node -e "require('net').connect(Number(process.env.APP_INTERNAL_PORT||3000),process.env.HEALTHCHECK_HOST||'127.0.0.1').on('connect',function(){process.exit(0)}).on('error',function(){process.exit(1)})"
CMD ["node", "app/web-nextjs/server.js"]
