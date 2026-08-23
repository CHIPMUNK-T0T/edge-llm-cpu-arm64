#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "usage: $0 <gateway|inference>" >&2
  exit 2
}

case "${1:-}" in
  gateway)
    selector='app.kubernetes.io/instance=inference-gateway,app.kubernetes.io/name=inference-gateway'
    ;;
  inference)
    selector='app.kubernetes.io/instance=north-mini-code,app.kubernetes.io/name=north-mini-code'
    ;;
  *)
    usage
    ;;
esac

case_name="$1-pod-delete"
kubeconfig="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
namespace="${SERVING_NAMESPACE:-edge-llm}"
gateway_local_port="${GATEWAY_RECOVERY_PORT:-18082}"
ready_timeout_seconds="${READY_TIMEOUT_SECONDS:-900}"
health_timeout_seconds="${HEALTH_TIMEOUT_SECONDS:-120}"
kubectl_cmd=(kubectl --kubeconfig "${kubeconfig}")

for command in kubectl jq curl; do
  command -v "${command}" >/dev/null || {
    echo "required command was not found: ${command}" >&2
    exit 1
  }
done

old_pod="$("${kubectl_cmd[@]}" -n "${namespace}" get pod \
  -l "${selector}" -o jsonpath='{.items[0].metadata.name}')"
if [[ -z "${old_pod}" ]]; then
  echo "target Pod was not found: ${selector}" >&2
  exit 1
fi

old_uid="$("${kubectl_cmd[@]}" -n "${namespace}" get pod "${old_pod}" \
  -o jsonpath='{.metadata.uid}')"
started_at="$(date --iso-8601=seconds)"
started_ms="$(date +%s%3N)"

"${kubectl_cmd[@]}" -n "${namespace}" delete pod "${old_pod}" --wait=false >/dev/null

new_pod=''
deadline=$((SECONDS + ready_timeout_seconds))
while [[ -z "${new_pod}" ]]; do
  if (( SECONDS >= deadline )); then
    echo "timed out waiting for replacement Pod to become Ready" >&2
    "${kubectl_cmd[@]}" -n "${namespace}" get pod -l "${selector}" -o wide >&2
    exit 1
  fi

  new_pod="$("${kubectl_cmd[@]}" -n "${namespace}" get pod -l "${selector}" -o json | \
    jq -r --arg old_uid "${old_uid}" '
      .items[]
      | select(.metadata.uid != $old_uid)
      | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))
      | .metadata.name
    ' | head -n 1)"
  [[ -n "${new_pod}" ]] || sleep 1
done
ready_ms="$(date +%s%3N)"

port_forward_log="$(mktemp)"
port_forward_pid=''
cleanup() {
  local exit_status=$?
  trap - EXIT
  if [[ -n "${port_forward_pid}" ]]; then
    kill "${port_forward_pid}" 2>/dev/null || true
    wait "${port_forward_pid}" 2>/dev/null || true
  fi
  rm -f "${port_forward_log}"
  exit "${exit_status}"
}
trap cleanup EXIT

"${kubectl_cmd[@]}" -n "${namespace}" port-forward service/inference-gateway \
  "${gateway_local_port}:8080" --address 127.0.0.1 \
  >"${port_forward_log}" 2>&1 &
port_forward_pid=$!

deadline=$((SECONDS + health_timeout_seconds))
until curl --fail --silent "http://127.0.0.1:${gateway_local_port}/health" >/dev/null; do
  if (( SECONDS >= deadline )); then
    echo "timed out waiting for Gateway health after Pod replacement" >&2
    cat "${port_forward_log}" >&2
    exit 1
  fi
  sleep 1
done
healthy_ms="$(date +%s%3N)"

cat <<EOF
case=${case_name}
started_at=${started_at}
old_pod=${old_pod}
new_pod=${new_pod}
ready_ms=$((ready_ms - started_ms))
health_ms=$((healthy_ms - started_ms))
EOF
