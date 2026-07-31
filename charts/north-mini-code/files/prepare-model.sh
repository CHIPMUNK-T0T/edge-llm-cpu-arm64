#!/bin/sh
set -eu

: "${SOURCE_FILE:?SOURCE_FILE is required}"
: "${TARGET_FILE:?TARGET_FILE is required}"
: "${EXPECTED_SIZE:?EXPECTED_SIZE is required}"
: "${EXPECTED_SHA256:?EXPECTED_SHA256 is required}"

temporary_file="${TARGET_FILE}.part"

cleanup() {
  rm -f "$temporary_file"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

verify_file() {
  candidate="$1"
  test -f "$candidate" || return 1
  actual_size="$(stat -c '%s' "$candidate")" || return 1
  actual_sha256_line="$(sha256sum "$candidate")" || return 1
  actual_sha256="${actual_sha256_line%% *}"
  test "$actual_size" = "$EXPECTED_SIZE" || return 1
  test "$actual_sha256" = "$EXPECTED_SHA256" || return 1
}

if verify_file "$TARGET_FILE"; then
  echo "Model already present and verified."
  exit 0
fi

if ! verify_file "$SOURCE_FILE"; then
  echo "Source model verification failed; existing target was left unchanged." >&2
  exit 1
fi

if [ -e "$TARGET_FILE" ]; then
  echo "Removing the invalid target after verifying the source model."
  rm -f "$TARGET_FILE"
fi

echo "Copying the pinned model into the PVC."
cp "$SOURCE_FILE" "$temporary_file"
verify_file "$temporary_file"
mv "$temporary_file" "$TARGET_FILE"
echo "Model import and verification: PASS"
