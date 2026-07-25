# K3s infrastructure smoke test — 2026-07-21

## Scope

Validate the ARM64 Kubernetes foundation independently of LLM serving. The test
covers node readiness, container scheduling, probes, cluster DNS, ClusterIP
routing, and basic resource metrics.

## Versions and node

| Item | Observed value |
| --- | --- |
| K3s | `v1.36.2+k3s1` (`01b6f04a`) |
| Kubernetes node | `surface-laptop7` |
| Architecture | `arm64` |
| Container runtime | `containerd://2.3.2-k3s2` |
| Node state | `Ready` |
| Internal IP at test time | `172.26.175.86` |

## Test workload

Applied `kubernetes/smoke-test.yaml`, containing a dedicated Namespace, a
single-replica nginx Deployment with startup/readiness/liveness probes and
resource controls, and a ClusterIP Service.

Observed workload state:

```text
pod/smoke-web-7c6f4b868f-qfs8j   1/1   Running   0 restarts
service/smoke-web                ClusterIP      port 80/TCP
```

The generated Pod name and addresses are observations, not stable interfaces.

## End-to-end cluster check

An ephemeral ARM64 `curlimages/curl:8.16.0` Pod requested:

```text
http://smoke-web.edge-llm-smoke.svc.cluster.local/
```

Result:

```text
HTTP 200
```

The client Pod was deleted automatically after the test. This verifies the
relevant path through Pod scheduling, CoreDNS, the Service virtual IP, and the
server Pod. It does not test ingress, Tailscale, or Windows-to-WSL access.

## System observations

CoreDNS, local-path-provisioner, Traefik, its ServiceLB Pod, and metrics-server
were Running after cluster startup. The two Helm installer Pods were Completed,
which is expected for installer Jobs.

At the observation point, metrics-server reported approximately 173 millicores
and 1163 MiB for the node. These values are readiness observations, not a
benchmark.

## Issue encountered

The initial non-root `kubectl` check failed because the default kubeconfig was
root-only. The resolution and security trade-off are recorded in
`docs/troubleshooting/0001-kubeconfig-permission.md`.

## Result

**Passed.** Phase 0 Kubernetes foundation requirements are met. The next gate is
LLM-independent persistent volume validation, followed by Phase 1 inference
runtime and model selection.
