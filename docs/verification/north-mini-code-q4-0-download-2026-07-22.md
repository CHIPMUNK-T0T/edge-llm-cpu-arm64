# North Mini Code Q4_0 download verification — 2026-07-22

## Result

**Passed.** The pinned third-party GGUF was downloaded outside Git and matched
both the expected byte size and SHA-256. This verifies the exact bytes used by
this lab; it does not make the conversion an official Cohere artifact.

| Item | Verified value |
| --- | --- |
| GGUF repository | `bartowski/North-Mini-Code-1.0-GGUF` |
| Repository revision | `6ff6563002170723a6f7a672bf4c99775be6c0dd` |
| Filename | `North-Mini-Code-1.0-Q4_0.gguf` |
| Size | 17,521,204,800 bytes |
| SHA-256 | `e4803e44e2b97269deb3b33b1ea8d4309d06773ca5f07684f876bd8f751f4f86` |
| Authentication | none required for this public artifact |
| Git handling | `models/` and `*.gguf` are ignored |

## Reproduction

```bash
bash scripts/download-north-mini-code-q4-0.sh

stat --format='size_bytes=%s' \
  models/north-mini-code/North-Mini-Code-1.0-Q4_0.gguf
sha256sum models/north-mini-code/North-Mini-Code-1.0-Q4_0.gguf
```

Expected observations:

```text
size_bytes=17521204800
e4803e44e2b97269deb3b33b1ea8d4309d06773ca5f07684f876bd8f751f4f86
```

The download script uses a `.part` filename, supports HTTP resume, verifies the
size and hash before renaming, and refuses to overwrite an invalid final file.

## Scope

This record closes artifact acquisition and byte-identity verification only.
It does not establish model quality, runtime compatibility, memory use, chat
template behavior, or K3s operation; those require separate serving evidence.
