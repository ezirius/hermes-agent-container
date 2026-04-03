#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

bash -n \
  "$ROOT/lib/shell/common.sh" \
  "$ROOT/scripts/shared/bootstrap" \
  "$ROOT/scripts/shared/hermes-build" \
  "$ROOT/scripts/shared/hermes-upgrade" \
  "$ROOT/scripts/shared/bootstrap-test" \
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
  "$ROOT/tests/shared/test-runtime.sh"

python3 -m py_compile \
  "$ROOT/config/patches/apply-hermes-mautrix-migration.py" \
  "$ROOT/config/patches/templates/hermes-matrix-mautrix.py"

"$ROOT/tests/shared/test-layout.sh"
"$ROOT/tests/shared/test-common.sh"
"$ROOT/tests/shared/test-args.sh"
"$ROOT/tests/shared/test-ref-resolution.sh"
"$ROOT/tests/shared/test-runtime.sh"

echo "All Hermes checks passed"
