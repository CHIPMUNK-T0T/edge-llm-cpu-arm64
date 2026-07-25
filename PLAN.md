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

**Status:** pending.

- Package the current single-replica workload in a Helm chart.
- Expose the environment and experiment inputs that need to vary: model source
  path, context size, threads, CPU and memory resources, probes, and termination
  grace period.
- Keep the verified model identity, quantization, artifact hash, runtime image
  digest, one-replica `Recreate` strategy, ClusterIP Service, security controls,
  Jinja support, metrics, and embedded Web UI fixed in this baseline.
- Run `helm lint`, render the chart, and perform a K3s dry-run before install.
- Exercise install, controlled upgrade, rollback, and uninstall.
- Record one explicit SSE streaming check through the Helm-managed K3s Service.

## Phase 3 — Private external access

**Status:** pending.

- Route enrolled external PC and Android devices through Tailscale and a
  gateway; never expose `llama-server` directly.
- Verify streaming, request policy, unavailable backend, and network-loss cases.
- Keep the Android app to a minimal validation client.

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
