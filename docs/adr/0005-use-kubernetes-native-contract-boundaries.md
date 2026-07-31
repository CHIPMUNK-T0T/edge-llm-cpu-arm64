# ADR-0005: Use Kubernetes-native contract boundaries

**Status:** accepted
**Date:** 2026-07-31

## Context

The verified North Mini Code workload is intentionally fixed, but an FDE must
adapt model artifacts, runtimes, storage, and network entry points to customer
constraints. Making every Helm field arbitrary would weaken reproducibility;
splitting every function into a Pod would add ordering, ownership, and failure
coordination that this single-node lab does not need.

The current model import is an ordered prerequisite of inference and shares the
same retained PVC. The future gateway has a different security boundary,
update cadence, and failure domain from inference.

## Options considered

1. Keep all model and runtime details embedded directly in one Deployment
   template.
2. Split model preparation, inference, gateway, and tests into independent
   long-running services with a generic plugin framework.
3. Keep one cohesive inference Pod, define narrow artifact and HTTP contracts,
   inject reviewed profiles through Helm, and add the gateway as a separate
   release only when its external-access responsibility exists.

## Decision

Use option 3, a small ports-and-adapters design expressed through Kubernetes:

- Helm values and schema form the configuration composition root.
- A reviewed profile binds one GGUF artifact to a digest-pinned official
  llama.cpp ARM64 runtime. A different compatible profile is not called
  verified until it passes the same contracts.
- One release/PVC binds one immutable artifact filename, size, and SHA-256.
  A different artifact uses a different release and retained PVC.
- A testable model-init script receives source, target, expected byte size, and
  expected SHA-256. It atomically places the verified artifact on the retained
  PVC; the runtime mounts that PVC read-only. When an existing target is
  invalid, the script verifies the source before deleting the invalid target,
  avoiding a two-model capacity requirement on the 24 GiB claim.
- A release-specific selector isolates the Deployment and Service from another
  release in the same namespace.
- The ClusterIP Service is the stable inference interface. Consumers know its
  DNS name and named HTTP port, not a Pod name or IP.
- The guaranteed API surface is limited to health, Prometheus metrics, 4xx
  invalid-request handling, non-streaming chat, and SSE ending once in
  `[DONE]`.
- The future gateway is a separate Deployment and Helm release. It depends on
  the inference Service contract and does not run as an inference sidecar.
- Contract tests are invoked when needed from the host, CI, or a temporary
  in-cluster test; they are not a permanent workload.

Do not add a model-provider Deployment, import Job, CRD, Operator, service
mesh, umbrella chart, permanent fake backend, arbitrary command/args values,
or a universal runtime plugin mechanism at this stage.

## Consequences

- The serving workload remains one Deployment, one Pod, one Service, and one
  retained PVC.
- Model and runtime changes have explicit injection points and repeatable
  acceptance tests without claiming every combination is supported.
- Model preparation failure prevents inference startup without cross-Pod
  ordering logic.
- Gateway or inference failure can be diagnosed within separate lifecycle and
  security boundaries.
- A completely different runtime should use an adapter chart that implements
  the same Service/API contract instead of adding conditionals to this chart.
- Adding the release instance to the Deployment selector is an immutable
  Kubernetes change and requires a controlled workload recreation for the
  existing release. The retained PVC remains the artifact boundary.

## Validation

1. Strictly lint and render the chart for two release names; verify distinct
   instance selectors and exactly one Deployment, Service, and PVC per render.
2. Reject unpinned or unsupported runtime image values through the schema.
3. Run the model-artifact fixture for first copy, verified reuse, size/hash
   rejection, partial-file cleanup, atomic promotion, and invalid-target repair
   only after source verification.
4. Verify that canonical model provenance matches chart, download, and
   benchmark consumers.
5. Recreate the live inference workload while retaining the PVC and exact model
   artifact.
6. Verify Pod readiness, model-init reuse, Windows-local UI, health, metrics,
   invalid-request handling, non-streaming chat, and SSE.
7. Reuse the API contract unchanged against the future gateway URL.

Steps 1 through 6 passed on 2026-07-31. Step 7 remains part of the private
external-access milestone.
