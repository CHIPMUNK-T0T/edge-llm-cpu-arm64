#!/usr/bin/env bash
set -euo pipefail

kubeconfig="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
monitoring_namespace="${MONITORING_NAMESPACE:-monitoring}"
prometheus_local_port="${PROMETHEUS_SNAPSHOT_PORT:-19091}"
kubectl_cmd=(kubectl --kubeconfig "${kubeconfig}")

for command in kubectl curl jq; do
  command -v "${command}" >/dev/null || {
    echo "required command was not found: ${command}" >&2
    exit 1
  }
done

prometheus_service="$("${kubectl_cmd[@]}" -n "${monitoring_namespace}" get service \
  -l app=kube-prometheus-stack-prometheus \
  -o jsonpath='{.items[0].metadata.name}')"
if [[ -z "${prometheus_service}" ]]; then
  echo 'Prometheus Service was not found' >&2
  exit 1
fi

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

"${kubectl_cmd[@]}" -n "${monitoring_namespace}" port-forward \
  "service/${prometheus_service}" "${prometheus_local_port}:9090" \
  --address 127.0.0.1 >"${port_forward_log}" 2>&1 &
port_forward_pid=$!

for _ in $(seq 1 30); do
  curl --fail --silent "http://127.0.0.1:${prometheus_local_port}/-/ready" >/dev/null && break
  sleep 1
done
curl --fail --silent "http://127.0.0.1:${prometheus_local_port}/-/ready" >/dev/null

query_value() {
  local query="$1"
  local response
  response="$(curl --fail --silent --get \
    --data-urlencode "query=${query}" \
    "http://127.0.0.1:${prometheus_local_port}/api/v1/query")"
  jq -er '
    select(.status == "success")
    | .data.result[0].value[1]
    | select(. != "NaN")
  ' <<<"${response}"
}

cpu_cores="$(query_value '
  sum(rate(container_cpu_usage_seconds_total{
    namespace="edge-llm",
    pod=~"north-mini-code-.*|inference-gateway-.*",
    container!="POD",
    image!=""
  }[5m]))
')"
memory_bytes="$(query_value '
  sum(container_memory_working_set_bytes{
    namespace="edge-llm",
    pod=~"north-mini-code-.*|inference-gateway-.*",
    container!="POD",
    image!=""
  })
')"
request_total="$(query_value '
  sum(envoy_http_downstream_rq_total{envoy_http_conn_manager_prefix="public"})
')"
error_total="$(query_value '
  sum(envoy_http_downstream_rq_xx{
    envoy_http_conn_manager_prefix="public",
    envoy_response_code_class=~"4|5"
  })
  or vector(0)
')"
latency_p95_ms="$(query_value '
  histogram_quantile(0.95,
    sum by (le) (envoy_cluster_upstream_rq_time_bucket{
      envoy_cluster_name="inference"
    })
  )
')"

jq -n \
  --arg observed_at "$(date --iso-8601=seconds)" \
  --arg serving_cpu_cores "${cpu_cores}" \
  --arg serving_memory_bytes "${memory_bytes}" \
  --arg gateway_requests_total "${request_total}" \
  --arg gateway_errors_total "${error_total}" \
  --arg inference_upstream_p95_ms "${latency_p95_ms}" \
  '{
    observed_at: $observed_at,
    serving_cpu_cores: ($serving_cpu_cores | tonumber),
    serving_memory_bytes: ($serving_memory_bytes | tonumber),
    gateway_requests_total: ($gateway_requests_total | tonumber),
    gateway_errors_total: ($gateway_errors_total | tonumber),
    inference_upstream_p95_ms: ($inference_upstream_p95_ms | tonumber)
  }'
