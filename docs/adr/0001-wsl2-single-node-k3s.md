# ADR-0001: Use single-node K3s inside WSL2 as the lab orchestrator

**Status:** accepted

**Date:** 2026-07-21

## Context

The portfolio must demonstrate LLM serving and Kubernetes operations on a
Surface Laptop 7 running Windows on ARM. The project deliberately represents a
constrained, single-node, on-premises-style customer environment. It needs
Linux container and Kubernetes behavior while keeping the Windows on ARM host
constraint visible.

The initial baseline confirms Ubuntu 24.04 on WSL2, ARM64 Linux, systemd,
cgroup v2, and an ARM64 Docker daemon. It initially showed 31 GiB visible
memory despite the host having about 63.5 GiB. On 2026-07-22, the configured
WSL2 ceiling was raised to 48 GB and Linux observed 46 GiB.

## Options considered

1. Run the inference runtime directly on Windows ARM64 without Kubernetes.
2. Run Docker containers in WSL2 without Kubernetes.
3. Run a single-node K3s cluster in WSL2.
4. Use a managed or remote Kubernetes cluster.

## Decision

Use a single-node K3s cluster in WSL2 as the primary lab orchestrator. Keep a
direct or container-only run only as a comparison baseline where it is feasible
and clearly labelled.

## Consequences

- The project can demonstrate Deployment, Service, PVC, probes, resource
  controls, Helm lifecycle, logs, observability, and recovery drills using
  Linux/ARM64 semantics.
- WSL2 introduces an explicit memory, filesystem, lifecycle, and NAT-networking
  boundary that must be measured and documented.
- A one-node cluster cannot demonstrate node failure tolerance, distributed
  storage, or production high availability; these are explicit non-goals.
- Model serving begins with one replica because the host is a single failure
  domain and the workload ceiling is 40 GiB. Replication is an experiment, not
  an availability claim.

## Validation

1. Install K3s and verify a Ready ARM64 node.
2. Deploy a small non-LLM ARM64 Pod and access it through a Kubernetes Service.
3. Record cluster startup/restart behavior under WSL2.
4. Later, compare the documented inference metrics with a direct or
   container-only run when that comparison is feasible.
