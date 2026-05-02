# syntax=docker/dockerfile:1@sha256:2780b5c3bab67f1f76c781860de469442999ed1a0d7992a5efdf2cffc0e3d769
# Build context is the repo root.
FROM docker.io/node:24-alpine@sha256:d1b3b4da11eefd5941e7f0b9cf17783fc99d9c6fc34884a665f40a06dbdfc94f AS build
ENV NODE_ENV=production
RUN corepack enable && corepack prepare pnpm@10.33.2 --activate
WORKDIR /workspace
COPY package.json pnpm-lock.yaml pnpm-workspace.yaml .npmrc ./
COPY app/web-nextjs ./app/web-nextjs
RUN pnpm install --frozen-lockfile --filter web-nextjs...
WORKDIR /workspace/app/web-nextjs
# Next.js validates the JWT signing key at module init for /api/auth, so the
# `pnpm run build` page-data collection fails without one. The runtime value
# comes from Key Vault (ACA) or .env (local); a placeholder is sufficient
# for the build itself.
ARG JWT_SECRET_KEY=build-time-placeholder
ENV JWT_SECRET_KEY=$JWT_SECRET_KEY
RUN pnpm run build

# Runtime — Next.js standalone output. The build stage emits a self-contained
# tree at .next/standalone (with hoisted pnpm deps included via
# outputFileTracingRoot in next.config.ts), plus .next/static and public/.
# No pnpm/corepack at runtime; entry is `node server.js`.
FROM docker.io/node:24-alpine@sha256:d1b3b4da11eefd5941e7f0b9cf17783fc99d9c6fc34884a665f40a06dbdfc94f AS runtime
ENV NODE_ENV=production
WORKDIR /app
COPY --from=build --chown=node:node /workspace/app/web-nextjs/.next/standalone /app
COPY --from=build --chown=node:node /workspace/app/web-nextjs/.next/static /app/app/web-nextjs/.next/static
COPY --from=build --chown=node:node /workspace/app/web-nextjs/public /app/app/web-nextjs/public
USER node
EXPOSE 3000
CMD ["node", "app/web-nextjs/server.js"]
