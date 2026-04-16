#!/usr/bin/env bash
# End-to-end smoke test against the running compose stack.
#
# Assumes `make up -d` (or `docker compose up -d`) has been run and services
# are listening on their documented ports. Use `make e2e` to orchestrate.
#
# Ports come from env (see .env.example) with documented defaults.

set -uo pipefail

NEXTJS_PORT="${NEXTJS_PORT:-3000}"
BACKEND_PORT="${SERVER_PORT:-3001}"
DAPR_PORT="${DAPR_PORT:-3500}"
DASHBOARD_PORT="${DAPR_DASHBOARD_PORT:-8888}"
ZIPKIN_PORT="${ZIPKIN_PORT:-9411}"
OTEL_PORT="${GRAFANA_OTEL_PORT:-3200}"
SCHEDULER_PORT="${SCHEDULER_PORT:-50006}"
BACKEND_APP_ID="${BACKEND_APP_ID:-backend-ts}"
JWT_SECRET="${JWT_SECRET_KEY:-secret}"

PASS=0
FAIL=0
FAILURES=()

record() {
  if [[ "$1" == "PASS" ]]; then
    echo "  ✓ $2"
    PASS=$((PASS + 1))
  else
    echo "  ✗ $2"
    FAIL=$((FAIL + 1))
    FAILURES+=("$2")
  fi
}

assert_http() {
  local label="$1" url="$2" expected="$3" method="${4:-GET}" body="${5:-}" auth="${6:-}"
  local curl_args=(-s -o /dev/null -w '%{http_code}' -X "$method" --max-time 10)
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

assert_json_field() {
  local label="$1" url="$2" field="$3" auth="${4:-}"
  local curl_args=(-sf --max-time 10)
  [[ -n "$auth" ]] && curl_args+=(-H "Authorization: Bearer $auth")
  local body
  body=$(curl "${curl_args[@]}" "$url" 2>/dev/null || echo '')
  if echo "$body" | grep -q "\"$field\""; then
    record PASS "$label (field '$field' present)"
  else
    record FAIL "$label (field '$field' missing in response: ${body:0:120})"
  fi
}

make_jwt() {
  node -e "console.log(require('jsonwebtoken').sign({sub:'e2e-user'}, '${JWT_SECRET}'))"
}

wait_for() {
  local label="$1" url="$2" timeout="${3:-60}"
  echo "  waiting for $label at $url (up to ${timeout}s)..."
  local deadline=$((SECONDS + timeout))
  until curl -sf -o /dev/null --max-time 2 "$url" 2>/dev/null; do
    if (( SECONDS >= deadline )); then
      record FAIL "$label did not become ready within ${timeout}s"
      return 1
    fi
    sleep 2
  done
  record PASS "$label ready"
}

echo "=== E2E smoke test ==="
echo

echo "[1/6] Waiting for services..."
wait_for "Backend direct"        "http://localhost:${BACKEND_PORT}/docs" 90 || exit 1
wait_for "Backend via Dapr"      "http://localhost:${DAPR_PORT}/v1.0/healthz" 90 || exit 1
wait_for "Next.js SSR frontend"  "http://localhost:${NEXTJS_PORT}" 90 || exit 1
wait_for "Grafana OTEL"          "http://localhost:${OTEL_PORT}"   120 || exit 1
echo

echo "[2/6] Service health probes..."
assert_http "Next.js SSR root"   "http://localhost:${NEXTJS_PORT}"         200
assert_http "Swagger UI redirect" "http://localhost:${BACKEND_PORT}/docs"  301
assert_http "Dapr Dashboard"     "http://localhost:${DASHBOARD_PORT}"      200
assert_http "Zipkin"             "http://localhost:${ZIPKIN_PORT}"         302
assert_http "Grafana OTEL"       "http://localhost:${OTEL_PORT}"           200
echo

echo "[3/6] Dapr scheduler reachability..."
if nc -z -w 3 localhost "${SCHEDULER_PORT}" 2>/dev/null; then
  record PASS "Scheduler TCP ${SCHEDULER_PORT} reachable"
else
  record FAIL "Scheduler TCP ${SCHEDULER_PORT} NOT reachable"
fi
echo

echo "[4/6] Auth / negative cases..."
assert_http "Unauthenticated todos → 401" \
  "http://localhost:${BACKEND_PORT}/api/v1/todos" 401
assert_http "Nonexistent todo → 404" \
  "http://localhost:${BACKEND_PORT}/api/v1/todos/00000000-0000-0000-0000-000000000000" \
  404 GET "" "$(make_jwt)"
echo

echo "[5/6] Backend CRUD (direct)..."
TOKEN=$(make_jwt)
assert_http "List todos (empty state ok)" \
  "http://localhost:${BACKEND_PORT}/api/v1/todos" 200 GET "" "$TOKEN"

CREATE_RESP=$(curl -sf -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"title":"e2e-test-todo"}' \
  "http://localhost:${BACKEND_PORT}/api/v1/todos" 2>/dev/null || echo '')
if echo "$CREATE_RESP" | grep -q '"id"'; then
  record PASS "Create todo (direct) returns id"
  TODO_ID=$(echo "$CREATE_RESP" | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{try{console.log(JSON.parse(d).data.id)}catch{console.log('')}})")
else
  record FAIL "Create todo (direct) — no id in response: ${CREATE_RESP:0:120}"
  TODO_ID=""
fi

if [[ -n "$TODO_ID" ]]; then
  assert_http "Get todo by id (direct)" \
    "http://localhost:${BACKEND_PORT}/api/v1/todos/${TODO_ID}" 200 GET "" "$TOKEN"
  assert_http "Delete todo (direct)" \
    "http://localhost:${BACKEND_PORT}/api/v1/todos/${TODO_ID}" 200 DELETE "" "$TOKEN"
fi
echo

echo "[6/6] Backend CRUD via Dapr sidecar..."
DAPR_BASE="http://localhost:${DAPR_PORT}/v1.0/invoke/${BACKEND_APP_ID}/method"
assert_json_field "List todos via sidecar has items field" \
  "${DAPR_BASE}/api/v1/todos" "items" "$TOKEN"

CREATE_VIA_DAPR=$(curl -sf -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"title":"e2e-via-dapr"}' \
  "${DAPR_BASE}/api/v1/todos" 2>/dev/null || echo '')
if echo "$CREATE_VIA_DAPR" | grep -q '"id"'; then
  record PASS "Create todo via Dapr sidecar"
  DAPR_TODO_ID=$(echo "$CREATE_VIA_DAPR" | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{try{console.log(JSON.parse(d).data.id)}catch{console.log('')}})")
  if [[ -n "$DAPR_TODO_ID" ]]; then
    assert_http "Delete via Dapr sidecar" \
      "${DAPR_BASE}/api/v1/todos/${DAPR_TODO_ID}" 200 DELETE "" "$TOKEN"
  fi
else
  record FAIL "Create via Dapr sidecar — no id: ${CREATE_VIA_DAPR:0:120}"
fi
echo

echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if (( FAIL > 0 )); then
  echo "Failures:"
  for f in "${FAILURES[@]}"; do echo "  - $f"; done
  exit 1
fi
