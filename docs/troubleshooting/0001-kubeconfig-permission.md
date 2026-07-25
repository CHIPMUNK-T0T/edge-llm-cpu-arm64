# K3s kubeconfig permission denied

**Observed:** 2026-07-21

**Status:** resolved

## Symptom

K3s installed successfully and its root-run readiness check passed, but the
normal WSL user could not run `k3s kubectl`:

```text
Unable to read /etc/rancher/k3s/k3s.yaml
open /etc/rancher/k3s/k3s.yaml: permission denied
```

## Cause

The default K3s kubeconfig is owned by root and contains cluster-admin
credentials. The installing root process could read it, while the operator user
could not.

## Resolution

Create a local `k3s` operator group, add the intended WSL operator to it, and
configure K3s with:

```yaml
write-kubeconfig-mode: "0640"
write-kubeconfig-group: k3s
```

Re-run `scripts/install-k3s.sh` as root so K3s applies the Git-managed
configuration. A new WSL process is required to pick up the added group.

## Trade-off and residual risk

This avoids making cluster-admin credentials readable by every local account,
as mode `0644` would. Membership in `k3s` still grants access to a
cluster-admin kubeconfig; the group must remain restricted. A production
environment should issue scoped identities rather than share this administrative
kubeconfig.
