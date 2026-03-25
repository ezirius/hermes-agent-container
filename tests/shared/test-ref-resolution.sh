#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT/lib/shell/common.sh"

TMPDIR="$(mktemp -d)"
SERVER_PID=""
cleanup() {
  if [[ -n "$SERVER_PID" ]]; then
    kill "$SERVER_PID" >/dev/null 2>&1 || true
    wait "$SERVER_PID" 2>/dev/null || true
  fi
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

assert_eq() {
  local expected="$1" actual="$2" message="$3"
  [[ "$expected" == "$actual" ]] || { printf 'assertion failed: %s\nexpected: %s\nactual:   %s\n' "$message" "$expected" "$actual" >&2; exit 1; }
}

mkdir -p "$TMPDIR/repos/NousResearch/hermes-agent/releases" "$TMPDIR/repos/NousResearch/hermes-agent"
printf '{"tag_name":"v1.2.3"}\n' > "$TMPDIR/repos/NousResearch/hermes-agent/releases/latest"
python3 -m http.server 18082 --bind 127.0.0.1 --directory "$TMPDIR" >/dev/null 2>&1 &
SERVER_PID=$!
sleep 1

assert_eq 'v1.2.3' "$(HERMES_REF=latest-release HERMES_GITHUB_API_BASE=http://127.0.0.1:18082 resolve_hermes_ref)" 'latest release is preferred when available'
rm -f "$TMPDIR/repos/NousResearch/hermes-agent/releases/latest"
ERR_FILE="$TMPDIR/release.err"
if HERMES_REF=latest-release HERMES_GITHUB_API_BASE=http://127.0.0.1:18082 resolve_hermes_ref >/dev/null 2> "$ERR_FILE"; then
  printf 'assertion failed: latest-release should fail when the release endpoint is unavailable\n' >&2
  exit 1
fi
grep -Fq 'Latest upstream Hermes release not found' "$ERR_FILE"
assert_eq 'main' "$(HERMES_REF=main resolve_hermes_ref)" 'explicit ref bypasses remote resolution'

echo "Ref resolution checks passed"
