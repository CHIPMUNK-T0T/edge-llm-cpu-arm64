# Edge LLM Platform on ARM64

Technical portfolio project for an AI-serving platform in a constrained,
single-node, on-premises-style environment.

The project uses a Surface Laptop 7 (Windows on ARM), WSL2 Ubuntu ARM64, and
K3s to serve a Cohere public model in GGUF format through `llama-server`. A
private Tailscale tailnet was used to validate an Android browser path to the
Gateway on the same Wi-Fi. A persistent, different-network route remains. The
focus is the engineering process:
architecture, deployment, observability, benchmarks, failure recovery, and
documented trade-offs.

> Status (2026-08-11): Phases 0, 1, and 2 passed. The ARM64 K3s foundation, pinned
> North Mini Code Q4_0 artifact, official `llama-server` runtime, one Ready
> inference Pod, Windows-local Web UI, and chat API are verified. Helm is the
> only serving definition; static checks, controlled upgrade, rollback,
> uninstall, and normal reinstall all succeeded. The reinstall retained the
> existing model PVC and exact model SHA without a 17 GB recopy. UI, health,
> metrics, error handling, chat, and explicit SSE checks pass through the K3s
> Service. Chart `0.2.2` separates the reviewed model/runtime profile,
> site-specific placement, PVC artifact contract, and Service/API contract.
> A separate Envoy Gateway chart `0.1.2` now provides the Windows-local fixed-model UI,
> public health, and OpenAI- and Anthropic-compatible chat/SSE contracts while
> denying operational and
> model-management routes. An enrolled Android browser has also passed UI,
> health, chat, and cancellation checks through a temporary, device-restricted
> Windows tailnet relay on the same Wi-Fi. This verifies the Android client and
> tailnet path, but not access from a different network. Tailscale Serve HTTPS
> remains blocked by an ACME certificate provisioning failure.

## Demonstrated so far

- ARM64 LLM serving with `llama.cpp` / `llama-server`
- Single-node Kubernetes operations with K3s
- Pinned model provenance, runtime digest, and reproducible model placement
- Windows-local Web UI and API access to the K3s-hosted workload
- Statically validated Helm packaging without changing the live workload
- Controlled Helm values upgrade and rollback with workload verification
- Helm uninstall and normal reinstall while retaining the exact model artifact
- Explicit SSE streaming through the Helm-managed K3s Service
- Schema-constrained model/runtime profile injection without arbitrary
  container or command overrides
- Reusable chart, model-artifact, and internal inference contract tests covering
  health, browser origins, metrics, error handling, chat, and SSE
- Localhost-restricted CORS at the ClusterIP inference backend; external-client
  policy remains a gateway responsibility
- Separate digest-pinned Envoy Gateway Deployment and Helm release
- Fixed-model browser UI without model or generation-setting controls
- Windows-browser verification of normal SSE completion and user cancellation
- Completed UI turns are retained for the next request; canceled or failed
  turns remain visible but are excluded from subsequent request context
- Allowlisted health, OpenAI chat/SSE, and Anthropic Messages/SSE client surface
  with internal endpoints denied
- Direct inference and Gateway contracts for both API formats, strict JSON
  media types, a 1 MiB limit on both public chat routes, fixed model identity,
  and terminal SSE events
- Fixed public model alias without exposing the inference Pod mount path
- Sanitized Envoy-generated missing-upstream and timeout replies without
  internal connection details
- Android browser access to the Gateway during a temporary Windows tailnet
  relay test, including health, chat, and cancellation, with the Firewall rule
  restricted to that enrolled Android device

## Planned portfolio scope

- Private access from a different network through Tailscale
- LLM performance and operational observability
- Failure diagnosis and recovery under realistic resource constraints
- Reproducible infrastructure, benchmarks, and documentation

## Explicit non-goals

- Production high availability or multi-node scaling
- Public internet exposure
- A feature-complete Android product
- Claims of production-grade security beyond tested lab controls

## Target architecture

```text
Android client or external PC
            |
       Tailscale tailnet
            |
   Envoy Gateway + fixed Web UI
            |
       K3s Service
            |
    llama-server Pod + PVC
            |
   Cohere public GGUF model
```

See [DESIGN.md](DESIGN.md) for boundaries and trade-offs,
[PLAN.md](PLAN.md) for milestone gates, and
[docs/environment-baseline.md](docs/environment-baseline.md) for the measured
host and WSL2 baseline.

## Verified evidence

- [K3s infrastructure smoke test](docs/verification/k3s-smoke-test-2026-07-21.md)
- [K3s storage smoke test](docs/verification/k3s-storage-smoke-test-2026-07-21.md)
- [Kubeconfig permission incident](docs/troubleshooting/0001-kubeconfig-permission.md)
- [North Mini Code Q4_0 feasibility decision](docs/adr/0002-north-mini-code-q4-0-feasibility.md)
- [North Mini Code Q4_0 download verification](docs/verification/north-mini-code-q4-0-download-2026-07-22.md)
- [Official llama-server ARM64 validation](docs/verification/official-llama-server-arm64-2026-07-24.md)
- [Official ARM64 runtime decision](docs/adr/0003-use-official-llama-server-arm64-image.md)
- [K3s inference and Windows-local Web UI verification](docs/verification/north-mini-code-k3s-serving-2026-07-25.md)
- [Helm packaging and PVC lifecycle decision](docs/adr/0004-use-helm-as-serving-source-of-truth.md)
- [Helm static validation](docs/verification/north-mini-code-helm-static-2026-07-25.md)
- [Helm controlled upgrade and rollback](docs/verification/north-mini-code-helm-upgrade-rollback-2026-07-25.md)
- [Helm uninstall, retained-PVC reinstall, and SSE verification](docs/verification/north-mini-code-helm-uninstall-reinstall-sse-2026-07-25.md)
- [Kubernetes-native contract refactor verification](docs/verification/north-mini-code-contract-refactor-2026-07-31.md)
- [Inference boundary and foundation image verification](docs/verification/inference-boundary-hardening-2026-07-31.md)
- [Kubernetes-native contract boundary decision](docs/adr/0005-use-kubernetes-native-contract-boundaries.md)
- [Envoy and fixed client UI decision](docs/adr/0006-use-envoy-with-a-fixed-client-ui.md)
- [Local inference Gateway verification](docs/verification/inference-gateway-local-2026-08-06.md)
- [Android tailnet same-Wi-Fi verification](docs/verification/tailscale-android-same-wifi-2026-08-11.md)

## Repository map

- `config/` — host/K3s configuration under version control
- `scripts/` — reproducible K3s, Helm, and model-download entry points
- `kubernetes/` — foundation and storage validation workloads
- `charts/` — Helm sources for the inference and Gateway workloads
- `monitoring/` — metrics and dashboards (planned)
- `benchmark/` — repeatable inputs and raw results
- `tests/` — reusable chart, artifact, and inference API contracts
- `android-app/` — optional minimal native API client (not started)
- `docs/adr/` — durable architecture decision records

## Evidence standard

Every milestone must link to the configuration used, a verification command or
test, measured results where applicable, known limitations, and recovery
guidance for observed failures. A successful demo alone is not sufficient.
