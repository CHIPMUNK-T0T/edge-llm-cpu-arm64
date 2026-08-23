# Edge LLM monitoring verification — 2026-08-23

## Scope

This check validates workload observability on the existing single-node ARM64
K3s serving path, including collection after a controlled WSL restart. It does
not validate alert delivery, seven-day retention, Windows host telemetry, high
availability, or node-loss durability. Windows reboot recovery is covered by
the separate controlled recovery record.

## Configuration under test

- K3s: `v1.36.2+k3s1`
- Node architecture: `arm64`
- Kernel: `6.18.33.2-microsoft-standard-WSL2`
- Monitoring chart: `edge-llm-monitoring` `0.1.0`
- Helm release: `edge-llm-monitoring`, namespace `monitoring`, revision `4`
- Dependency: `kube-prometheus-stack` `87.21.0`
- Dependency OCI digest:
  `sha256:3f2b01fe1b3f0e2bb957c2d6bf664ace5ceab6a2119377d132aced8b2087e8cc`

The final release ran four monitoring workloads: Grafana, Prometheus Operator,
kube-state-metrics, and Prometheus. Every container image is pinned by the
platform digest observed on the ARM64 node.

## Reproduction

From the repository root:

```bash
bash tests/monitoring-chart-contract.sh

helm upgrade --install edge-llm-monitoring charts/edge-llm-monitoring \
  --namespace monitoring \
  --create-namespace \
  --kubeconfig /etc/rancher/k3s/k3s.yaml \
  --wait \
  --timeout 10m

bash scripts/verify-monitoring.sh
bash scripts/monitoring-snapshot.sh
```

Expected terminal observations are:

```text
monitoring chart contract: PASS
monitoring live verification: PASS
```

The live script creates one successful health request and one intentional 404,
waits for two 15-second scrape intervals, then requires non-empty Prometheus
results for all of the following:

| Requirement | Prometheus evidence |
| --- | --- |
| CPU | `container_cpu_usage_seconds_total` for namespace `edge-llm` |
| Memory | `container_memory_working_set_bytes` for namespace `edge-llm` |
| Request count | Envoy public connection-manager request counter |
| Error count | Envoy response-class counter with an observed 4xx series |
| Latency | Envoy inference-cluster upstream request histogram |
| Active inference | `llamacpp:requests_processing` |
| Token throughput | `llamacpp:predicted_tokens_seconds` |
| Restarts | `kube_pod_container_status_restarts_total` for `edge-llm` |

All eight raw-series checks and all 14 PromQL expressions used by the Grafana
dashboard passed after the digest-pinned, namespace-scoped Helm upgrade.

A post-recovery snapshot at `2026-08-23T16:48:01+09:00` returned:

- serving CPU: `0.014230076418712519` cores
- serving memory working set: `17,264,648,192` bytes
- Gateway requests since its WSL restart: `5`
- Gateway 4xx/5xx responses since its WSL restart: `1`
- Gateway-process-lifetime inference upstream p95: `0.475` ms

Request, error, and latency histogram values reset when the single Gateway
process restarts. This snapshot proves the query path and units; it is not a
load or capacity benchmark.

## Runtime observations

All monitoring Pods were Ready with zero restarts. One snapshot after startup
showed:

| Workload | CPU | Memory |
| --- | ---: | ---: |
| Grafana, including two provisioning sidecars | 23m | 293 MiB |
| Prometheus Operator | 8m | 18 MiB |
| kube-state-metrics | 2m | 17 MiB |
| Prometheus, including config reloader | 21m | 229 MiB |
| **Snapshot total** | **54m** | **557 MiB** |

At the same snapshot, inference used 16,523 MiB and the Gateway used 17 MiB.
These are point-in-time operational values, not capacity or benchmark results.

Prometheus bound an 8 GiB local-path PVC and Grafana bound a 2 GiB local-path
PVC. Every monitoring Service was `ClusterIP`; the inference and Gateway
Services also remained `ClusterIP` on port 8080 only.
Grafana dashboard discovery used a namespace Role rather than a ClusterRole.
kube-state-metrics was limited to the `edge-llm`, `monitoring`, and
`kube-system` namespaces and the object types used by this lab.

Grafana returned database health `ok` and version `13.1.1`. Its API listed the
provisioned read-only dashboard with UID `edge-llm-serving` and title
`Edge LLM Serving Overview`.

After the controlled WSL restart, all monitoring workloads returned Ready.
Prometheus and Grafana retained their bound local-path PVCs. The live check was
then repeated and again passed all eight raw metric groups and all 14 dashboard
queries. Serving restart series reflected the Gateway and inference container
restarts.

The same live check passed again after an actual Windows restart. A snapshot at
`2026-08-23T17:35:55+09:00` returned 0.0224 serving CPU cores,
17,345,208,320 bytes of serving memory, four Gateway requests, one error, and
0.475 ms inference-upstream p95. This verifies collection recovery on the same
WSL/K3s node after both restart boundaries; it does
not test PVC survival after node or disk loss. See the
[controlled recovery record](recovery/controlled-recovery-2026-08-23.md).

## WSL2 constraint

The upstream node-exporter DaemonSet cannot start with its default host-root
mount because WSL2 reports `/` as neither a shared nor a slave mount. The final
chart does not deploy that DaemonSet. Kubelet/cAdvisor and kube-state-metrics
provide the workload metrics required by this milestone. This avoids leaving a
known-failing Pod in the published implementation while documenting the host
telemetry limitation.

## Known limitations

- No Windows host CPU or memory series is collected.
- No alert rules or notification path are configured yet.
- Seven-day retention and node/disk-loss PVC recovery have not been exercised.
- Grafana was validated through its localhost HTTP API; the dashboard still
  requires a manual browser visual check before taking article screenshots.
- Prometheus and Grafana have one replica and local-path storage. No high
  availability or node-loss durability claim is made.
