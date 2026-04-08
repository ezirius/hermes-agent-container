#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

bash -n \
  "$ROOT/lib/shell/common.sh" \
  "$ROOT/config/containers/entrypoint.sh" \
  "$ROOT/scripts/shared/hermes-bootstrap" \
  "$ROOT/scripts/shared/hermes-build" \
  "$ROOT/scripts/shared/hermes-start" \
  "$ROOT/scripts/shared/hermes-open" \
  "$ROOT/scripts/shared/hermes-status" \
  "$ROOT/scripts/shared/hermes-logs" \
  "$ROOT/scripts/shared/hermes-shell" \
  "$ROOT/scripts/shared/hermes-stop" \
  "$ROOT/scripts/shared/hermes-remove" \
  "$ROOT/tests/shared/test-layout.sh" \
  "$ROOT/tests/shared/test-common.sh" \
  "$ROOT/tests/shared/test-args.sh" \
  "$ROOT/tests/shared/test-ref-resolution.sh" \
  "$ROOT/tests/shared/test-runtime.sh" \
  "$ROOT/tests/shared/test-entrypoint.sh" \
  "$ROOT/tests/shared/test-patches.sh"

python3 -m py_compile \
  "$ROOT/config/patches/apply-hermes-host-agents-context.py" \
  "$ROOT/config/patches/apply-hermes-matrix-device-id.py" \
  "$ROOT/config/patches/apply-hermes-matrix-config-overrides.py" \
  "$ROOT/config/patches/apply-hermes-transcription-oga.py"

bash "$ROOT/tests/shared/test-layout.sh"
bash "$ROOT/tests/shared/test-common.sh"
bash "$ROOT/tests/shared/test-args.sh"
bash "$ROOT/tests/shared/test-ref-resolution.sh"
bash "$ROOT/tests/shared/test-runtime.sh"
bash "$ROOT/tests/shared/test-entrypoint.sh"
bash "$ROOT/tests/shared/test-patches.sh"

echo "All Hermes checks passed"
