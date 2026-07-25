# ARM64 container runtime verification — 2026-07-21

## Objective

Confirm that the reference Windows on ARM / WSL2 environment can execute a
Linux ARM64 container before installing Kubernetes or an LLM runtime.

## Command

```powershell
wsl.exe -d Ubuntu-24.04 -- docker run --rm --platform linux/arm64 alpine:3.21 uname -m
```

## Result

**Passed.** Docker downloaded `alpine:3.21` and the container reported
`aarch64`.

## Interpretation

This verifies the container runtime can execute a minimal `linux/arm64` image.
It does not by itself prove that K3s or an LLM-serving runtime will work.

## Follow-up

K3s was subsequently installed and its ARM64 node, Pod scheduling, probes,
cluster DNS, Service routing, metrics, and local-path storage were verified.
See `k3s-smoke-test-2026-07-21.md` and
`k3s-storage-smoke-test-2026-07-21.md` in this directory.
