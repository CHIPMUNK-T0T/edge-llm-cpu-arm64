#!/bin/sh

set -eu

repository_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
chart="$repository_root/charts/inference-gateway"
kubeconfig="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
namespace="${GATEWAY_TEST_NAMESPACE:-edge-llm}"
release="${GATEWAY_UNAVAILABLE_RELEASE:-gateway-unavailable-contract}"
local_port="${GATEWAY_UNAVAILABLE_PORT:-18083}"
base_url="http://127.0.0.1:$local_port"
work_dir="$(mktemp -d)"
release_created=0
port_forward_pid=""

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

cleanup() {
  exit_status=$?
  trap - EXIT HUP INT TERM
  cleanup_failed=0
  if [ -n "$port_forward_pid" ]; then
    kill "$port_forward_pid" 2>/dev/null || true
    wait "$port_forward_pid" 2>/dev/null || true
  fi
  if [ "$release_created" -eq 1 ]; then
    if ! helm uninstall "$release" \
      --namespace "$namespace" \
      --kubeconfig "$kubeconfig" >/dev/null 2>&1; then
      printf 'CLEANUP FAIL: could not uninstall temporary release: %s\n' \
        "$release" >&2
      cleanup_failed=1
    fi
    if helm status "$release" --namespace "$namespace" --kubeconfig "$kubeconfig" \
      >/dev/null 2>&1; then
      printf 'CLEANUP FAIL: temporary release remains: %s\n' "$release" >&2
      cleanup_failed=1
    fi
  fi
  if ! rm -rf -- "$work_dir"; then
    printf 'CLEANUP FAIL: could not remove work directory: %s\n' "$work_dir" >&2
    cleanup_failed=1
  fi
  if [ "$cleanup_failed" -ne 0 ] && [ "$exit_status" -eq 0 ]; then
    exit_status=1
  fi
  exit "$exit_status"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

if helm status "$release" --namespace "$namespace" --kubeconfig "$kubeconfig" \
  >/dev/null 2>&1; then
  fail "temporary release already exists: $release"
fi

helm install "$release" "$chart" \
  --namespace "$namespace" \
  --create-namespace \
  --kubeconfig "$kubeconfig" \
  --set-string "upstream.host=missing-inference.$namespace.svc.cluster.local" \
  --rollback-on-failure \
  --wait=watcher \
  --timeout 3m >/dev/null
release_created=1

kubectl --kubeconfig "$kubeconfig" --namespace "$namespace" \
  port-forward "service/$release" "$local_port:8080" --address 127.0.0.1 \
  >"$work_dir/port-forward.log" 2>&1 &
port_forward_pid=$!

attempt=0
while [ "$attempt" -lt 30 ]; do
  status="$(curl --silent --output /dev/null --write-out '%{http_code}' \
    --connect-timeout 1 --max-time 2 "$base_url/health" 2>/dev/null || true)"
  [ "$status" != 000 ] && break
  attempt=$((attempt + 1))
  sleep 1
done
[ "${status:-000}" != 000 ] || \
  fail "temporary Gateway port-forward did not become reachable"

expected='{"error":{"message":"inference unavailable","type":"service_unavailable"}}'

assert_unavailable() {
  name="$1"
  method="$2"
  path="$3"
  request_file="${4:-}"
  response_file="$work_dir/$name.json"
  response_headers="$work_dir/$name-headers.txt"

  if [ -n "$request_file" ]; then
    status="$(curl --silent --show-error \
      --connect-timeout 2 \
      --max-time 15 \
      --request "$method" \
      --header 'Content-Type: application/json' \
      --data-binary "@$request_file" \
      --dump-header "$response_headers" \
      --output "$response_file" \
      --write-out '%{http_code}' \
      "$base_url$path")"
  else
    status="$(curl --silent --show-error \
      --connect-timeout 2 \
      --max-time 15 \
      --request "$method" \
      --dump-header "$response_headers" \
      --output "$response_file" \
      --write-out '%{http_code}' \
      "$base_url$path")"
  fi

  [ "$status" = 503 ] || fail "$name returned HTTP $status"
  actual="$(tr -d '\r\n' <"$response_file")"
  [ "$actual" = "$expected" ] || fail "$name returned an unexpected error body"
  tr -d '\r' <"$response_headers" >"$work_dir/$name-headers-normalized.txt"
  grep -Eiq '^content-type:[[:space:]]*application/json([[:space:]]*;|[[:space:]]*$)' \
    "$work_dir/$name-headers-normalized.txt" || \
    fail "$name response content type is not application/json"
  if grep -Eiq 'missing-inference|upstream connect|connection failure|reset reason|x-envoy-upstream-service-time' \
    "$response_headers" "$response_file"; then
    fail "$name exposed upstream connection details"
  fi
}

cat >"$work_dir/openai.json" <<'EOF'
{"model":"unavailable-fixture","messages":[{"role":"user","content":"hello"}],"max_tokens":512,"stream":false}
EOF
cat >"$work_dir/anthropic.json" <<'EOF'
{"model":"unavailable-fixture","messages":[{"role":"user","content":"hello"}],"max_tokens":512,"stream":false}
EOF

assert_unavailable health GET /health
assert_unavailable openai POST /v1/chat/completions "$work_dir/openai.json"
assert_unavailable anthropic POST /v1/messages "$work_dir/anthropic.json"

helm uninstall "$release" \
  --namespace "$namespace" \
  --kubeconfig "$kubeconfig" >/dev/null
if helm status "$release" --namespace "$namespace" --kubeconfig "$kubeconfig" \
  >/dev/null 2>&1; then
  fail "temporary release still exists after uninstall: $release"
fi
release_created=0

printf 'Gateway unavailable-upstream contract: PASS\n'
