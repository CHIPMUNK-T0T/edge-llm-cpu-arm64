#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
kubeconfig="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
namespace="${SERVING_NAMESPACE:-edge-llm}"
release="${INFERENCE_RELEASE:-north-mini-code}"
gateway_local_port="${GATEWAY_RECOVERY_PORT:-18083}"
failure_timeout_seconds="${FAILURE_TIMEOUT_SECONDS:-120}"
rollback_timeout="${ROLLBACK_TIMEOUT:-15m}"
kubectl_cmd=(kubectl --kubeconfig "${kubeconfig}")
helm_cmd=(helm --kubeconfig "${kubeconfig}")

for command in kubectl helm jq curl; do
  command -v "${command}" >/dev/null || {
    echo "required command was not found: ${command}" >&2
    exit 1
  }
done

baseline_revision="$("${helm_cmd[@]}" -n "${namespace}" list \
  --filter "^${release}$" -o json | jq -r '.[0].revision // empty')"
baseline_status="$("${helm_cmd[@]}" -n "${namespace}" list \
  --filter "^${release}$" -o json | jq -r '.[0].status // empty')"
current_source="$("${helm_cmd[@]}" -n "${namespace}" get values "${release}" -a -o json | \
  jq -r '.model.sourcePath')"

if [[ -z "${baseline_revision}" || "${baseline_status}" != 'deployed' ]]; then
  echo "inference Helm release is not in a deployed state" >&2
  exit 1
fi
if [[ -z "${current_source}" || ! -d "${current_source}" ]]; then
  echo "current model source is not a directory: ${current_source}" >&2
  exit 1
fi

invalid_source="${current_source}.recovery-test-missing"
if [[ -e "${invalid_source}" ]]; then
  echo "refusing to use an existing path as the invalid source: ${invalid_source}" >&2
  exit 1
fi

selector='app.kubernetes.io/instance=north-mini-code,app.kubernetes.io/name=north-mini-code'
old_pod="$("${kubectl_cmd[@]}" -n "${namespace}" get pod -l "${selector}" \
  -o jsonpath='{.items[0].metadata.name}')"
old_uid="$("${kubectl_cmd[@]}" -n "${namespace}" get pod "${old_pod}" \
  -o jsonpath='{.metadata.uid}')"

port_forward_log="$(mktemp)"
port_forward_pid=''
rollback_required='false'
rollback_finished='false'
cleanup() {
  local exit_status=$?
  trap - EXIT
  if [[ "${rollback_required}" == 'true' && "${rollback_finished}" != 'true' ]]; then
    echo "attempting safety rollback to revision ${baseline_revision}" >&2
    "${helm_cmd[@]}" -n "${namespace}" rollback "${release}" "${baseline_revision}" \
      --wait --timeout "${rollback_timeout}" >&2 || true
  fi
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

for _ in $(seq 1 30); do
  curl --fail --silent "http://127.0.0.1:${gateway_local_port}/health" >/dev/null && break
  sleep 1
done
curl --fail --silent "http://127.0.0.1:${gateway_local_port}/health" >/dev/null

started_at="$(date --iso-8601=seconds)"
started_ms="$(date +%s%3N)"
"${helm_cmd[@]}" -n "${namespace}" upgrade "${release}" \
  "${repo_root}/charts/north-mini-code" --reuse-values \
  --set-string "model.sourcePath=${invalid_source}" >/dev/null
rollback_required='true'
failed_revision="$("${helm_cmd[@]}" -n "${namespace}" list \
  --filter "^${release}$" -o json | jq -r '.[0].revision')"

new_pod=''
failure_message=''
deadline=$((SECONDS + failure_timeout_seconds))
while [[ -z "${failure_message}" ]]; do
  if (( SECONDS >= deadline )); then
    echo "timed out waiting for the invalid model path failure" >&2
    "${kubectl_cmd[@]}" -n "${namespace}" get pod -l "${selector}" -o wide >&2
    exit 1
  fi

  new_pod="$("${kubectl_cmd[@]}" -n "${namespace}" get pod -l "${selector}" -o json | \
    jq -r --arg old_uid "${old_uid}" '
      .items[] | select(.metadata.uid != $old_uid) | .metadata.name
    ' | head -n 1)"
  if [[ -n "${new_pod}" ]]; then
    failure_message="$("${kubectl_cmd[@]}" -n "${namespace}" get events \
      --field-selector "involvedObject.name=${new_pod}" -o json | \
      jq -r '
        [.items[]
          | select(.reason == "FailedMount")
          | select(.message | contains("hostPath type check failed"))
          | .message][0] // empty
      ')"
  fi
  [[ -n "${failure_message}" ]] || sleep 1
done
failure_detected_ms="$(date +%s%3N)"

gateway_failure_status="$(curl --silent --output /dev/null \
  --write-out '%{http_code}' "http://127.0.0.1:${gateway_local_port}/health" || true)"

rollback_started_ms="$(date +%s%3N)"
"${helm_cmd[@]}" -n "${namespace}" rollback "${release}" "${baseline_revision}" \
  --wait --timeout "${rollback_timeout}" >/dev/null
rollback_finished='true'
rollback_ready_ms="$(date +%s%3N)"

deadline=$((SECONDS + 120))
until curl --fail --silent "http://127.0.0.1:${gateway_local_port}/health" >/dev/null; do
  if (( SECONDS >= deadline )); then
    echo "timed out waiting for Gateway health after rollback" >&2
    exit 1
  fi
  sleep 1
done
healthy_ms="$(date +%s%3N)"

cat <<EOF
case=invalid-model-source
started_at=${started_at}
baseline_revision=${baseline_revision}
failed_revision=${failed_revision}
failed_pod=${new_pod}
failure_message=${failure_message}
gateway_failure_http_status=${gateway_failure_status}
failure_detection_ms=$((failure_detected_ms - started_ms))
rollback_ready_ms=$((rollback_ready_ms - rollback_started_ms))
total_health_recovery_ms=$((healthy_ms - started_ms))
EOF
