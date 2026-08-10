# Portfolio plan

Each phase has a demonstrable outcome and evidence. A phase is not complete
solely because its components exist.

## Phase 0 — Baseline and Kubernetes foundation

**Status:** complete on 2026-07-21.

- Recorded Windows, WSL2, kernel, ARM64, memory, disk, and network baseline.
- Verified Linux ARM64 Docker execution.
- Installed pinned K3s `v1.36.2+k3s1`; verified a Ready ARM64 node.
- Verified Deployment probes, ClusterIP Service, CoreDNS, and HTTP 200 from an
  ephemeral in-cluster client.
- Verified metrics-server and local-path PVC write/read from a non-root Pod.
- Resolved kubeconfig access with a restricted local operator group.

**Evidence:** [environment inventory](docs/environment-baseline.md),
[ADR-0001](docs/adr/0001-wsl2-single-node-k3s.md),
[network smoke test](docs/verification/k3s-smoke-test-2026-07-21.md), and
[storage smoke test](docs/verification/k3s-storage-smoke-test-2026-07-21.md).

## Phase 1 — In-cluster inference

**Status:** complete on 2026-07-25.

Completed:

- Confirmed upstream Cohere2MoE architecture support from llama.cpp `b9626`
  and the dedicated North Code chat parser from `b9637`.
- Selected official `ghcr.io/ggml-org/llama.cpp:server-b10108` for ARM64,
  pinned to platform digest
  `sha256:06ac0adfef3ce89ce7f080fbe129b4725362a6281ad110c8493fffd6393841c1`.
- Increased the WSL2 memory ceiling to 48 GB and observed 46 GiB inside Linux.
- Accepted North Mini Code Q4_0 as the initial local-serving model.
- Downloaded the pinned 17,521,204,800-byte GGUF outside Git and verified its
  SHA-256 independently.
- Validated the official ARM64 server image on localhost: non-root/read-only
  execution, embedded Web UI, exact official chat template, BOS/EOS/PAD IDs,
  string and typed content, multi-turn memory, stop behavior, and SSE `[DONE]`.
  The EOS/EOG warning remains visible but caused no observed stop failure.
- Imported the verified model into a 24 GiB local-path PVC with a temporary
  non-root Job; byte-size and SHA-256 verification passed in 82 seconds.
- Deployed one official `llama-server` ARM64 replica with resource controls,
  read-only model/root filesystems, and startup/readiness/liveness probes.
- Reached `1/1` Ready with zero restarts, served the embedded Web UI and health
  endpoint to Windows through a localhost-only port-forward, and completed the
  existing 256-token chat smoke input with `finish_reason=stop`.

The Pod remained `1/1` Ready with zero restarts and zero OOM events during the
initial nine-minute observation. This closes the startup gate, not long-running
stability or recovery validation. Recovery timing, forced-failure drills,
monitoring, long-context and concurrency measurements, and external access
remain in their later phases.

**Evidence:** [K3s serving verification](docs/verification/north-mini-code-k3s-serving-2026-07-25.md)
and [deployment smoke result](benchmark/results/north-mini-code-q4-0-k3s-smoke-2026-07-25.json).

## Phase 2 — Helm and lifecycle operations

**Status:** complete on 2026-07-25. Implementation and lifecycle steps 2-1
through 2-5 passed, followed by a cross-phase consistency review.

Completed:

- Established one Helm chart as the only serving definition.
- Exposed only the environment and experiment inputs that need to vary: model
  source path, context size, threads, CPU and memory resources, probes, and
  termination grace period.
- Defined the verified model/runtime combination as the reviewed default while
  allowing only schema-constrained, contract-tested llama.cpp-compatible
  profiles. Kept the one-replica `Recreate` strategy, ClusterIP Service,
  security controls, Jinja support, metrics, and embedded Web UI fixed.
- Pinned and checksum-verified the official Helm 4.2.0 Linux ARM64 client.
- Passed strict chart lint, values schema checks, template rendering, and K3s
  server-side dry-run without changing the live workload.
- Verified init model integrity, `1/1` Ready with zero restarts, ClusterIP and
  Windows-local Web UI/health, and the fixed non-streaming chat smoke input.
- Upgraded context size from 4096 to 3072 through a local values file, verified
  the effective Pod arguments and serving path, and rolled back to 4096.
- Verified the rollback with zero Pod restarts, preserved
  Deployment/Service/PVC identities, and a working UI, health endpoint, and
  fixed chat input.
- Uninstalled the Helm release while retaining the bound model PVC and exact
  model artifact.
- Reinstalled through the normal install path, verified the same PVC UID, PV
  binding, model size, and model SHA, and confirmed that the model was not
  recopied.
- Verified the recreated one-Pod serving path with the embedded UI, health,
  fixed non-streaming chat input, and explicit multi-frame SSE response ending
  in `[DONE]`.
- Disabled automatic ServiceAccount token mounting because neither serving
  container uses the Kubernetes API, then verified zero token volumes/mounts
  and repeated UI, health, chat, and SSE checks.
- Refactored the same three-resource serving unit into explicit injection and
  contract boundaries without adding a long-running Pod: a reviewed
  model/runtime profile, site-specific source path, tested PVC artifact
  preparation, release-specific selectors, and a reusable API contract.
- Recreated only the immutable-selector Deployment through Helm revision 3;
  preserved the Service UID/ClusterIP and PVC UID/PV, reused the verified model
  without copying it, and passed UI, health, metrics, 4xx, chat, and SSE checks.
- Stored the final chart package as Helm revision 4 through a no-op upgrade;
  the Ready Pod UID and zero-restart count were unchanged.
- Applied the reviewed invalid-artifact repair and observable profile contract
  as Helm revision 5. The healthy retained target was verified and reused
  without recopying, and the replacement Pod reached Ready.
- Restricted inference CORS to localhost, disabled CORS credentials, and kept
  operational metrics in an internal inference contract; the separate
  Gateway does not expose them.
- Pinned the Phase 0 nginx and BusyBox validation images by digest and repeated
  their server-side validation on the ARM64 K3s node.

**Static evidence:** [Helm static validation](docs/verification/north-mini-code-helm-static-2026-07-25.md)
and [ADR-0004](docs/adr/0004-use-helm-as-serving-source-of-truth.md).

**Lifecycle evidence:** [controlled upgrade and rollback](docs/verification/north-mini-code-helm-upgrade-rollback-2026-07-25.md).

**Recreation evidence:** [uninstall, retained-PVC reinstall, and SSE](docs/verification/north-mini-code-helm-uninstall-reinstall-sse-2026-07-25.md).

**Contract refactor evidence:** [profile, artifact, selector, and API contracts](docs/verification/north-mini-code-contract-refactor-2026-07-31.md)
and [ADR-0005](docs/adr/0005-use-kubernetes-native-contract-boundaries.md).

**Boundary hardening evidence:** [inference CORS, contract separation, and
foundation image digests](docs/verification/inference-boundary-hardening-2026-07-31.md).

## Phase 3 — Private external access

**Status:** in progress. The local Gateway boundary passed on 2026-08-06;
Tailscale and external-device verification remain.

Completed:

- Deployed a separate digest-pinned Envoy ARM64 Deployment and Helm release.
- Published only the fixed-model Web UI, `GET /health`, and
  `POST /v1/chat/completions`, and `POST /v1/messages`; denied internal metrics,
  runtime, slot, model list, token-count, and model-management paths.
- Kept the UI to message entry, SSE display, and cancellation without model
  switching or generation settings.
- Verified normal streaming completion and cancellation from the Windows
  browser, including restoration of the input and Send control.
- Verified request-size, method, media-type, security-header, deny-by-default,
  OpenAI and Anthropic non-streaming, and both SSE contracts through the
  Gateway Service with `max_tokens: 512`.
- Verified both API formats directly against inference, exact model identity
  across the profile and Gateway, and strict JSON media types. Statically
  confirmed that the UI contains a terminal-event guard for early SSE
  disconnects.
- Configured a fixed public model alias and verified that neither API exposes
  the inference Pod's internal model mount path.
- Verified sanitized 503 responses from a missing inference backend without
  exposing the in-cluster DNS name or connection details.
- Verified a sanitized 504 response from a controlled delayed backend without
  changing or stopping the inference workload.
- Replaced the Windows-local direct inference path with a localhost-only
  port-forward to the Gateway Service.

Remaining:

- Route enrolled external PC and Android devices through Tailscale; never
  expose `llama-server` directly.
- Verify tailnet policy, external browser/API access, SSE, and network loss.
- Build only the minimal Android validation client.

**Evidence:** [Gateway decision](docs/adr/0006-use-envoy-with-a-fixed-client-ui.md)
and [local Gateway verification](docs/verification/inference-gateway-local-2026-08-06.md).

## Phase 4 — Observability and benchmarks

**Status:** pending.

- Collect request/error counts, latency percentiles, TTFT, inter-token latency,
  tokens/sec, CPU, memory, restarts, and OOM events where measurable.
- Compare direct, container, and K3s execution only with controlled settings.
- Commit scripts and raw CSV/JSON; explain limitations in written conclusions.

## Phase 5 — Failure drills and CI/CD

**Status:** pending.

- Rehearse model path, permission, memory/OOM, probe, rollout, WSL restart,
  Windows restart, and Tailscale connectivity scenarios.
- Add ARM64 builds, appropriate multi-architecture checks, Helm lint, manifest
  validation, tests, and API smoke tests in GitHub Actions.

## Definition of done

- Every completed phase has reproducible instructions and evidence in Git.
- Operational layers include measurable success and failure/recovery evidence.
- README and design documents describe actual implementation, not intent.
- The project can be explained as customer constraints, decisions, evidence,
  trade-offs, and explicit limitations.
