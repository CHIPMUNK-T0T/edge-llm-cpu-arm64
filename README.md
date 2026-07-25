# Edge LLM Platform on ARM64

Technical portfolio project for an AI-serving platform in a constrained,
single-node, on-premises-style environment.

The project uses a Surface Laptop 7 (Windows on ARM), WSL2 Ubuntu ARM64, and
K3s to serve a Cohere public model in GGUF format through `llama-server`. A
private Tailscale network will enable a minimal Android client and external PCs
to use the service through a gateway. The focus is the engineering process:
architecture, deployment, observability, benchmarks, failure recovery, and
documented trade-offs.

> Status (2026-07-25): Phase 0 passed. K3s, ARM64 scheduling, ClusterIP/DNS,
> metrics, and local-path PVC read/write are verified. Phase 1 passed:
> North Mini Code Q4_0 is downloaded, verified, and accepted as the initial
> serving model. Upstream llama.cpp explicitly supports its Cohere2MoE
> architecture and North Code chat format. The official versioned ARM64
> `llama-server` image is selected with its platform digest. Local validation
> passed for Web UI, exact official chat template, tokenizer IDs, single-turn,
> typed-content, multi-turn, stop, and streaming behavior. One K3s inference
> Pod now loads the model from a verified PVC, reaches Ready with zero restarts,
> and serves its embedded Web UI and chat API to Windows through a
> localhost-only port-forward.

## Demonstrated so far

- ARM64 LLM serving with `llama.cpp` / `llama-server`
- Single-node Kubernetes operations with K3s
- Pinned model provenance, runtime digest, and reproducible model placement
- Windows-local Web UI and API access to the K3s-hosted workload

## Planned portfolio scope

- Helm packaging, upgrades, and rollback
- Private external access through Tailscale and a gateway
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
   Gateway / reverse proxy
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

## Repository map

- `config/` — host/K3s configuration under version control
- `scripts/` — reproducible installation and model-download entry points
- `kubernetes/` — manifests and infrastructure validation workloads
- `charts/` — Helm chart (planned)
- `gateway/` — reverse-proxy and access policy (planned)
- `monitoring/` — metrics and dashboards (planned)
- `benchmark/` — repeatable inputs and raw results
- `android-app/` — minimal external validation client (planned)
- `docs/adr/` — durable architecture decision records

## Evidence standard

Every milestone must link to the configuration used, a verification command or
test, measured results where applicable, known limitations, and recovery
guidance for observed failures. A successful demo alone is not sufficient.
