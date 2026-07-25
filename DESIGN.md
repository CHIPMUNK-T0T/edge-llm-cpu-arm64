# Design

## Goal and scope

This is a single-node technical verification project, not a production service.
It demonstrates the lifecycle an FDE would perform in a constrained customer
environment: assess constraints, deploy an AI workload, expose it safely to
clients, observe it, measure it, and recover it when it fails.

## Reference environment

| Area | Target |
| --- | --- |
| Host | Surface Laptop 7, Snapdragon X Elite, 64 GB RAM |
| Host OS | Windows 11 ARM64 |
| Linux runtime | WSL2 Ubuntu ARM64; 48 GB configured ceiling, 46 GiB observed |
| Orchestrator | single-node K3s; Helm 4.2.0 deployment client |
| Inference runtime | official versioned `llama.cpp` `llama-server` ARM64 image |
| Model | North Mini Code 1.0 Q4_0 GGUF |
| Remote network | private Tailscale tailnet |
| Client | embedded Web UI; minimal Android streaming client; PC command-line client |

The model identity, quantization, artifact hash, and runtime image digest form
the fixed Phase 1 baseline. Context size, threads, resource settings, and other
explicitly varied inference controls are experiment parameters. Record their
values with results.

The `charts/north-mini-code` chart is the only serving definition in the
current repository. The earlier raw serving manifests were removed after the
chart passed static rendering and K3s API validation. The existing Deployment,
Service, and bound model PVC were then transferred in place to Helm release
`north-mini-code`; their object UIDs and the Service ClusterIP were preserved.

## Logical architecture

```text
[Android client] ----\
                    +-- Tailscale --> [Gateway / ingress] --> [K3s Service]
[External PC] ------/                                      |
                                                     [Helm-managed Pod]
                                                        /          \
                                             [model init]      [llama-server]
                                                   |                 |
                                           [host GGUF] ---------> [PVC]

[Prometheus] <--- metrics / exporter --- gateway and workload
      |
[Grafana]

[Windows browser] -- localhost-only port-forward --> [K3s Service]
```

## Boundaries and responsibilities

| Boundary | Responsibility | Not responsible for |
| --- | --- | --- |
| Tailscale | Private, encrypted connectivity between enrolled devices | Application authentication or request policy |
| Gateway / ingress | Only supported entry point; reverse proxy, request policy, and telemetry | Direct model inference |
| K3s | Scheduling and lifecycle of in-cluster workloads | Multi-node availability |
| Helm chart | Declarative serving configuration, release history, upgrade, and rollback | Preserving availability on this single node |
| `llama-server` | OpenAI-compatible inference and streaming | Public exposure or durable authorization |
| PVC | Model storage persistence within the lab | Distributed storage durability |
| Android client | End-to-end streaming and client-side experience measurements | Product-grade UX or distribution |

## Design constraints and trade-offs

- **Single replica:** model memory makes one replica the expected configuration
  on a 64 GB host. This makes availability a limitation to document, not a
  feature to emulate.
- **Memory envelope:** cap the model workload at 40 GiB within the 48 GB WSL2
  ceiling. Any swap growth during inference is a failed performance result,
  even if the request eventually succeeds.
- **WSL2 + K3s:** this yields Linux-native container and Kubernetes semantics
  while retaining Windows on ARM as the host constraint. Startup, networking,
  and filesystem behavior must be verified rather than assumed.
- **Gateway before inference:** prevents the inference endpoint from becoming
  the network boundary, and creates one place for request controls and metrics.
- **Tailscale rather than public ingress:** suitable for private lab access and
  remote-client verification. It does not remove the need for gateway policy.
- **GGUF quantization:** reduces RAM requirements at a quality/performance
  trade-off. The chosen quantization is an experimental result, not a default.
- **Upstream runtime package:** use the official versioned ARM64 server image
  instead of maintaining a custom build. Pin the platform digest and validate
  the model, Web UI, security context, and API behavior on this host.
- **Embedded Web UI:** retain the upstream Web UI as the primary human-operated
  client. External access will still pass through Tailscale and the gateway;
  the UI does not make direct public exposure acceptable.
- **Windows-local validation:** before building the external path, bind
  `kubectl port-forward` only to `127.0.0.1` and verify the K3s-hosted embedded
  UI from the Windows browser. This is a temporary operator path, not the final
  ingress architecture.
- **One Helm source:** do not retain raw serving manifests beside the chart.
  Git history preserves Phase 1; keeping two active definitions would create
  configuration drift without adding portfolio value.
- **Model preparation in the Pod lifecycle:** an init container copies the
  pinned host GGUF only when the PVC does not contain the verified artifact and
  checks its exact size and SHA-256 before inference starts. This avoids a race
  between an import Job and the Deployment, at the cost of verifying the 17 GB
  file on each Pod start.
- **Retained model PVC:** Helm owns the PVC but marks it with
  `helm.sh/resource-policy: keep`. Uninstalling the release must not discard the
  costly verified artifact; reinstall therefore requires an explicit ownership
  step for the retained claim.

## Success criteria

The project is complete only when the evidence recorded in `PLAN.md` supports:

1. Reproducible deployment of the model workload to K3s through Helm.
2. Private access from both an external PC and Android client via Tailscale and
   the gateway, including streaming responses.
3. Measured performance and resource use for at least one documented workload.
4. Observable and reproducible recovery from selected workload, configuration,
   networking, and upgrade failures.
5. Clear limits, trade-offs, and non-goals that can be explained in an
   interview.
