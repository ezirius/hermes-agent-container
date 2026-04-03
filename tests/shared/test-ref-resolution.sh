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
PORT_FILE="$TMPDIR/http.port"
python3 -u - "$TMPDIR" "$PORT_FILE" >"$TMPDIR/http.log" 2>&1 <<'PY' &
import functools
import http.server
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
port_file = pathlib.Path(sys.argv[2])
handler = functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(root))
server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
port_file.write_text(str(server.server_port), encoding="utf-8")
server.serve_forever()
PY
SERVER_PID=$!

for _ in $(seq 1 50); do
  if [[ -s "$PORT_FILE" ]]; then
    break
  fi
  sleep 0.1
done
[[ -s "$PORT_FILE" ]] || { printf 'assertion failed: test HTTP server did not publish a port\n' >&2; exit 1; }
API_BASE="http://127.0.0.1:$(cat "$PORT_FILE")"

for _ in $(seq 1 50); do
  if python3 - "$API_BASE" >/dev/null 2>&1 <<'PY'
import sys, urllib.request
with urllib.request.urlopen(sys.argv[1] + '/repos/NousResearch/hermes-agent/releases/latest', timeout=1) as response:
    raise SystemExit(0 if response.status == 200 else 1)
PY
  then
    break
  fi
  sleep 0.1
done

assert_eq 'v1.2.3' "$(HERMES_REF=latest-release HERMES_GITHUB_API_BASE=$API_BASE resolve_hermes_ref)" 'latest release is preferred when available'
assert_eq 'NousResearch/hermes-agent' "$(github_repo_slug 'https://github.com/NousResearch/hermes-agent/')" 'github slug strips a trailing slash'
assert_eq 'NousResearch/hermes-agent' "$(github_repo_slug 'ssh://git@github.com/NousResearch/hermes-agent.git')" 'github slug accepts ssh GitHub URLs'
ERR_FILE="$TMPDIR/repo-slug.err"
if bash -lc 'set -euo pipefail; source "$1"; github_repo_slug "$2"' _ "$ROOT/lib/shell/common.sh" 'https://github.com/NousResearch/hermes-agent/tree/main' >/dev/null 2> "$ERR_FILE"; then
  printf 'assertion failed: malformed GitHub URLs should be rejected\n' >&2
  exit 1
fi
grep -Fq 'could not derive owner/repo from HERMES_REPO_URL' "$ERR_FILE"
rm -f "$TMPDIR/repos/NousResearch/hermes-agent/releases/latest"
ERR_FILE="$TMPDIR/release.err"
if HERMES_REF=latest-release HERMES_GITHUB_API_BASE=$API_BASE resolve_hermes_ref >/dev/null 2> "$ERR_FILE"; then
  printf 'assertion failed: latest-release should fail when the release endpoint is unavailable\n' >&2
  exit 1
fi
grep -Fq 'Latest upstream Hermes release not found' "$ERR_FILE"
assert_eq 'v9.9.9-test' "$(HERMES_REF=v9.9.9-test resolve_hermes_ref)" 'explicit ref bypasses remote resolution'

echo "Ref resolution checks passed"
