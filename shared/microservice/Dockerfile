# syntax=docker/dockerfile:1@sha256:87999aa3d42bdc6bea60565083ee17e86d1f3339802f543c0d03998580f9cb89
FROM docker.io/node:24-alpine@sha256:2bdb65ed1dab192432bc31c95f94155ca5ad7fc1392fb7eb7526ab682fa5bf14

# Certicate
ENV CERT_HOME=/usr/local/share/ca-certificates
ENV CERT_FILE_PATH=${CERT_HOME}/zscaler_chain_root-int.pem
RUN mkdir -p ${CERT_HOME}
COPY zscaler_chain_root-int.pem ${CERT_FILE_PATH}

# Enable pnpm via corepack — single source of truth is root package.json's
# `packageManager` field, but corepack still needs an explicit prepare to
# avoid the first-use download prompt at runtime.
RUN corepack enable && corepack prepare pnpm@11.1.3 --activate

# Trust corporate CA cert when ADD_CERT=true.
ARG ADD_CERT
RUN if [ "$ADD_CERT" = "true" ]; then \
      npm config set cafile ${CERT_FILE_PATH} && \
      pnpm config set cafile ${CERT_FILE_PATH}; \
    else echo "No CA cert added."; fi

# NOTE: this image is a *build-only* base for the monorepo — child
# Dockerfiles inherit it (`microservice-sdk-build`, `microservice-build`)
# and need root to install workspace packages. Each downstream runtime
# Dockerfile drops to `USER node` before its CMD. The DS-0002 trivy
# misconfig (no USER) is therefore suppressed in `.trivyignore` with
# scoping rationale.
