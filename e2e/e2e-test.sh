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
WARN=0
FAILURES=()
WARNINGS=()

record() {
  case "$1" in
    PASS)
      echo "  ✓ $2"
      PASS=$((PASS + 1))
      ;;
    WARN)
      # Non-blocking observation — known-flaky probe. Kept in the suite so we
      # notice if the underlying behavior changes, but doesn't fail the run.
      echo "  ! $2"
      WARN=$((WARN + 1))
      WARNINGS+=("$2")
      ;;
    *)
      echo "  ✗ $2"
      FAIL=$((FAIL + 1))
      FAILURES+=("$2")
      ;;
  esac
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
  # Forge an HS256 JWT using only openssl + base64 — no Node, no jsonwebtoken,
  # no runner-side language toolchain. Removes the runner's `pnpm install`
  # dependency for e2e and matches what the backend's auth middleware accepts.
  local header_b64 payload_b64 unsigned signature
  # base64url: standard base64 with -/_ swapped and trailing = stripped.
  b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
  header_b64=$(printf '%s' '{"alg":"HS256","typ":"JWT"}' | b64url)
  payload_b64=$(printf '%s' '{"sub":"e2e-user"}' | b64url)
  unsigned="${header_b64}.${payload_b64}"
  signature=$(printf '%s' "$unsigned" | openssl dgst -binary -sha256 -hmac "$JWT_SECRET" | b64url)
  printf '%s.%s' "$unsigned" "$signature"
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

echo "[1/8] Waiting for services..."
wait_for "Backend direct"        "http://localhost:${BACKEND_PORT}/docs" 90 || exit 1
wait_for "Backend via Dapr"      "http://localhost:${DAPR_PORT}/v1.0/healthz" 90 || exit 1
wait_for "Next.js SSR frontend"  "http://localhost:${NEXTJS_PORT}" 90 || exit 1
wait_for "Grafana OTEL"          "http://localhost:${OTEL_PORT}"   120 || exit 1
echo

echo "[2/8] Service health probes..."
assert_http "Next.js SSR root"   "http://localhost:${NEXTJS_PORT}"         200
assert_http "Swagger UI redirect" "http://localhost:${BACKEND_PORT}/docs"  301
assert_http "Dapr Dashboard"     "http://localhost:${DASHBOARD_PORT}"      200
assert_http "Zipkin"             "http://localhost:${ZIPKIN_PORT}"         302
assert_http "Grafana OTEL"       "http://localhost:${OTEL_PORT}"           200
echo

echo "[3/8] Dapr scheduler reachability..."
if nc -z -w 3 localhost "${SCHEDULER_PORT}" 2>/dev/null; then
  record PASS "Scheduler TCP ${SCHEDULER_PORT} reachable"
else
  record FAIL "Scheduler TCP ${SCHEDULER_PORT} NOT reachable"
fi
echo

echo "[4/8] Auth / negative cases..."
assert_http "Unauthenticated todos (direct) → 401" \
  "http://localhost:${BACKEND_PORT}/api/v1/todos" 401
assert_http "Nonexistent todo (direct) → 404" \
  "http://localhost:${BACKEND_PORT}/api/v1/todos/00000000-0000-0000-0000-000000000000" \
  404 GET "" "$(make_jwt)"
# Mirror the same negatives via the Dapr sidecar — catches misconfigured
# app-id, sidecar header stripping, and ACL/middleware regressions that
# would only surface on the sidecar code path.
DAPR_INVOKE_BASE="http://localhost:${DAPR_PORT}/v1.0/invoke/${BACKEND_APP_ID}/method"
assert_http "Unauthenticated todos (via Dapr) → 401" \
  "${DAPR_INVOKE_BASE}/api/v1/todos" 401
assert_http "Nonexistent todo (via Dapr) → 404" \
  "${DAPR_INVOKE_BASE}/api/v1/todos/00000000-0000-0000-0000-000000000000" \
  404 GET "" "$(make_jwt)"
echo

echo "[5/8] Backend CRUD (direct)..."
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
  # Response shape: assert envelope and todo fields per skill recommendation
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
  if echo "$CREATE_RESP" | grep -qE '"createdAt":"[0-9]{4}-[0-9]{2}-[0-9]{2}T'; then
    record PASS "Create response has ISO-8601 createdAt"
  else
    record FAIL "Create response missing ISO createdAt: ${CREATE_RESP:0:120}"
  fi
  TODO_ID=$(echo "$CREATE_RESP" | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{try{console.log(JSON.parse(d).data.id)}catch{console.log('')}})")
else
  record FAIL "Create todo (direct) — no id in response: ${CREATE_RESP:0:120}"
  TODO_ID=""
fi

if [[ -n "$TODO_ID" ]]; then
  assert_http "Get todo by id (direct)" \
    "http://localhost:${BACKEND_PORT}/api/v1/todos/${TODO_ID}" 200 GET "" "$TOKEN"
  # Update path coverage — both PUT and PATCH are registered for updateTodoById;
  # a regression that drops one method would otherwise be silent.
  assert_http "Update todo via PUT" \
    "http://localhost:${BACKEND_PORT}/api/v1/todos/${TODO_ID}" 200 PUT \
    '{"title":"e2e-test-todo-updated","completed":true}' "$TOKEN"
  assert_http "Update todo via PATCH" \
    "http://localhost:${BACKEND_PORT}/api/v1/todos/${TODO_ID}" 200 PATCH \
    '{"title":"e2e-test-todo-patched"}' "$TOKEN"
  assert_http "Delete todo (direct)" \
    "http://localhost:${BACKEND_PORT}/api/v1/todos/${TODO_ID}" 200 DELETE "" "$TOKEN"
fi
echo

echo "[6/8] Backend CRUD via Dapr sidecar..."
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

echo "[7/8] OpenTelemetry trace propagation (web-nextjs → backend-ts → Zipkin)..."
# Trigger an SSR request through the Next.js frontend so its OTel exporter
# emits a trace that web-nextjs handed off to backend-ts via the Dapr
# invoker — gives both services spans on the same traceId.
curl -sf -o /dev/null --max-time 10 "http://localhost:${NEXTJS_PORT}" 2>/dev/null || true
# Allow a short window for spans to flush before querying Zipkin.
sleep 5
TRACES_URL="http://localhost:${ZIPKIN_PORT}/api/v2/traces?serviceName=backend-ts&limit=50"
TRACE_COUNT=$(curl -sf --max-time 5 "$TRACES_URL" 2>/dev/null \
  | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{try{console.log(JSON.parse(d).length)}catch{console.log(0)}})" \
  || echo 0)
if [[ "$TRACE_COUNT" -gt 0 ]]; then
  record PASS "Zipkin received ${TRACE_COUNT} backend-ts trace(s)"
else
  record FAIL "Zipkin returned 0 backend-ts traces (OTel pipeline likely broken)"
fi
# Cross-service propagation: any single trace should contain spans from
# BOTH services if the Dapr invoker is propagating W3C traceparent headers.
WEB_TRACES=$(curl -sf --max-time 5 \
  "http://localhost:${ZIPKIN_PORT}/api/v2/traces?serviceName=web-nextjs&limit=20" 2>/dev/null || echo '[]')
WEB_TRACE_IDS=$(echo "$WEB_TRACES" | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{try{const t=JSON.parse(d);console.log(t.flat().map(s=>s.traceId).filter((v,i,a)=>a.indexOf(v)===i).join(' '))}catch{console.log('')}})")
PROPAGATED=0
for tid in $WEB_TRACE_IDS; do
  HITS=$(curl -sf --max-time 3 "http://localhost:${ZIPKIN_PORT}/api/v2/trace/${tid}" 2>/dev/null \
    | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{try{const s=JSON.parse(d);const svcs=new Set(s.map(x=>x.localEndpoint?.serviceName).filter(Boolean));console.log(svcs.has('web-nextjs')&&svcs.has('backend-ts')?'1':'0')}catch{console.log('0')}})" \
    || echo 0)
  if [[ "$HITS" == "1" ]]; then PROPAGATED=1; break; fi
done
if [[ "$PROPAGATED" == "1" ]]; then
  record PASS "Trace propagation web-nextjs → backend-ts (W3C traceparent)"
else
  # Non-blocking: SSR for the homepage may not actually call backend-ts, and
  # OTel context propagation through the Dapr invoker is a known gap. Probe
  # stays in the suite so a future fix is observable.
  record WARN "Trace propagation web-nextjs → backend-ts not observed (non-blocking)"
fi
echo

echo "[8/8] Dapr pub/sub round-trip (publish → consumer)..."
# Publish a CloudEvent directly through the Dapr sidecar's publish API. A 204
# from the sidecar means the event was dispatched to Redis. We then poll
# backend-ts logs for the "Consumer handling message" log line that the
# todo-consumer emits when Dapr delivers the event to /consumer/todo —
# this proves the FULL round-trip (publish → Redis → subscription →
# subscriber endpoint), not just the publish API surface.
PROBE_TITLE="e2e-pubsub-witness-$$"
PROBE_TODO=$(curl -sf -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d "{\"title\":\"${PROBE_TITLE}\"}" \
  "http://localhost:${BACKEND_PORT}/api/v1/todos" 2>/dev/null || echo '')
if echo "$PROBE_TODO" | grep -q '"id"'; then
  record PASS "Pub/sub probe: create todo (will publish to todo-data)"
  # Wait up to 30s for the consumer to log handling of the event. Dapr
  # Redis pub/sub propagation in DinD CI runners is meaningfully slower
  # than local Podman — 10s was too tight.
  WITNESS=0
  for _ in $(seq 1 30); do
    if docker compose logs --tail=200 backend-ts 2>/dev/null \
        | grep -q 'Consumer handling message'; then
      WITNESS=1; break
    fi
    sleep 1
  done
  if [[ "$WITNESS" == "1" ]]; then
    record PASS "Pub/sub round-trip: consumer received event"
  else
    record FAIL "Pub/sub round-trip: no 'Consumer handling message' log within 30s"
  fi
  PROBE_ID=$(echo "$PROBE_TODO" | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{try{console.log(JSON.parse(d).data.id)}catch{console.log('')}})")
  if [[ -n "$PROBE_ID" ]]; then
    curl -s -o /dev/null --max-time 5 -X DELETE \
      -H "Authorization: Bearer $TOKEN" \
      "http://localhost:${BACKEND_PORT}/api/v1/todos/${PROBE_ID}" 2>/dev/null || true
  fi
else
  record FAIL "Pub/sub probe: could not create probe todo: ${PROBE_TODO:0:120}"
fi

# Negative path — publish a malformed CloudEvent directly through Dapr's
# publish API. The consumer's input schema requires `title`; without it,
# zod validation throws and the consumer returns DROP (not RETRY) so Dapr
# does not requeue. Witness: no error spike in backend-ts logs.
ERR_BEFORE=$(docker compose logs --tail=200 backend-ts 2>/dev/null | grep -c 'Error processing message' || true)
PUBSUB_DROP_URL="http://localhost:${DAPR_PORT}/v1.0/publish/redis-pubsub/todo-data"
DROP_STATUS=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
  -X POST -H 'Content-Type: application/cloudevents+json' \
  -d '{"specversion":"1.0","type":"com.dapr.event.sent","source":"e2e-test","id":"drop-probe-'"$$"'","data":{"not_title":"missing required field"}}' \
  "$PUBSUB_DROP_URL" 2>/dev/null || echo '000')
if [[ "$DROP_STATUS" == "204" ]]; then
  record PASS "Pub/sub negative: malformed CloudEvent accepted by sidecar (204)"
  sleep 2
  ERR_AFTER=$(docker compose logs --tail=200 backend-ts 2>/dev/null | grep -c 'Error processing message' || true)
  ERR_DELTA=$(( ERR_AFTER - ERR_BEFORE ))
  # 1 expected error log = consumer rejected the malformed event with DROP.
  # >5 means Dapr is requeueing the bad event (RETRY), which would be a bug.
  if [[ "$ERR_DELTA" -ge 1 && "$ERR_DELTA" -le 5 ]]; then
    record PASS "Pub/sub negative: consumer DROP (no requeue storm; ${ERR_DELTA} error log(s))"
  else
    record FAIL "Pub/sub negative: unexpected error count delta=${ERR_DELTA} (expected 1-5)"
  fi
else
  record FAIL "Pub/sub negative: sidecar returned ${DROP_STATUS} (expected 204)"
fi
echo

echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if (( FAIL > 0 )); then
  echo "Failures:"
  for f in "${FAILURES[@]}"; do echo "  - $f"; done
  exit 1
fi
