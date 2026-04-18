#!/usr/bin/env bash

set -euo pipefail

# This test checks that the entrypoint waits for setup and then starts Hermes automatically.

# This finds the repo root so the test can reach the entrypoint and shared asserts.
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
source "$ROOT/tests/agent/shared/test-asserts.sh"

# This creates temporary state for the fake Hermes commands and delayed setup files.
TMP_DIR="$(mktemp -d)"
FAKE_BIN="$TMP_DIR/fake-bin"
HERMES_HOME_DIR="$TMP_DIR/hermes-home"
ENTRYPOINT_STDERR="$TMP_DIR/entrypoint.stderr"
HERMES_LOG="$TMP_DIR/hermes.log"
ENTRYPOINT_PID=""

# This cleans up the background entrypoint and temporary test files.
cleanup() {
  if [[ -n "$ENTRYPOINT_PID" ]] && kill -0 "$ENTRYPOINT_PID" 2>/dev/null; then
    kill "$ENTRYPOINT_PID" 2>/dev/null || true
    wait "$ENTRYPOINT_PID" 2>/dev/null || true
  fi

  rm -rf "$TMP_DIR"
}

trap cleanup EXIT

mkdir -p "$FAKE_BIN" "$HERMES_HOME_DIR"

# This fake Hermes records which services were started and then stays alive.
cat >"$FAKE_BIN/hermes" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

printf '%s\n' "$*" >>"$HERMES_TEST_HERMES_LOG"
trap 'exit 0' TERM INT

while true; do
  sleep 1
done
EOF

chmod +x "$FAKE_BIN/hermes"

# This starts the entrypoint without setup so the test can add config files later.
PATH="$FAKE_BIN:$PATH" \
HERMES_HOME="$HERMES_HOME_DIR" \
HERMES_AGENT_DASHBOARD_PORT="9234" \
HERMES_TEST_HERMES_LOG="$HERMES_LOG" \
bash "$ROOT/scripts/agent/shared/hermes-agent-entrypoint" \
  >/dev/null 2>"$ENTRYPOINT_STDERR" &
ENTRYPOINT_PID="$!"

# This gives the entrypoint time to print its idle message before setup exists.
sleep 2

assert_file_contains 'Hermes setup is incomplete. Skipping gateway and dashboard startup until ' "$ENTRYPOINT_STDERR" 'entrypoint should explain why startup is waiting for setup files'
assert_equals '1' "$(grep -c '^Hermes setup is incomplete\.' "$ENTRYPOINT_STDERR")" 'entrypoint should print the incomplete-setup message only once while polling'

if [[ -s "$HERMES_LOG" ]]; then
  fail 'entrypoint should not start Hermes services before setup is complete'
fi

# This confirms the old config.toml path does not count as completed setup.
printf 'model = "default"\n' >"$HERMES_HOME_DIR/config.toml"
printf 'HERMES_API_KEY=test\n' >"$HERMES_HOME_DIR/.env"
sleep 6

if [[ -s "$HERMES_LOG" ]]; then
  fail 'entrypoint should keep waiting when only config.toml and .env exist'
fi

# This completes setup after the entrypoint has already started waiting.
printf 'model: default\n' >"$HERMES_HOME_DIR/config.yaml"

# This waits for the delayed setup to trigger both managed services.
for attempt in 1 2 3 4 5 6 7 8; do
  if grep -Fq 'gateway run' "$HERMES_LOG" 2>/dev/null && grep -Fq 'dashboard --host 0.0.0.0 --port 9234 --no-open --insecure' "$HERMES_LOG" 2>/dev/null; then
    break
  fi

  sleep 1
done

assert_file_contains 'gateway run' "$HERMES_LOG" 'entrypoint should start the gateway after delayed setup completes'
assert_file_contains 'dashboard --host 0.0.0.0 --port 9234 --no-open --insecure' "$HERMES_LOG" 'entrypoint should start the dashboard after delayed setup completes'

if ! kill -0 "$ENTRYPOINT_PID" 2>/dev/null; then
  fail 'entrypoint should stay alive after delayed setup starts the managed services'
fi

printf 'hermes-agent-entrypoint behavior checks passed\n'
