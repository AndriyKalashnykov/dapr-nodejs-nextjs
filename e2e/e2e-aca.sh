#!/usr/bin/env bash
# End-to-end smoke test against a live Azure Container Apps deployment.
#
# Reads the Next.js and backend FQDNs from `terraform output -raw`, runs the
# same CRUD + auth + cross-service assertions as e2e/e2e-test.sh but without
# the local-only probes (no Zipkin, Dashboard, Grafana — those are compose).
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

PASS=0; FAIL=0; FAILURES=()

record() {
  if [[ "$1" == "PASS" ]]; then
    echo "  ✓ $2"; PASS=$((PASS + 1))
  else
    echo "  ✗ $2"; FAIL=$((FAIL + 1)); FAILURES+=("$2")
  fi
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

echo "[4/4] Backend CRUD cycle..."
assert_http "List todos" \
  "$BACKEND_URL/api/v1/todos" 200 GET "" "$TOKEN"

CREATE_RESP=$(curl -sf -X POST \
  -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' \
  -d '{"title":"e2e-aca-todo"}' \
  "$BACKEND_URL/api/v1/todos" 2>/dev/null || echo '')
if echo "$CREATE_RESP" | grep -q '"id"'; then
  record PASS "Create todo on ACA returns id"
  TODO_ID=$(echo "$CREATE_RESP" | node -e "let d='';process.stdin.on('data',c=>d+=c).on('end',()=>{try{console.log(JSON.parse(d).data.id)}catch{console.log('')}})")
else
  record FAIL "Create todo on ACA — no id: ${CREATE_RESP:0:160}"
  TODO_ID=""
fi

if [[ -n "$TODO_ID" ]]; then
  assert_http "Get todo by id" \
    "$BACKEND_URL/api/v1/todos/${TODO_ID}" 200 GET "" "$TOKEN"
  assert_http "Delete todo" \
    "$BACKEND_URL/api/v1/todos/${TODO_ID}" 200 DELETE "" "$TOKEN"
fi
echo

echo "=== Results: ${PASS} passed, ${FAIL} failed ==="
if (( FAIL > 0 )); then
  echo "Failures:"
  for f in "${FAILURES[@]}"; do echo "  - $f"; done
  exit 1
fi
