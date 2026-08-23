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
| Observability | Prometheus Operator, Prometheus, Grafana, and kube-state-metrics through a scoped Helm wrapper |
| Client | Gateway fixed-model Web UI; Android browser validated on the same Wi-Fi; native Android client optional; external PC planned |

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

The `charts/north-mini-code` chart is the only inference definition. It
manages one Deployment, one ClusterIP Service, and one retained model PVC
through Helm release `north-mini-code`. The separate
`charts/inference-gateway` chart manages the client boundary through Helm
release `inference-gateway`. Helm values are the composition roots, the PVC
mount is the model-artifact interface, and Kubernetes Service DNS is the
network contract between the two releases.

The `charts/edge-llm-monitoring` wrapper composes a pinned public
`kube-prometheus-stack` dependency. Its ServiceMonitor and PodMonitor are the
telemetry contracts for inference and Gateway. Prometheus and Grafana are
single-replica, local-path-backed, and internal-only; Grafana is viewed through
a localhost port-forward.

## Logical architecture

```text
[Android browser] -- Tailscale IP -- [temporary Windows relay; removed] --\
                                                                  +--> [Envoy Gateway Service]
[Windows browser] -------- localhost-only port-forward -----------/       separate release
                                                                               |
                                                                    [Inference Service]
                                                                               |
                                                                       [Inference Pod]
                                                                          /        \
                                                                [model init]  [llama-server]
                                                                     |             |
                                                             [host GGUF] -------> [PVC]

[External PC / different network] -- Tailscale (planned verification)
[Prometheus] <---- [ServiceMonitor: inference /metrics]
       ^------<--- [PodMonitor: Gateway admin metrics]
       +----------> [Grafana; localhost operator access]
```

## Boundaries and responsibilities

| Boundary | Responsibility | Not responsible for |
| --- | --- | --- |
| Tailscale | Private, encrypted connectivity between enrolled devices | Application authentication or request policy |
| Gateway / ingress | Only supported external entry point; client contract, request policy, and telemetry | Direct model inference or exposing operational metrics |
| Inference Service | Stable in-cluster DNS/port contract and routing to Ready inference Pods | Model loading, client access policy, or external exposure |
| K3s | Scheduling and lifecycle of in-cluster workloads | Multi-node availability |
| Helm chart | Declarative serving configuration, release history, upgrade, and rollback | Preserving availability on this single node |
| Model init | Place an exact size/SHA-verified GGUF at the PVC contract path before inference starts | Serving HTTP requests |
| `llama-server` | OpenAI- and Anthropic-compatible inference and streaming | Public exposure or durable authorization |
| PVC | Model storage persistence within the lab | Distributed storage durability |
| Browser client | End-to-end health, streaming, and cancellation checks | Product-grade UX or distribution |
| Monitoring | Collect and retain workload, request, error, latency, restart, and inference metrics | Public telemetry, Windows host telemetry, alert delivery, or high availability |

## Design constraints and trade-offs

- **Single replica:** model memory makes one replica the expected configuration
  on a 64 GB host. This makes availability a limitation to document, not a
  feature to emulate.
- **Recovery contract:** K3s recreates deleted Pods, while Helm revision history
  is the recovery path for an invalid site value. Neither mechanism preserves
  availability with one replica. Measured recovery must distinguish K3s API,
  Pod Ready, and Gateway health; model loading, not Gateway startup, dominates
  inference and WSL restart time.
- **Memory envelope:** cap the model workload at 40 GiB within the 48 GB WSL2
  ceiling. Any swap growth during inference is a failed performance result,
  even if the request eventually succeeds.
- **WSL2 + K3s:** this yields Linux-native container and Kubernetes semantics
  while retaining Windows on ARM as the host constraint. Startup, networking,
  and filesystem behavior must be verified rather than assumed.
- **Gateway before inference:** prevents the inference endpoint from becoming
  the external network boundary, and creates one place for client request
  controls. Inference metrics remain on the internal operational contract.
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
- **Published monitoring package:** wrap pinned `kube-prometheus-stack` instead
  of maintaining four related systems independently. Disable Alertmanager,
  default rules, unused K3s control-plane monitors, and admission hooks until a
  measured requirement needs them.
- **WSL2 monitoring boundary:** the upstream node-exporter host-root mount
  requires propagation that WSL2 does not provide for `/`. Do not leave its
  DaemonSet failing. Use kubelet/cAdvisor for workload CPU and memory and
  kube-state-metrics for restart and object state. Windows host telemetry is
  explicitly outside this milestone.
- **Internal telemetry:** Prometheus and Grafana remain ClusterIP-only. Grafana
  anonymous Viewer access relies on the documented localhost-only port-forward.
- **Validated tailnet path:** an enrolled Android browser reached only the
  Gateway through a temporary Windows portproxy bound to the Windows Tailscale
  IP. Its inbound Firewall rule allowed only that Android Tailscale IP. HTTP
  lacked browser-level TLS, but the device-to-device path used Tailscale's
  encrypted overlay. Both devices were on the same Wi-Fi, so this result does
  not prove access across different networks. The relay is a verification
  fixture, not a durable ingress design.
- **Tailscale HTTPS limitation:** Windows Tailscale Serve accepted the intended
  localhost proxy configuration, but TLS handshakes did not complete because
  repeated Let's Encrypt ACME orders became `invalid`. The issue was isolated
  from K3s, Gateway health, and Android peer connectivity. No HTTPS or
  production security claim is made, and the failed Serve configuration is not
  part of the implementation.
- **GGUF quantization:** reduces RAM requirements at a quality/performance
  trade-off. The chosen quantization is an experimental result, not a default.
- **Upstream runtime package:** use the official versioned ARM64 server image
  instead of maintaining a custom build. Pin the platform digest and validate
  the model, Web UI, security context, and API behavior on this host.
- **Gateway-owned Web UI:** expose a small same-origin UI from Envoy rather
  than proxying the embedded upstream UI. It uses the fixed served model and
  offers no model switch or generation settings. This keeps model metadata,
  slots, metrics, properties, and model-management routes outside the client
  contract.
- **Windows-local validation:** bind `kubectl port-forward` only to
  `127.0.0.1` and verify the K3s-hosted Gateway from the Windows browser.
  This is a temporary operator path, not the final Tailscale route. Restart a
  long-running port-forward after its target Pod is replaced.
- **One Helm source per workload:** do not retain raw serving manifests beside
  either chart. The inference and Gateway charts are their respective
  deployment definitions, avoiding drift from parallel deployment paths.
- **Model preparation in the Pod lifecycle:** an init container executes a
  separately testable script that copies the profile-selected host GGUF only
  when the PVC does not contain the verified artifact and checks its exact size
  and SHA-256 before inference starts. Its contract is four inputs
  (`SOURCE_FILE`, `TARGET_FILE`, `EXPECTED_SIZE`, and
  `EXPECTED_SHA256`) and one verified file at the PVC path. This avoids an
  import Job/Deployment race at the cost of verifying the file on each start.
- **Contract scope:** the internal inference contract guarantees health,
  localhost-only browser origins, Prometheus metrics, 4xx invalid-request
  handling, OpenAI-compatible `/v1/chat/completions` and Anthropic-compatible
  `/v1/messages`, in both non-streaming and SSE modes. OpenAI SSE ends once
  in `[DONE]`; Anthropic SSE ends in `message_stop`. The
  external Gateway contract guarantees its fixed UI, public health,
  OpenAI-compatible `/v1/chat/completions`, Anthropic-compatible `/v1/messages`,
  both non-streaming and SSE modes, deny-by-default routing, and sanitized
  Envoy-generated missing-upstream and timeout replies. Both formats share the same
  inference process and reviewed
  `max_tokens: 512` client setting. The runtime returns a fixed model alias
  instead of its internal mount path. The Gateway does not expose inference
  metrics or `/v1/messages/count_tokens`. Neither contract claims the complete
  OpenAI or Anthropic API surface.
- **Browser conversation boundary:** the UI keeps conversation context only in
  browser memory. It commits a user/assistant turn to the next request only
  after the terminal SSE event is received. Canceled or failed turns remain
  visible for operator feedback but are not sent as subsequent context.
- **Gateway administration boundary:** Envoy admin port 9901 is omitted from
  the Service but binds the Pod interface so kubelet can run probes and the
  monitoring-namespace Prometheus can scrape it through a PodMonitor. It is
  reachable inside the cluster Pod network; no public exposure or NetworkPolicy
  isolation is claimed at this stage.
- **Browser-origin boundary:** the ClusterIP-only inference server restricts
  CORS to localhost and disables CORS credentials. Gateway browser calls are
  same-origin, so the Gateway does not add broad CORS. It has no application
  API key; future remote clients terminate at the Gateway through the private
  Tailscale path.
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
