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

The tracked default profile binds the verified model identity, quantization,
artifact hash, official runtime image digest, and serving controls. The profile
is reproducible, but it is not a universal default: another
llama.cpp-compatible profile is accepted only after it passes the same chart,
artifact, and inference API contracts. Machine placement, such as the absolute
host model path, remains site configuration.

`config/models/north-mini-code-q4-0.yaml` is the canonical artifact provenance
record. A static contract checks its filename, quantization, size, hash,
repository revision, and benchmark model ID against their deployment and
download consumers.

The `charts/north-mini-code` chart is the only serving definition in the
current repository. It manages one Deployment, one ClusterIP Service, and one
retained model PVC through Helm release `north-mini-code`. Helm values are the
composition root, the PVC mount is the model-artifact interface, and the
ClusterIP Service is the inference network interface.

## Logical architecture

```text
[Android client (planned)] ----\
                                +-- [Tailscale (planned)] --> [Gateway Deployment (planned)]
[External PC (planned)] --------/                                  separate release
                                                                          |
                                                               [Inference Service]
                                                                          |
                                                                  [Inference Pod]
                                                                     /        \
                                                           [model init]  [llama-server]
                                                                |             |
                                                        [host GGUF] -------> [PVC]

[Prometheus (planned)] <--- metrics / exporter --- gateway and workload
          |
[Grafana (planned)]

[Windows browser] -- localhost-only port-forward --> [K3s Service]
```

## Boundaries and responsibilities

| Boundary | Responsibility | Not responsible for |
| --- | --- | --- |
| Tailscale | Private, encrypted connectivity between enrolled devices | Application authentication or request policy |
| Gateway / ingress | Only supported entry point; reverse proxy, request policy, and telemetry | Direct model inference |
| Inference Service | Stable in-cluster DNS/port contract and routing to Ready inference Pods | Model loading or external exposure |
| K3s | Scheduling and lifecycle of in-cluster workloads | Multi-node availability |
| Helm chart | Declarative serving configuration, release history, upgrade, and rollback | Preserving availability on this single node |
| Model init | Place an exact size/SHA-verified GGUF at the PVC contract path before inference starts | Serving HTTP requests |
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
- **Two long-running workload boundaries:** inference and gateway have
  different privileges, update cadence, and failure domains, so they are
  separate Deployments and Helm releases. Model preparation remains an init
  container because it is an ordered prerequisite of inference, not an
  independently available service.
- **Kubernetes-native injection:** use schema-constrained Helm values, PVC
  mounts, Service DNS, and an explicitly tested HTTP/SSE subset instead of an
  application DI framework, CRD, Operator, or unrestricted plugin values.
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
  The Helm chart is the only serving definition, avoiding configuration drift
  from parallel deployment paths.
- **Model preparation in the Pod lifecycle:** an init container executes a
  separately testable script that copies the profile-selected host GGUF only
  when the PVC does not contain the verified artifact and checks its exact size
  and SHA-256 before inference starts. Its contract is four inputs
  (`SOURCE_FILE`, `TARGET_FILE`, `EXPECTED_SIZE`, and
  `EXPECTED_SHA256`) and one verified file at the PVC path. This avoids an
  import Job/Deployment race at the cost of verifying the file on each start.
- **Contract scope:** the serving adapter guarantees only the verified subset:
  health, Prometheus metrics, 4xx invalid-request handling, non-streaming
  `/v1/chat/completions`, and multi-frame SSE ending once in `[DONE]`.
  It does not claim the full OpenAI API surface.
- **Artifact identity per release:** a release and its retained PVC bind one
  model filename, size, and SHA-256. A different artifact uses a different
  release/PVC rather than an in-place profile mutation that could retain two
  large files or exhaust the 24 GiB claim.
- **Retained model PVC:** Helm owns the PVC but marks it with
  `helm.sh/resource-policy: keep`. Uninstalling the release must not discard the
  costly verified artifact. A verified same-name, same-namespace reinstall
  accepted the retained claim through the normal Helm install path. The normal
  server-side dry-run and install are the documented reinstall procedure.

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
