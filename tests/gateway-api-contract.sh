#!/bin/sh

set -eu

base_url="${1:-${GATEWAY_BASE_URL:-}}"
model_id="${GATEWAY_MODEL_ID:-}"
connect_timeout="${GATEWAY_CONNECT_TIMEOUT_SECONDS:-5}"
request_timeout="${GATEWAY_REQUEST_TIMEOUT_SECONDS:-180}"

if [ -z "$base_url" ]; then
  printf 'usage: %s BASE_URL\n' "$0" >&2
  printf 'or set GATEWAY_BASE_URL; for example http://localhost:18080\n' >&2
  exit 2
fi

case "$base_url" in
  http://*|https://*) ;;
  *)
    printf 'BASE_URL must start with http:// or https://: %s\n' "$base_url" >&2
    exit 2
    ;;
esac

base_url="${base_url%/}"
work_dir="$(mktemp -d)"
trap 'rm -rf -- "$work_dir"' EXIT HUP INT TERM

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  exit 1
}

status_for() {
  curl --silent --show-error \
    --connect-timeout "$connect_timeout" \
    --max-time "$request_timeout" \
    --output "$2" \
    --write-out '%{http_code}' \
    "$1"
}

printf '1/11 Web UI and browser security headers\n'
ui_status="$(curl --silent --show-error \
  --connect-timeout "$connect_timeout" \
  --max-time "$request_timeout" \
  --dump-header "$work_dir/ui-headers.txt" \
  --output "$work_dir/index.html" \
  --write-out '%{http_code}' \
  "$base_url/")"
[ "$ui_status" = 200 ] || fail "Web UI returned HTTP $ui_status"
grep -q '<title>Edge LLM Chat</title>' "$work_dir/index.html" || \
  fail 'Gateway-owned Web UI was not returned'
tr -d '\r' <"$work_dir/ui-headers.txt" >"$work_dir/ui-headers-normalized.txt"
for header in content-security-policy x-content-type-options x-frame-options referrer-policy; do
  grep -Eiq "^$header:" "$work_dir/ui-headers-normalized.txt" || \
    fail "security header is missing: $header"
done
for asset in app.js style.css; do
  [ "$(status_for "$base_url/$asset" "$work_dir/$asset")" = 200 ] || \
    fail "UI asset is unavailable: $asset"
  [ -s "$work_dir/$asset" ] || fail "UI asset is empty: $asset"
done

ui_model_id="$(sed -n 's/.*<meta name="edge-llm-model" content="\([^"]*\)">.*/\1/p' \
  "$work_dir/index.html")"
[ -n "$ui_model_id" ] || fail 'fixed model identity is missing from the Web UI'
if [ -n "$model_id" ] && [ "$model_id" != "$ui_model_id" ]; then
  fail 'GATEWAY_MODEL_ID does not match the Web UI model identity'
fi
model_id="${model_id:-$ui_model_id}"

printf '2/11 public health contract\n'
[ "$(status_for "$base_url/health" "$work_dir/health.json")" = 200 ] || \
  fail 'health endpoint did not return HTTP 200'
python3 - "$work_dir/health.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as response:
    payload = json.load(response)
if payload.get("status") != "ok":
    raise SystemExit("health response does not report status ok")
PY

printf '3/11 internal endpoint isolation\n'
for path in metrics props slots v1/models models/load v1/messages/count_tokens; do
  for method in GET POST; do
    status="$(curl --silent --show-error \
      --connect-timeout "$connect_timeout" \
      --max-time "$request_timeout" \
      --request "$method" \
      --output "$work_dir/internal-response.json" \
      --write-out '%{http_code}' \
      "$base_url/$path")"
    [ "$status" = 404 ] || \
      fail "$method on internal endpoint /$path returned HTTP $status"
  done
done

printf '4/11 method and media-type policy\n'
for endpoint in v1/chat/completions v1/messages; do
  [ "$(status_for "$base_url/$endpoint" "$work_dir/method.json")" = 405 ] || \
    fail "GET on /$endpoint did not return HTTP 405"
  media_status="$(curl --silent --show-error \
    --connect-timeout "$connect_timeout" \
    --max-time "$request_timeout" \
    --header 'Content-Type: text/plain' \
    --data-binary '{}' \
    --output "$work_dir/media.json" \
    --write-out '%{http_code}' \
    "$base_url/$endpoint")"
  [ "$media_status" = 415 ] || \
    fail "non-JSON request to /$endpoint returned HTTP $media_status"
  near_miss_status="$(curl --silent --show-error \
    --connect-timeout "$connect_timeout" \
    --max-time "$request_timeout" \
    --header 'Content-Type: application/jsonp' \
    --data-binary '{}' \
    --output "$work_dir/media-near-miss.json" \
    --write-out '%{http_code}' \
    "$base_url/$endpoint")"
  [ "$near_miss_status" = 415 ] || \
    fail "JSON prefix near miss on /$endpoint returned HTTP $near_miss_status"
  charset_status="$(curl --silent --show-error \
    --connect-timeout "$connect_timeout" \
    --max-time "$request_timeout" \
    --header 'Content-Type: Application/JSON; charset=UTF-8' \
    --data-binary '{}' \
    --output "$work_dir/media-charset.json" \
    --write-out '%{http_code}' \
    "$base_url/$endpoint")"
  [ "$charset_status" != 415 ] || \
    fail "valid JSON media type with charset was rejected on /$endpoint"
done

cat >"$work_dir/non-stream-request.json" <<EOF
{"model":"$model_id","messages":[{"role":"user","content":"Reply with exactly: hello"}],"max_tokens":512,"temperature":0,"stream":false}
EOF

printf '5/11 OpenAI-compatible non-streaming chat contract\n'
curl --fail --silent --show-error \
  --connect-timeout "$connect_timeout" \
  --max-time "$request_timeout" \
  --header 'Content-Type: application/json' \
  --data-binary "@$work_dir/non-stream-request.json" \
  --output "$work_dir/non-stream-response.json" \
  "$base_url/v1/chat/completions"
python3 - "$work_dir/non-stream-response.json" "$model_id" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as response:
    payload = json.load(response)
choices = payload.get("choices")
if not isinstance(choices, list) or not choices:
    raise SystemExit("non-streaming response has no choices")
message = choices[0].get("message")
if not isinstance(message, dict):
    raise SystemExit("non-streaming response has no message object")
if not isinstance(message.get("content"), str) or not message["content"].strip():
    raise SystemExit("non-streaming response content is empty")
model = payload.get("model")
if model != sys.argv[2]:
    raise SystemExit(f"OpenAI response model alias is unexpected: {model!r}")
PY

cat >"$work_dir/stream-request.json" <<EOF
{"model":"$model_id","messages":[{"role":"user","content":"Reply with exactly: one two three"}],"max_tokens":512,"temperature":0,"stream":true}
EOF

printf '6/11 OpenAI-compatible SSE streaming contract\n'
curl --fail --silent --show-error --no-buffer \
  --connect-timeout "$connect_timeout" \
  --max-time "$request_timeout" \
  --dump-header "$work_dir/stream-headers.txt" \
  --header 'Accept: text/event-stream' \
  --header 'Content-Type: application/json' \
  --data-binary "@$work_dir/stream-request.json" \
  --output "$work_dir/stream-body.txt" \
  "$base_url/v1/chat/completions"
tr -d '\r' <"$work_dir/stream-headers.txt" >"$work_dir/stream-headers-normalized.txt"
grep -Eiq '^content-type:[[:space:]]*text/event-stream([[:space:]]*;|[[:space:]]*$)' \
  "$work_dir/stream-headers-normalized.txt" || \
  fail 'SSE content type is not text/event-stream'
python3 - "$work_dir/stream-body.txt" "$model_id" <<'PY'
import json
import sys

frames = []
done = 0
events = []
with open(sys.argv[1], encoding="utf-8") as response:
    for raw_line in response:
        line = raw_line.rstrip("\r\n")
        if not line.startswith("data: "):
            continue
        data = line[6:]
        events.append(data)
        if data == "[DONE]":
            done += 1
        else:
            frames.append(json.loads(data))
if len(frames) < 2:
    raise SystemExit(f"SSE returned fewer than two JSON frames: {len(frames)}")
if done != 1 or not events or events[-1] != "[DONE]":
    raise SystemExit("SSE terminal event is invalid")
unexpected_models = sorted(
    {repr(frame.get("model")) for frame in frames if frame.get("model") != sys.argv[2]}
)
if unexpected_models:
    raise SystemExit(
        "OpenAI SSE model alias is unexpected: " + ", ".join(unexpected_models)
    )
content = []
for frame in frames:
    choices = frame.get("choices")
    if choices and isinstance(choices[0].get("delta"), dict):
        delta = choices[0]["delta"]
        for field in ("content", "reasoning_content"):
            part = delta.get(field)
            if isinstance(part, str):
                content.append(part)
if not "".join(content).strip():
    raise SystemExit("SSE frames contain no reconstructed model output")
PY

cat >"$work_dir/anthropic-non-stream-request.json" <<EOF
{"model":"$model_id","messages":[{"role":"user","content":"Reply with exactly: hello"}],"max_tokens":512,"temperature":0,"stream":false}
EOF

printf '7/11 Anthropic-compatible non-streaming Messages contract\n'
curl --fail --silent --show-error \
  --connect-timeout "$connect_timeout" \
  --max-time "$request_timeout" \
  --header 'Content-Type: application/json' \
  --header 'anthropic-version: 2023-06-01' \
  --header 'x-api-key: local-contract-key' \
  --data-binary "@$work_dir/anthropic-non-stream-request.json" \
  --output "$work_dir/anthropic-non-stream-response.json" \
  "$base_url/v1/messages"
python3 - "$work_dir/anthropic-non-stream-response.json" "$model_id" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as response:
    payload = json.load(response)
if payload.get("type") != "message" or payload.get("role") != "assistant":
    raise SystemExit("Anthropic response is not an assistant message")
content = payload.get("content")
if not isinstance(content, list) or not content:
    raise SystemExit("Anthropic response has no content blocks")
output = []
for block in content:
    if not isinstance(block, dict):
        continue
    for field in ("text", "thinking"):
        part = block.get(field)
        if isinstance(part, str):
            output.append(part)
if not "".join(output).strip():
    raise SystemExit("Anthropic response content is empty")
if not isinstance(payload.get("usage"), dict):
    raise SystemExit("Anthropic response has no usage object")
model = payload.get("model")
if model != sys.argv[2]:
    raise SystemExit(f"Anthropic response model alias is unexpected: {model!r}")
PY

cat >"$work_dir/anthropic-stream-request.json" <<EOF
{"model":"$model_id","messages":[{"role":"user","content":"Reply with exactly: one two three"}],"max_tokens":512,"temperature":0,"stream":true}
EOF

printf '8/11 Anthropic-compatible SSE Messages contract\n'
curl --fail --silent --show-error --no-buffer \
  --connect-timeout "$connect_timeout" \
  --max-time "$request_timeout" \
  --dump-header "$work_dir/anthropic-stream-headers.txt" \
  --header 'Accept: text/event-stream' \
  --header 'Content-Type: application/json' \
  --header 'anthropic-version: 2023-06-01' \
  --header 'x-api-key: local-contract-key' \
  --data-binary "@$work_dir/anthropic-stream-request.json" \
  --output "$work_dir/anthropic-stream-body.txt" \
  "$base_url/v1/messages"
tr -d '\r' <"$work_dir/anthropic-stream-headers.txt" \
  >"$work_dir/anthropic-stream-headers-normalized.txt"
grep -Eiq '^content-type:[[:space:]]*text/event-stream([[:space:]]*;|[[:space:]]*$)' \
  "$work_dir/anthropic-stream-headers-normalized.txt" || \
  fail 'Anthropic SSE content type is not text/event-stream'
python3 - "$work_dir/anthropic-stream-body.txt" "$model_id" <<'PY'
import json
import sys

event_names = []
output = []
pending_event = None
start_models = []
with open(sys.argv[1], encoding="utf-8") as response:
    for raw_line in response:
        line = raw_line.rstrip("\r\n")
        if line.startswith("event: "):
            pending_event = line[7:]
            event_names.append(pending_event)
        elif line.startswith("data: "):
            payload = json.loads(line[6:])
            if pending_event and payload.get("type") != pending_event:
                raise SystemExit(
                    f"Anthropic SSE event/data type mismatch: {pending_event}"
                )
            if payload.get("type") == "message_start":
                message = payload.get("message")
                start_models.append(
                    message.get("model") if isinstance(message, dict) else None
                )
            delta = payload.get("delta")
            if isinstance(delta, dict):
                for field in ("text", "thinking"):
                    part = delta.get(field)
                    if isinstance(part, str):
                        output.append(part)
required = {
    "message_start",
    "content_block_start",
    "content_block_delta",
    "content_block_stop",
    "message_delta",
    "message_stop",
}
missing = sorted(required.difference(event_names))
if missing:
    raise SystemExit(f"Anthropic SSE events are missing: {', '.join(missing)}")
if not event_names or event_names[-1] != "message_stop":
    raise SystemExit("Anthropic SSE terminal event is invalid")
if start_models != [sys.argv[2]]:
    raise SystemExit(f"Anthropic SSE model alias is unexpected: {start_models!r}")
if not "".join(output).strip():
    raise SystemExit("Anthropic SSE contains no reconstructed model output")
PY

printf '9/11 request body limit\n'
dd if=/dev/zero of="$work_dir/oversize.bin" bs=1048577 count=1 2>/dev/null
for endpoint in v1/chat/completions v1/messages; do
  oversize_status="$(curl --silent --show-error \
    --connect-timeout "$connect_timeout" \
    --max-time "$request_timeout" \
    --header 'Content-Type: application/json' \
    --data-binary "@$work_dir/oversize.bin" \
    --output "$work_dir/oversize-response.json" \
    --write-out '%{http_code}' \
    "$base_url/$endpoint")"
  [ "$oversize_status" = 413 ] || \
    fail "oversized request to /$endpoint returned HTTP $oversize_status"
done

printf '10/11 deny-by-default route\n'
[ "$(status_for "$base_url/not-a-public-route" "$work_dir/not-found.json")" = 404 ] || \
  fail 'unknown route did not return HTTP 404'

printf '11/11 response metadata isolation\n'
curl --silent --show-error \
  --connect-timeout "$connect_timeout" \
  --max-time "$request_timeout" \
  --dump-header "$work_dir/health-headers.txt" \
  --output /dev/null \
  "$base_url/health"
if grep -Eiq '^x-envoy-upstream-service-time:' "$work_dir/health-headers.txt"; then
  fail 'upstream timing header is exposed'
fi
if grep -Eiq '^access-control-allow-origin:[[:space:]]*\*' "$work_dir/health-headers.txt"; then
  fail 'wildcard CORS is exposed'
fi

printf 'Gateway API contract: PASS\n'
