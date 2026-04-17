# syntax=docker/dockerfile:1@sha256:2780b5c3bab67f1f76c781860de469442999ed1a0d7992a5efdf2cffc0e3d769
FROM docker.io/node:24-alpine@sha256:d1b3b4da11eefd5941e7f0b9cf17783fc99d9c6fc34884a665f40a06dbdfc94f

# Certicate
ENV CERT_HOME=/usr/local/share/ca-certificates
ENV CERT_FILE_PATH=${CERT_HOME}/zscaler_chain_root-int.pem
RUN mkdir -p ${CERT_HOME}
COPY zscaler_chain_root-int.pem ${CERT_FILE_PATH}

# Enable pnpm via corepack — single source of truth is root package.json's
# `packageManager` field, but corepack still needs an explicit prepare to
# avoid the first-use download prompt at runtime.
RUN corepack enable && corepack prepare pnpm@10.33.0 --activate

# Trust corporate CA cert when ADD_CERT=true.
ARG ADD_CERT
RUN if [ "$ADD_CERT" = "true" ]; then \
      npm config set cafile ${CERT_FILE_PATH} && \
      pnpm config set cafile ${CERT_FILE_PATH}; \
    else echo "No CA cert added."; fi
