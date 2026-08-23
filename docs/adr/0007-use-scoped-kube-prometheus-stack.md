# ADR 0007: Use a scoped kube-prometheus-stack for observability

- Status: accepted
- Date: 2026-08-23

## Context

The lab needs CPU, memory, restart, request, error, latency, and inference
metrics that can be explained and reproduced on one ARM64 K3s node. Monitoring
must not expand the public Gateway contract or imply production availability.
The implementation should use maintained packages where possible instead of
rebuilding Prometheus, Grafana, Kubernetes discovery, and dashboard loading.

The main alternatives were:

1. Install the Prometheus and Grafana charts separately and maintain their
   discovery and integration locally.
2. Maintain custom Prometheus, Grafana, kube-state-metrics, and exporter
   manifests.
3. Wrap the published `kube-prometheus-stack` chart and remove components that
   are not useful in this lab.

## Decision

Use a small local Helm wrapper around `kube-prometheus-stack` `87.21.0`. The
dependency version is locked and its OCI digest is checked by the chart
contract. Runtime images are pinned to the ARM64 digests validated on the K3s
node.

The wrapper owns these integration points:

- a `ServiceMonitor` for the internal llama.cpp `/metrics` endpoint;
- a `PodMonitor` for Envoy `/stats/prometheus` on the Pod-only admin port;
- one read-only Grafana dashboard for serving resource and request telemetry;
- seven-day Prometheus retention with an 8 GiB local-path PVC;
- a 2 GiB local-path PVC for Grafana.

Prometheus and Grafana remain single-replica `ClusterIP` services. Grafana is
opened only through a localhost-bound port-forward and allows anonymous Viewer
access in that boundary. No monitoring route is added to Envoy or Tailscale.

Alertmanager, default alert rules, Grafana chart tests, and K3s-inapplicable
etcd, controller-manager, scheduler, and kube-proxy monitors are disabled. The
Operator admission webhook is also disabled because this milestone does not
deploy PrometheusRule resources.

The upstream node-exporter DaemonSet is disabled. Its host-root mount requires
shared/slave propagation, which WSL2 does not provide for `/`. Workload CPU and
memory come from kubelet/cAdvisor, and Kubernetes object state and restart
counts come from kube-state-metrics.

## Consequences

- One published stack supplies the Operator, Prometheus, Grafana,
  kube-state-metrics, discovery resources, and dashboard provisioning.
- Envoy administration stays outside its Service even though Prometheus can
  scrape it inside the Pod network.
- Windows host telemetry and Linux host metrics that require node-exporter are
  not collected. This milestone measures K3s workloads, not the Windows host.
- There is no alert delivery yet. Failure drills can add a small set of useful
  alerts after their failure signals are measured.
- Prometheus and Grafana data survive Pod replacement but depend on the
  single-node local-path provisioner; they are not highly available.
- The upstream monitoring CRDs are cluster-scoped and are not automatically
  removed by a normal Helm uninstall.
- Anonymous Grafana access is acceptable only while the Service remains
  ClusterIP and the documented port-forward binds to `127.0.0.1`.

## Validation

- Run `tests/monitoring-chart-contract.sh` to verify dependency digest, image
  digests, disabled components, internal-only Services, storage, monitors, and
  dashboard structure.
- Install the wrapper in namespace `monitoring` and wait for all four workload
  Pods to become Ready on the ARM64 node.
- Run `scripts/verify-monitoring.sh` to query Prometheus for all required
  workload and request metrics.
- Confirm Grafana health and dashboard UID `edge-llm-serving` through a
  localhost-only port-forward.

See [the measured verification](../verification/edge-llm-monitoring-2026-08-23.md).
