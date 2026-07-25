# K3s storage smoke test — 2026-07-21

## Objective

Verify dynamic local-path provisioning and non-root Pod read/write access before
using a PVC for model artifacts.

## Method

Applied `kubernetes/storage-smoke-test.yaml`. It requested a 32 MiB
ReadWriteOnce PVC from the `local-path` StorageClass and ran a non-root BusyBox
Job that wrote a known value and read it back from the mounted filesystem.

## Result

**Passed.** The Job completed and emitted:

```text
PVC write/read verification: PASS (edge-llm-storage-ok)
```

The generated PersistentVolume was `Bound`, used the `local-path` StorageClass,
and had a `Delete` reclaim policy. The generated PV name is intentionally not
treated as a stable identifier.

## Interpretation and limitation

This proves dynamic provisioning and Pod-level filesystem access in the current
single-node lab. It does not prove disk redundancy, backup, portability to
another node, or survival of WSL distribution loss. A `Delete` reclaim policy
also means deleting the claim can delete its backing data; model acquisition
must therefore be reproducible and checksummed.
