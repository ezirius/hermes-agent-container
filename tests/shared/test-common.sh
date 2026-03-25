#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT/lib/shell/common.sh"

assert_eq() {
  local expected="$1"
  local actual="$2"
  local message="$3"
  [[ "$expected" == "$actual" ]] || { printf 'assertion failed: %s\nexpected: %s\nactual:   %s\n' "$message" "$expected" "$actual" >&2; exit 1; }
}

export HERMES_BASE_ROOT="$ROOT/.tmp/workspaces"
resolve_workspace "ezirius"
assert_eq "ezirius" "$WORKSPACE_NAME" "workspace name resolves"
assert_eq "$ROOT/.tmp/workspaces/ezirius" "$WORKSPACE_ROOT" "workspace root resolves under base root"
assert_eq "$ROOT/.tmp/workspaces/ezirius/workspace" "$HERMES_WORKSPACE_DIR" "workspace dir resolves under workspace root"

ERR_FILE="$(mktemp)"
trap 'rm -f "$ERR_FILE"' EXIT
if bash -lc 'set -euo pipefail; source "$1"; export HERMES_BASE_ROOT="$2"; resolve_workspace "/tmp/absolute"' _ "$ROOT/lib/shell/common.sh" "$ROOT/.tmp/workspaces" >/dev/null 2> "$ERR_FILE"; then
  printf 'assertion failed: absolute workspace paths should be rejected\n' >&2
  exit 1
fi
grep -Fq 'workspace name must not contain path separators' "$ERR_FILE"

echo "Common helper checks passed"
