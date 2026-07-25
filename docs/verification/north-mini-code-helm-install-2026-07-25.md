# North Mini Code Helm install verification — 2026-07-25

## Scope and result

**Passed the Phase 2 Helm ownership migration and install gate.**

The existing Phase 1 Deployment, ClusterIP Service, and bound model PVC were
transferred in place to Helm release `north-mini-code`. Model data, resource
UIDs, the persistent volume binding, and the Service ClusterIP were preserved.
The chart then passed init verification, Ready, embedded Web UI, health, and
the fixed non-streaming chat smoke input.

This result does not claim controlled upgrade, rollback, uninstall/reinstall,
or explicit SSE behavior. Those remain separate Phase 2 gates.

## Preflight

Before install:

- no Helm release existed in namespace `edge-llm`;
- Deployment was `1/1` Ready and the Service health endpoint was healthy;
- the PVC was `Bound`, 24 GiB, and contained the expected
  17,521,204,800-byte GGUF;
- chart rendering passed K3s server-side dry-run;
- the Phase 1 serving manifest from Git history passed recovery dry-run.

## Migration command

```bash
helm install north-mini-code charts/north-mini-code \
  --namespace edge-llm \
  -f .north-mini-code-values.yaml \
  --kubeconfig /etc/rancher/k3s/k3s.yaml \
  --take-ownership \
  --wait=watcher \
  --timeout 15m
```

Observed result:

```text
STATUS: deployed
REVISION: 1
DESCRIPTION: Install complete
elapsed_seconds=54.75
```

## Identity and data preservation

| Resource | Before UID | After UID | Result |
| --- | --- | --- | --- |
| Deployment `north-mini-code` | `48a35e9e-3d6e-4a56-979c-2a234eaef6c6` | same | preserved |
| Service `north-mini-code` | `b2fb521f-d42a-4d0f-8c3c-6c4d3bfbfad2` | same | preserved |
| PVC `north-mini-code-model` | `7e9dca97-c302-40bf-8a5f-13862a28d5c5` | same | preserved and Bound |

The Service retained ClusterIP `10.43.245.211`. All three resources received
release name `north-mini-code`, release namespace `edge-llm`, and
`app.kubernetes.io/managed-by=Helm` metadata.

The completed Phase 1 `import-north-mini-code-model` Job was deleted only after
the Helm-managed workload passed all checks. The PVC and model were not deleted.

## Startup observations

| Event | UTC timestamp or duration |
| --- | --- |
| Pod created | `2026-07-25T07:06:32Z` |
| init started | `2026-07-25T07:06:33Z` |
| init completed | `2026-07-25T07:06:53Z` |
| llama-server started | `2026-07-25T07:06:54Z` |
| Pod Ready | `2026-07-25T07:07:24Z` |
| model load reported by server | 26.19 seconds |

The init container exited 0 with:

```text
Model already present and verified.
```

The serving container reached `1/1` Ready with zero restarts.

## UI, health, and API regression

The Windows-local path used a temporary localhost-only port-forward:

```bash
kubectl port-forward --address=127.0.0.1 \
  --namespace edge-llm \
  service/north-mini-code 18080:8080
curl --compressed --fail --output /dev/null http://localhost:18080/
curl --fail http://localhost:18080/health
```

The fixed chat input was sent through the K3s Service:

```bash
jq -c '.requests[0].body' \
  benchmark/inputs/north-mini-code-q4-0-k3s-smoke.json |
  curl --fail \
    --header 'Content-Type: application/json' \
    --data-binary @- \
    http://10.43.245.211:8080/v1/chat/completions
```

| Check | Result |
| --- | --- |
| ClusterIP embedded UI | HTTP 200, `text/html; charset=utf-8`, 1,302 bytes |
| ClusterIP health | `{"status":"ok"}` |
| Windows `localhost:18080` embedded UI | HTTP 200, same content type and size |
| Windows `localhost:18080` health | `{"status":"ok"}` |
| Fixed chat smoke input | HTTP 200 in 20.66 seconds |
| Chat completion | correct `add(a, b)` function; `finish_reason=stop` |
| Usage | 135 prompt tokens, 113 completion tokens |

The embedded UI asset is gzip encoded. A generic curl request without gzip
support receives HTTP 415; `curl --compressed` and normal browsers succeed.
This is a client capability requirement, not a failed server health check.

## Remaining Phase 2 work

- perform one controlled values change through `helm upgrade`;
- verify the changed value and workload behavior;
- roll back and prove the original value and behavior return;
- verify uninstall/reinstall with the retained PVC;
- record explicit SSE streaming through the Helm-managed Service.
