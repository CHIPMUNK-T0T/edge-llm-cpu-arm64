#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
kubeconfig="${KUBECONFIG:-/etc/rancher/k3s/k3s.yaml}"
monitoring_namespace="monitoring"
serving_namespace="edge-llm"
prometheus_local_port="19090"
gateway_local_port="18081"

kubectl_cmd=(kubectl --kubeconfig "${kubeconfig}")

prometheus_service="$("${kubectl_cmd[@]}" -n "${monitoring_namespace}" get service \
  -l app=kube-prometheus-stack-prometheus \
  -o jsonpath='{.items[0].metadata.name}')"

if [[ -z "${prometheus_service}" ]]; then
  echo 'Prometheus Service was not found' >&2
  exit 1
fi

cleanup() {
  local exit_status=$?
  trap - EXIT
  if [[ -n "${prometheus_forward_pid:-}" ]]; then
    kill "${prometheus_forward_pid}" 2>/dev/null || true
    wait "${prometheus_forward_pid}" 2>/dev/null || true
  fi
  if [[ -n "${gateway_forward_pid:-}" ]]; then
    kill "${gateway_forward_pid}" 2>/dev/null || true
    wait "${gateway_forward_pid}" 2>/dev/null || true
  fi
  exit "${exit_status}"
}
trap cleanup EXIT

"${kubectl_cmd[@]}" -n "${monitoring_namespace}" port-forward \
  "service/${prometheus_service}" "${prometheus_local_port}:9090" \
  --address 127.0.0.1 >/dev/null 2>&1 &
prometheus_forward_pid=$!

"${kubectl_cmd[@]}" -n "${serving_namespace}" port-forward \
  service/inference-gateway "${gateway_local_port}:8080" \
  --address 127.0.0.1 >/dev/null 2>&1 &
gateway_forward_pid=$!

for _ in $(seq 1 30); do
  if curl --fail --silent "http://127.0.0.1:${prometheus_local_port}/-/ready" >/dev/null && \
     curl --fail --silent "http://127.0.0.1:${gateway_local_port}/health" >/dev/null; then
    break
  fi
  sleep 1
done

curl --fail --silent "http://127.0.0.1:${gateway_local_port}/health" >/dev/null
curl --silent "http://127.0.0.1:${gateway_local_port}/monitoring-verification-not-found" >/dev/null

echo 'Waiting for two Prometheus scrape intervals...'
sleep 35

assert_metric() {
  local description="$1"
  local query="$2"
  local result
  result="$(curl --fail --silent --get \
    --data-urlencode "query=${query}" \
    "http://127.0.0.1:${prometheus_local_port}/api/v1/query")"
  if ! jq -e '
    .status == "success" and
    (.data.result | length > 0) and
    any(.data.result[]; .value[1] != "NaN")' <<<"${result}" >/dev/null; then
    echo "missing metric: ${description}" >&2
    jq . <<<"${result}" >&2
    exit 1
  fi
  echo "metric present: ${description}"
}

assert_metric 'serving CPU' \
  'container_cpu_usage_seconds_total{namespace="edge-llm",container!="POD",image!=""}'
assert_metric 'serving memory' \
  'container_memory_working_set_bytes{namespace="edge-llm",container!="POD",image!=""}'
assert_metric 'Gateway request count' \
  'envoy_http_downstream_rq_total{envoy_http_conn_manager_prefix="public"}'
assert_metric 'Gateway error count by response class' \
  'envoy_http_downstream_rq_xx{envoy_http_conn_manager_prefix="public",envoy_response_code_class="4"}'
assert_metric 'Gateway upstream latency histogram' \
  'envoy_cluster_upstream_rq_time_bucket{envoy_cluster_name="inference"}'
assert_metric 'inference processing requests' 'llamacpp:requests_processing'
assert_metric 'inference token throughput' 'llamacpp:predicted_tokens_seconds'
assert_metric 'Pod restart count' \
  'kube_pod_container_status_restarts_total{namespace="edge-llm"}'

dashboard_query_count=0
while IFS= read -r query; do
  dashboard_query_count=$((dashboard_query_count + 1))
  query="${query//\$__rate_interval/1m}"
  assert_metric "dashboard query ${dashboard_query_count}" "${query}"
done < <(jq -r '.. | objects | .expr? // empty' \
  "${repo_root}/charts/edge-llm-monitoring/files/edge-llm-overview.json")

if (( dashboard_query_count < 10 )); then
  echo 'dashboard query coverage is unexpectedly small' >&2
  exit 1
fi

echo 'monitoring live verification: PASS'
