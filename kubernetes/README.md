# Kubernetes foundation validation

This directory contains only the Phase 0 workloads used to verify K3s
scheduling, networking, probes, metrics, and local-path storage:

- `smoke-test.yaml` validates a Deployment, ClusterIP Service, DNS, and probes.
- `storage-smoke-test.yaml` validates non-root local-path PVC write/read.

The inference workload is not defined here. Its only current deployment source
is [`charts/north-mini-code`](../charts/north-mini-code/README.md).
