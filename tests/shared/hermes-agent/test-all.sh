#!/usr/bin/env bash

set -euo pipefail

# This test runs the Hermes Agent shell test suite sequentially.

# This finds the repo root so each script runs from one stable path.
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"

# These tests run one at a time because some of them rewrite shared config.
bash "$ROOT/tests/shared/hermes-agent/test-hermes-agent-layout.sh"
bash "$ROOT/tests/shared/hermes-agent/test-hermes-agent-build.sh"
bash "$ROOT/tests/shared/hermes-agent/test-hermes-agent-run.sh"
bash "$ROOT/tests/shared/hermes-agent/test-hermes-agent-shell.sh"

printf 'All Hermes Agent wrapper checks passed\n'
