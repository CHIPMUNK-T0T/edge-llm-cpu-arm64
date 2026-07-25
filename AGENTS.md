# Repository instructions

## Purpose

This repository is a technical portfolio for a Cohere Forward Deployed Engineer,
Infrastructure Specialist role. Its priority is to demonstrate how an AI serving
platform is designed, deployed, operated, measured, and recovered under
constraints. It is **not** a production or high-availability product.

The reference environment is one Surface Laptop 7 (Windows 11 ARM64, WSL2
Ubuntu ARM64, 64 GB memory), acting as a small on-premises customer environment.

## Working principles

- Prefer a small, reproducible implementation over an impressive-looking but
  unexplained feature.
- Record assumptions, trade-offs, and measurable evidence with every meaningful
  infrastructure decision.
- Treat Windows on ARM, WSL2, single-node K3s, and ARM64 compatibility as
  first-class constraints; do not hide their limitations.
- Do not claim high availability, production readiness, or security guarantees
  that have not been verified in this single-node lab.
- Keep external access private through Tailscale. Do not expose the inference
  server directly to the public internet.
- The Android app is a minimal end-to-end verification client, not a consumer
  product.

## Documentation requirements

When a change affects architecture, deployment, operation, or a measured result:

1. Update `README.md` if the user-facing setup or project status changes.
2. Update `DESIGN.md` if a component, boundary, or trust assumption changes.
3. Update `PLAN.md` when a milestone is completed or re-scoped.
4. Add an ADR in `docs/adr/` for a durable, non-trivial decision; include the
   context, alternatives, decision, consequences, and validation method.
5. Put benchmark inputs and results in `benchmark/`, and controlled recovery
   experiments in `docs/verification/recovery/`. Do not commit incidental
   development dead-end history.

Do not create an ADR for trivial implementation details. Keep these documents
short, factual, and current.

## Change quality

- Keep Kubernetes manifests, Helm values, scripts, and documentation aligned.
- Make all setup and verification steps copy-pasteable where possible.
- State exact commands, expected observations, and environment assumptions in
  runbooks or experiment notes.
- Never commit model weights, credentials, Tailscale auth keys, or generated
  secrets. Provide `.example` files instead.
- Before declaring a feature complete, perform the documented verification and
  record its result or a known limitation.
