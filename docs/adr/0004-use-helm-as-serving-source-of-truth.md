# ADR-0004: Use Helm as the only serving source of truth

**Status:** accepted
**Date:** 2026-07-25

## Context

Keeping raw serving manifests beside a Helm chart would create two deployment
definitions that could drift. The 17 GB model artifact in the local-path PVC
must also survive lifecycle exercises, including release uninstall and
reinstall.

Packaging the import Job and Deployment unchanged would introduce a clean
install race: the inference container can start before the model Job completes.
It would also make environment changes to an existing Job fail because most Job
spec fields are immutable.

## Options considered

1. Keep raw manifests and add a parallel Helm path.
2. Package only Deployment and Service, leaving model storage and import as an
   external raw-manifest prerequisite.
3. Make one chart authoritative, prepare and verify the model in an init
   container, and retain the model PVC across release deletion.

## Decision

Use option 3. `charts/north-mini-code` is the repository's only serving
definition.

The chart fixes the verified model identity, filename, size, SHA-256, runtime
image digest, one replica, `Recreate` strategy, storage size/class, Service,
security controls, parallel slot count, Jinja support, metrics, and embedded
Web UI. Values expose only the local source path and the experiment controls:
context size, threads, CPU/memory, probes, and termination grace period.

An init container uses the same pinned runtime image and Phase 1 verification
logic. It accepts an already verified PVC artifact or copies the host artifact
to a temporary path, verifies its size and SHA-256, and renames it atomically.
The main container mounts the PVC read-only.

Annotate the PVC with `helm.sh/resource-policy: keep`. Use the release namespace
rather than templating a Namespace object.

## Consequences

- Current repository configuration cannot drift between raw YAML and Helm.
- A clean chart install has no import Job/Deployment startup race.
- Every Pod start verifies the 17 GB artifact before inference, increasing
  startup time; this cost must be measured rather than hidden.
- The host model directory remains a single-node, environment-specific input.
- Release uninstall preserves model bytes but leaves a retained PVC. The
  verified same-name, same-namespace reinstall accepted its existing Helm
  ownership metadata through a normal dry-run and install; no explicit
  ownership takeover was needed.
- Helm cannot provide availability during a `Recreate` rollout on this
  single-node, one-replica lab.
- Static validation alone does not prove lifecycle or serving behavior. Live
  install, upgrade, rollback, uninstall/reinstall, Web UI, health, chat, and
  explicit SSE checks have passed.

## Validation

1. Verify the official Helm Linux ARM64 archive checksum and client version.
2. Run strict lint and reject invalid or unknown values through the schema.
3. Render exactly one Deployment, one Service, and one PVC.
4. Pass K3s server-side dry-run and review the live-object diff.
5. Install the chart and preserve the bound PVC across uninstall and reinstall.
6. Verify init completion, Ready state, Web UI, chat API, controlled upgrade,
   rollback, uninstall/reinstall behavior, and explicit SSE streaming.

All validation steps passed on 2026-07-25. The uninstall/reinstall retained the
same PVC UID, PV binding, model size, and model SHA through the normal install
path. The recreated K3s Service passed UI, health, non-streaming chat, and
explicit multi-frame SSE checks.
