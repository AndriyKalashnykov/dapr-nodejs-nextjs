# syntax=docker/dockerfile:1@sha256:2780b5c3bab67f1f76c781860de469442999ed1a0d7992a5efdf2cffc0e3d769
FROM docker.io/node:24-alpine@sha256:01743339035a5c3c11a373cd7c83aeab6ed1457b55da6a69e014a95ac4e4700b

# Certicate
ENV CERT_HOME=/usr/local/share/ca-certificates
ENV CERT_FILE_PATH=${CERT_HOME}/zscaler_chain_root-int.pem
RUN mkdir -p ${CERT_HOME}
COPY zscaler_chain_root-int.pem ${CERT_FILE_PATH}

# npm settings
ARG ADD_CERT
RUN if [ "$ADD_CERT" = "true" ]; then npm config set cafile ${CERT_FILE_PATH}; else echo "No CA cert added."; fi
