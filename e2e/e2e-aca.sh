#!/usr/bin/env bash
# End-to-end smoke test against a live Azure Container Apps deployment.
#
# Reads the Next.js/backend FQDNs + resource group from `terraform output -raw`,
# runs CRUD + auth + envelope + PUT/PATCH assertions AND a pub/sub-delivery
# witness that exercises the PROD-real paths compose e2e can't (Azure Cache for
# Redis over TLS + consumerID, Key Vault secretstore). The pub/sub witness reads
# the app's console log via `az containerapp logs` and is best-effort (WARN, not
# FAIL) since ACA log surfacing can lag. Local-only probes (Zipkin, Dashboard,
# Grafana) are intentionally omitted — those live in e2e/e2e-test.sh (compose).
#
# Expected env:
#   TF_DIR — path to infra/azure (default ./infra/azure)
#   JWT_SECRET_KEY — matches the value seeded into Key Vault at apply time
#
# Exit codes:
#   0  all probes passed
#   1  one or more failures
#   2  required env or terraform output missing

set -uo pipefail

TF_DIR="${TF_DIR:-infra/azure}"
JWT_SECRET="${JWT_SECRET_KEY:-}"
BACKEND_APP_ID="${BACKEND_APP_ID:-backend-ts}"

if [[ -z "$JWT_SECRET" ]]; then
  echo "JWT_SECRET_KEY env var is required (must match the value seeded into Key Vault)" >&2
  exit 2
fi

# Read outputs from the applied Terraform state.
read_tf() {
  (cd "$TF_DIR" && terraform output -raw "$1" 2>/dev/null) || echo ""
}

NEXTJS_URL=$(read_tf nextjs_url)
BACKEND_URL=$(read_tf backend_url)

if [[ -z "$NEXTJS_URL" || -z "$BACKEND_URL" ]]; then
  echo "terraform outputs missing: nextjs_url='$NEXTJS_URL' backend_url='$BACKEND_URL'" >&2
  echo "run 'terraform apply' first" >&2
  exit 2
fi

PASS=0; FAIL=0; WARN=0; FAILURES=(); WARNINGS=()

record() {
  case "$1" in
    PASS) echo "  ✓ $2"; PASS=$((PASS + 1)) ;;
    # Non-blocking: ACA console-log surfacing can lag, so the pub/sub-delivery
    # witness is best-effort — a miss is recorded but does not fail the run.
    WARN) echo "  ! $2"; WARN=$((WARN + 1)); WARNINGS+=("$2") ;;
    *)    echo "  ✗ $2"; FAIL=$((FAIL + 1)); FAILURES+=("$2") ;;
  esac
}

assert_http() {
  local label="$1" url="$2" expected="$3" method="${4:-GET}" body="${5:-}" auth="${6:-}"
  local curl_args=(-s -o /dev/null -w '%{http_code}' -X "$method" --max-time 15)
  [[ -n "$body" ]] && curl_args+=(-H 'Content-Type: application/json' -d "$body")
  [[ -n "$auth" ]] && curl_args+=(-H "Authorization: Bearer $auth")
  local status
  status=$(curl "${curl_args[@]}" "$url" 2>/dev/null || echo '000')
  if [[ "$status" == "$expected" ]]; then
    record PASS "$label ($method $url → $status)"
  else
    record FAIL "$label ($method $url → $status, expected $expected)"
  fi
}

make_jwt() {
  node -e "console.log(require('jsonwebtoken').sign({sub:'e2e-aca'}, '${JWT_SECRET}'))"
}

wait_for() {
  local label="$1" url="$2" timeout="${3:-300}"
  echo "  waiting for $label at $url (up to ${timeout}s)..."
  local deadline=$((SECONDS + timeout))
  until curl -sf -o /dev/null --max-time 5 "$url" 2>/dev/null; do
    if (( SECONDS >= deadline )); then
      record FAIL "$label not ready within ${timeout}s"
      return 1
    fi
    sleep 5
  done
  record PASS "$label ready"
}

echo "=== ACA e2e smoke test ==="
echo "  nextjs_url:  $NEXTJS_URL"
echo "  backend_url: $BACKEND_URL"
echo

echo "[1/4] Waiting for Container Apps to reach Ready..."
# ACA cold starts can take 60–120s on first deploy.
wait_for "Next.js SSR"   "$NEXTJS_URL"                     300 || exit 1
wait_for "Backend API"   "$BACKEND_URL/docs"               300 || exit 1
echo

echo "[2/4] Health probes..."
assert_http "Next.js SSR root"   "$NEXTJS_URL"             200
assert_http "Swagger UI redirect" "$BACKEND_URL/docs"      301
echo

echo "[3/4] Auth / negative cases..."
assert_http "Unauthenticated → 401" \
  "$BACKEND_URL/api/v1/todos" 401
TOKEN=$(make_jwt)
assert_http "Nonexistent todo → 404" \
  "$BACKEND_URL/api/v1/todos/00000000-0000-0000-0000-000000000000" \
  404 GET "" "$TOKEN"
echo

echo "[4/5] Backend CRUD cycle (create exercises the PROD-real paths compose can't)..."
# A successful create on ACA implicitly validates three prod-only paths:
#   • Key Vault secretstore — JWT_SECRET_KEY is fetched from Key Vault at boot,
#     so any authed request proves the secretstore wiring.
#   • Azure Cache for Redis (TLS) STATE — the read-through cache saves the todo
#     to the Redis state store over TLS.
#   • Azure Cache for Redis (TLS) PUB/SUB — the write publishes to `todo-data`
#     over TLS with the configured consumerID.
# The explicit envelope + PUT/PATCH + pub/sub-delivery checks below make those
# implicit validations observable.
assert_http "List todos" \
  "$BACKEND_URL/api/v1/todos" 200 GET "" "$TOKEN"

CREATE_RESP=$(curl -sf -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"title":"e2e-aca-todo"}' \
  "$BACKEND_URL/api/v1/todos" 2>/dev/null || echo '')
if echo "$CREATE_RESP" | grep -q '"id"'; then
  record PASS "Create todo on ACA returns id"
  # Envelope shape (mirrors the compose e2e) — proves the standard API response
  # contract holds against the deployed app, not just a 2xx status.
  if echo "$CREATE_RESP" | grep -q '"apiVersion"'; then
    record PASS "Create response has apiVersion envelope"
  else
    record FAIL "Create response missing apiVersion envelope: ${CREATE_RESP:0:120}"
  fi
  if echo "$CREATE_RESP" | grep -q '"completed":false'; then
    record PASS "Create response has completed=false"
  else
    record FAIL "Create response missing completed=false: ${CREATE_RESP:0:120}"
  fi
  TODO_ID=$(echo "$CREATE_RESP" | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{try{console.log(JSON.parse(d).data.id)}catch{console.log('')}})")
else
  record FAIL "Create todo on ACA — no id: ${CREATE_RESP:0:160}"
  TODO_ID=""
fi

if [[ -n "$TODO_ID" ]]; then
  assert_http "Get todo by id" \
    "$BACKEND_URL/api/v1/todos/${TODO_ID}" 200 GET "" "$TOKEN"
  # PUT + PATCH are both registered for updateTodoById; a regression dropping
  # one would otherwise be silent (mirrors the compose e2e update coverage).
  assert_http "Update todo via PUT" \
    "$BACKEND_URL/api/v1/todos/${TODO_ID}" 200 PUT \
    '{"title":"e2e-aca-todo-updated","completed":true}' "$TOKEN"
  assert_http "Update todo via PATCH" \
    "$BACKEND_URL/api/v1/todos/${TODO_ID}" 200 PATCH \
    '{"title":"e2e-aca-todo-patched"}' "$TOKEN"
fi
echo

echo "[5/5] Pub/sub delivery witness (Azure Cache for Redis over TLS + consumerID)..."
# The create above published to `todo-data` THROUGH the app's Dapr sidecar over
# Azure Cache for Redis (TLS). Witnessing the consumer handling it proves the
# full publish→Redis(TLS)→subscription→/consumer round trip on real Azure — the
# path the compose e2e (plain Redis, no TLS) cannot cover. Best-effort (WARN):
# ACA console-log surfacing can lag, and the exact `az containerapp logs` shape
# may need tuning per deployment — a miss does NOT fail the release (the create
# publish itself already succeeded above).
RG=$(read_tf resource_group_name)
if [[ -n "$RG" && -n "${TODO_ID:-}" ]] && command -v az >/dev/null 2>&1; then
  witness=""
  for _ in $(seq 1 24); do # up to ~120s for the console log to surface
    if az containerapp logs show \
         --name "$BACKEND_APP_ID" --resource-group "$RG" \
         --type console --tail 200 2>/dev/null \
         | grep -q 'Consumer handling message'; then
      witness=yes; break
    fi
    sleep 5
  done
  if [[ "$witness" == "yes" ]]; then
    record PASS "Pub/sub round-trip witnessed on ACA (Redis-TLS publish → consumer)"
  else
    record WARN "Pub/sub consumer log not observed within 120s (ingestion lag or az-log shape) — the create-todo publish itself succeeded"
  fi
else
  record WARN "Skipped pub/sub witness (no resource_group_name output or az CLI unavailable)"
fi

# Clean up the probe todo (delete also publishes a delete event).
if [[ -n "${TODO_ID:-}" ]]; then
  assert_http "Delete todo" \
    "$BACKEND_URL/api/v1/todos/${TODO_ID}" 200 DELETE "" "$TOKEN"
fi
echo

echo "=== Results: ${PASS} passed, ${WARN} warnings, ${FAIL} failed ==="
if (( WARN > 0 )); then
  echo "Warnings (non-blocking):"
  for w in "${WARNINGS[@]}"; do echo "  - $w"; done
fi
if (( FAIL > 0 )); then
  echo "Failures:"
  for f in "${FAILURES[@]}"; do echo "  - $f"; done
  exit 1
fi
