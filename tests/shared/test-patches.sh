#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

python3 -m py_compile \
  "$ROOT/config/patches/apply-hermes-host-agents-context.py" \
  "$ROOT/config/patches/apply-hermes-matrix-device-id.py" \
  "$ROOT/config/patches/apply-hermes-matrix-config-overrides.py" \
  "$ROOT/config/patches/apply-hermes-transcription-oga.py"

echo "Patch checks passed"
