#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
chart_dir="${repo_root}/charts/edge-llm-monitoring"
rendered="$(mktemp)"
trap 'rm -f "${rendered}"' EXIT

dependency_output="$(helm dependency build "${chart_dir}" 2>&1)"
printf '%s\n' "${dependency_output}"
if ! grep -q 'Digest: sha256:3f2b01fe1b3f0e2bb957c2d6bf664ace5ceab6a2119377d132aced8b2087e8cc' <<<"${dependency_output}"; then
  echo 'unexpected kube-prometheus-stack OCI digest' >&2
  exit 1
fi

helm lint "${chart_dir}"
helm template edge-llm-monitoring "${chart_dir}" \
  --namespace monitoring >"${rendered}"

jq -e '.uid == "edge-llm-serving" and (.panels | length >= 10)' \
  "${chart_dir}/files/edge-llm-overview.json" >/dev/null

grep -q 'kind: ServiceMonitor' "${rendered}"
grep -q 'name: edge-llm-inference' "${rendered}"
grep -q 'path: /metrics' "${rendered}"
grep -q 'kind: PodMonitor' "${rendered}"
grep -q 'name: edge-llm-gateway' "${rendered}"
grep -q 'path: /stats/prometheus' "${rendered}"
grep -q 'port: admin' "${rendered}"
grep -q 'monitoring.edge-llm.io/stack: edge-llm' "${rendered}"
grep -q 'storageClassName: local-path' "${rendered}"
grep -q 'storage: 8Gi' "${rendered}"
grep -q 'storage: 2Gi' "${rendered}"
grep -q 'name: edge-llm-monitoring-kube-state-metrics' "${rendered}"

for digest in \
  7cb8c64c4d57a57e734073f3cc94620adb24a0acb929bd80ba9f14017e3a975b \
  dc2d74b28e4cf8984fa52af1f39bc7c3d9c73760b41a74d629f5d11b1ab28616 \
  21b9fe7bb29d65caf2445ccbf96ff6eda5e589a92bd8f5188f957fe75b551d72 \
  214f8427c8fba80c327bb94a75feb802ae12f2d6ca30812aa6e7d22f09bbea80 \
  7d9247d2351480fc74587e24681578f815f387bafb2ee7b86a852a94c4cd3774 \
  74550ba3e8bf93f47bc574231090d340ae9c01d25cd11ff74799e65f9fdb9a48 \
  85108987d044b18a098126732f98602df408888c0f7d456241f5abefb9744bc1; do
  grep -q "@sha256:${digest}" "${rendered}"
done

if grep -q 'prometheus-node-exporter' "${rendered}"; then
  echo 'node-exporter is incompatible with the WSL2 mount boundary' >&2
  exit 1
fi
if grep -q 'name: edge-llm-monitoring-grafana-clusterrole' "${rendered}"; then
  echo 'Grafana dashboard discovery must use namespace-scoped RBAC' >&2
  exit 1
fi

if ! grep -q -- '--namespaces=edge-llm,monitoring,kube-system' "${rendered}"; then
  echo 'kube-state-metrics namespace scope is missing' >&2
  exit 1
fi


if grep -Eq '^  type: (LoadBalancer|NodePort)$' "${rendered}"; then
  echo 'monitoring must not render an externally reachable Service type' >&2
  exit 1
fi

if grep -Eq 'kind: (Ingress|HTTPRoute)' "${rendered}"; then
  echo 'monitoring must not render an ingress or gateway route' >&2
  exit 1
fi

if grep -q 'kind: Alertmanager' "${rendered}"; then
  echo 'Alertmanager is outside the current monitoring scope' >&2
  exit 1
fi

echo 'monitoring chart contract: PASS'
