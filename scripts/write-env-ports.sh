#!/usr/bin/env bash
# Allocate free ports for every service and write them to an env file.
#
# Usage:
#   scripts/write-env-ports.sh                # writes .env.ports
#   scripts/write-env-ports.sh >> $GITHUB_ENV # exports to a GitHub Actions job
#
# Use this when running tests in parallel (multiple compose projects on one
# host, multiple local test runs, or side-by-side integration harnesses) to
# avoid port collisions on fixed defaults.
#
# Note: allocation happens in-process; there's a small TOCTOU window between
# picking a port and binding it. Acceptable for CI; not for high-churn loops.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PICK="${SCRIPT_DIR}/pick-port.sh"

# Each entry: VAR_NAME[:default]. Default is informational; picker always
# returns an ephemeral free port regardless of the default.
VARS=(
  SERVER_PORT
  DAPR_PORT
  DB_PORT
  NEXTJS_PORT
  ZIPKIN_PORT
  OTLP_PORT
  DAPR_DASHBOARD_PORT
  PLACEMENT_PORT
  SCHEDULER_PORT
  REDIS_PORT
  GRAFANA_OTEL_PORT
)

out="${1:-.env.ports}"
if [[ "$out" == "-" || "$out" == "/dev/stdout" ]]; then
  out=/dev/stdout
fi

{
  for v in "${VARS[@]}"; do
    echo "${v}=$("$PICK")"
  done
} > "$out"

if [[ "$out" != /dev/stdout && "$out" != /dev/stderr ]]; then
  echo "wrote $(wc -l < "$out") ports to $out" >&2
fi
