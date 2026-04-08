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

mkdir -p "$TMPDIR/repos/NousResearch/hermes-agent"
printf '[{"tag_name":"v1.2.3","name":"Hermes Agent v1.2.3"},{"tag_name":"v1.2.2","name":"Hermes Agent v1.2.2"}]\n' > "$TMPDIR/repos/NousResearch/hermes-agent/releases"
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
  [[ -s "$PORT_FILE" ]] && break
  sleep 0.1
done
API_BASE="http://127.0.0.1:$(cat "$PORT_FILE")"

assert_eq '1.2.3' "$(HERMES_REF=latest HERMES_GITHUB_API_BASE=$API_BASE resolve_hermes_ref)" 'latest release resolves to the display label used in immutable tags'
assert_eq 'main' "$(HERMES_REF=main resolve_hermes_ref)" 'main stays main'
assert_eq 'v9.9.9-test' "$(HERMES_REF=v9.9.9-test resolve_hermes_ref)" 'explicit ref bypasses remote resolution'
assert_eq $'1.2.3\tv1.2.3' "$(HERMES_REF=latest HERMES_GITHUB_API_BASE=$API_BASE resolve_hermes_selection)" 'latest selection returns display label and git ref'
assert_eq $'1.2.3\tv1.2.3\n1.2.2\tv1.2.2' "$(HERMES_GITHUB_API_BASE=$API_BASE list_upstream_release_options)" 'release options derive display labels from the releases list'

echo "Ref resolution checks passed"
