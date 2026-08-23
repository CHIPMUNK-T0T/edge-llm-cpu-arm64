# Edge LLM monitoring chart

This wrapper installs a deliberately small `kube-prometheus-stack` profile for
the single-node ARM64 K3s lab. It collects Kubernetes resource metrics, Envoy
Gateway request metrics, and llama.cpp inference metrics without adding a public
monitoring endpoint.

## Boundaries

- Grafana and Prometheus remain `ClusterIP` services.
- Envoy's admin port is scraped directly from the Gateway Pod by `PodMonitor`;
  it is not added to the Gateway Service.
- The inference `ServiceMonitor` uses the existing internal `/metrics` endpoint.
- Alertmanager and default alert rules are outside this measurement milestone.
- Prometheus and Grafana run as one replica and use K3s `local-path` storage.
- The published chart, OCI artifact, and all runtime images are pinned.
- WSL2-incompatible node-exporter is disabled; kubelet/cAdvisor provides
  workload CPU and memory metrics.
- Alertmanager, default rules, and unused K3s control-plane monitors are not
  deployed in this measurement milestone.

## Install or upgrade

Run from the repository root:

```bash
helm dependency build charts/edge-llm-monitoring
helm upgrade --install edge-llm-monitoring charts/edge-llm-monitoring \
  --namespace monitoring \
  --create-namespace \
  --kubeconfig /etc/rancher/k3s/k3s.yaml \
  --wait \
  --timeout 10m
```

Open Grafana only on the local machine:

```bash
kubectl --kubeconfig /etc/rancher/k3s/k3s.yaml \
  -n monitoring port-forward service/edge-llm-monitoring-grafana \
  3000:80 --address 127.0.0.1
```

Then browse to `http://127.0.0.1:3000`. The provisioned dashboard is read-only,
and anonymous access is limited to the Viewer role. No Grafana route is added to
the inference Gateway or Tailscale access path.

## What to inspect

Open `Edge LLM Serving Overview`, set the time range to **Last 15 minutes**, and
use these panels rather than treating Grafana itself as the result:

| Question | Panel |
| --- | --- |
| Are both metric endpoints being collected? | `Inference scrape up` and `Gateway scrape up` must be 1 |
| How much CPU and memory does each serving Pod use? | `Serving CPU` and `Serving memory working set` |
| Did client traffic reach the Gateway? | `Public request rate` |
| Did requests fail? | `4xx + 5xx rate` and `Gateway response classes` |
| How long did Gateway-to-inference requests take? | `Inference upstream p95` |
| Is inference active or queued? | `Inference requests processing` and `Inference queue` |
| Is generation progressing? | `Inference token throughput` |
| Did a container restart during a drill? | `Serving container restarts` |

To create a visible sample, run `bash scripts/verify-monitoring.sh` from another
terminal, wait about 35 seconds, then refresh the dashboard. The request graph
must show traffic, the error graph must show the intentional 404, CPU and memory
must have one series for Gateway and one for inference, and the latency panel
must contain inference upstream samples. Empty scrape panels indicate a
collection failure; zero request/error rates can simply mean there was no
traffic in the selected time range.

## Verify

Run both the static and live contracts:

```bash
bash tests/monitoring-chart-contract.sh
bash scripts/verify-monitoring.sh
bash scripts/monitoring-snapshot.sh
```

The live check generates one successful request and one intentional 404, waits
for two scrape intervals, and verifies all required Prometheus series. See the
[measured result](../../docs/verification/edge-llm-monitoring-2026-08-23.md).
`monitoring-snapshot.sh` prints the five requested operational values as JSON:

serving CPU cores, serving memory bytes, cumulative Gateway requests, cumulative
Gateway 4xx/5xx errors, and Gateway-process-lifetime upstream p95 milliseconds.
