#!/usr/bin/env bash

set -euo pipefail

# This test checks that the shell script finds the right running container for one workspace.

# This finds the repo root so the test can reach the script, config, and helpers.
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
source "$ROOT/tests/agent/shared/test-asserts.sh"

# This points at the shared config file the test rewrites for a short time.
CONFIG_PATH="$ROOT/config/agent/shared/hermes-agent-settings-shared.conf"
CONFIG_BACKUP="$(mktemp)"
TMP_DIR="$(mktemp -d)"

# This puts the real config back and removes the temporary test files.
cleanup() {
  cp "$CONFIG_BACKUP" "$CONFIG_PATH"
  rm -rf "$TMP_DIR"
}

trap cleanup EXIT

# This saves the real config before the test writes its own version.
cp "$CONFIG_PATH" "$CONFIG_BACKUP"

# This folder holds fake commands so the test can watch what the script would do.
FAKE_BIN="$TMP_DIR/fake-bin"
mkdir -p "$FAKE_BIN"

# This fake Podman returns controlled running-container answers for each test case.
cat >"$FAKE_BIN/podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$HERMES_TEST_PODMAN_LOG"

case "$1" in
  ps)
    case "${HERMES_TEST_CONTAINER_MODE:-present}" in
      present)
        case "$*" in
          *beta*)
            printf 'hermes-agent-beta-0.10.0-20260417-120000-123\n'
            ;;
          *)
            printf 'hermes-agent-alpha-0.10.0-20260417-120000-123\n'
            ;;
        esac
        ;;
      multiple)
        printf 'hermes-agent-beta-0.10.0-20260417-120000-123\n'
        printf 'hermes-agent-beta-0.10.0-20260417-120500-456\n'
        ;;
    esac
    ;;
  exec)
    ;;
esac
EOF

chmod +x "$FAKE_BIN/podman"

# This test config keeps the workspace names and commands predictable.
cat >"$CONFIG_PATH" <<EOF
# Hermes Agent runtime and build configuration.
HERMES_AGENT_IMAGE_BASENAME="hermes-agent"
HERMES_AGENT_UID="1000"
HERMES_AGENT_GID="1000"
HERMES_AGENT_VERSION="0.10.0"
HERMES_AGENT_RELEASE_TAG="v2026.4.16"
HERMES_AGENT_DASHBOARD_PORT="9234"
HERMES_AGENT_CHAT_COMMAND="hermes"
HERMES_AGENT_SHELL_COMMAND="bash"
HERMES_AGENT_OPEN_COMMAND="open"
HERMES_AGENT_BASE_PATH="${HOME}/tmp/hermes-agent"
HERMES_AGENT_WORKSPACES="alpha:100 beta:200"
HERMES_AGENT_CONTAINER_HOME="/home/hermes-agent"
HERMES_AGENT_CONTAINER_WORKSPACE="/workspace/general"
HERMES_AGENT_HOST_HOME_DIRNAME="hermes-agent-home"
HERMES_AGENT_HOST_WORKSPACE_DIRNAME="hermes-agent-general"
EOF

PODMAN_LOG="$TMP_DIR/podman.log"
SHELL_STDERR="$TMP_DIR/shell.stderr"

# This is the normal case where beta has one running container.
printf 'beta\n' | PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/agent/shared/hermes-agent-shell" >/dev/null 2>"$SHELL_STDERR"

# These checks prove the shell command looked up the right container and attached to it.
assert_file_contains 'Selection:' "$SHELL_STDERR" 'shell should show an explicit selection prompt'
assert_file_contains '--filter name=^hermes-agent-beta-' "$PODMAN_LOG" 'shell should filter running containers by chosen workspace'
assert_file_contains 'exec -i hermes-agent-beta-0.10.0-20260417-120000-123 bash' "$PODMAN_LOG" 'shell should exec configured shell command'

# This checks that one workspace argument skips the picker and still opens bash.
: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/agent/shared/hermes-agent-shell" alpha >/dev/null 2>"$SHELL_STDERR"

assert_file_contains 'exec -i hermes-agent-alpha-0.10.0-20260417-120000-123 bash' "$PODMAN_LOG" 'shell should accept a workspace argument and still open bash'
assert_file_not_contains 'Selection:' "$SHELL_STDERR" 'shell should not show the picker when a workspace argument is provided'

# This checks that extra arguments run through hermes inside the chosen workspace.
: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/agent/shared/hermes-agent-shell" alpha auth list >/dev/null 2>"$SHELL_STDERR"

assert_file_contains 'exec -i hermes-agent-alpha-0.10.0-20260417-120000-123 hermes auth list' "$PODMAN_LOG" 'shell should run hermes with forwarded arguments after the workspace name'

# This checks that a typed workspace still has to be one of the configured ones.
if PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/agent/shared/hermes-agent-shell" gamma >/dev/null 2>"$TMP_DIR/unconfigured.stderr"; then
  fail 'shell should reject an unconfigured workspace argument'
fi

assert_file_contains 'Workspace gamma is not configured.' "$TMP_DIR/unconfigured.stderr" 'shell should reject unconfigured workspace arguments before looking up containers'

# This checks that the newest running container wins when more than one matches.
: >"$PODMAN_LOG"
printf 'beta\n' | PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_CONTAINER_MODE="multiple" bash "$ROOT/scripts/agent/shared/hermes-agent-shell" >/dev/null

assert_file_contains 'exec -i hermes-agent-beta-0.10.0-20260417-120500-456 bash' "$PODMAN_LOG" 'shell should choose the newest running workspace container when multiple match'

# This checks that the script explains the failure when no container exists.
if printf 'alpha\n' | PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_CONTAINER_MODE="missing" bash "$ROOT/scripts/agent/shared/hermes-agent-shell" >/dev/null 2>"$TMP_DIR/missing.stderr"; then
  fail 'shell should fail when no container exists for workspace'
fi

assert_file_contains 'No running Hermes Agent container found for alpha.' "$TMP_DIR/missing.stderr" 'shell should explain missing workspace container'

# This checks that the shared exec helper drops `-t` when stdin is not a real terminal.
cat >"$FAKE_BIN/podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$HERMES_TEST_PODMAN_LOG"
EOF

chmod +x "$FAKE_BIN/podman"
: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" bash -lc 'set -euo pipefail; source "$1"; hermes_exec_podman_interactive_command exec demo-container bash' _ "$ROOT/lib/shell/shared/common.sh" </dev/null >/dev/null

assert_file_contains 'exec -i demo-container bash' "$PODMAN_LOG" 'shared exec helper should drop tty mode when stdin is not interactive'

# This checks that interactive Linux auto mode falls back to plain Podman `-it` when no wrapper is needed.
: >"$PODMAN_LOG"
PATH="$FAKE_BIN:/usr/bin:/bin" ROOT="$ROOT" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_AGENT_FORCE_EXEC_TTY="1" OSTYPE='linux-gnu' /bin/bash -lc 'set -euo pipefail; source "$1"; hermes_exec_podman_interactive_command exec demo-container bash' _ "$ROOT/lib/shell/shared/common.sh" >/dev/null

assert_file_contains 'exec -it demo-container bash' "$PODMAN_LOG" 'shared exec helper should use plain interactive Podman when auto mode does not need script'

# This checks that explicit script mode fails clearly when `script` is not installed.
if PATH="$FAKE_BIN" ROOT="$ROOT" HERMES_AGENT_FORCE_EXEC_TTY="1" HERMES_AGENT_PODMAN_TTY_WRAPPER="script" /bin/bash -lc 'set -euo pipefail; source "$1"; hermes_exec_podman_interactive_command exec demo-container bash' _ "$ROOT/lib/shell/shared/common.sh" >/dev/null 2>"$TMP_DIR/script-missing.stderr"; then
  fail 'shared exec helper should fail when explicit script mode is requested but unavailable'
fi

assert_file_contains 'HERMES_AGENT_PODMAN_TTY_WRAPPER=script requires script to be installed.' "$TMP_DIR/script-missing.stderr" 'shared exec helper should explain missing script dependency'

printf 'hermes-agent-shell behavior checks passed\n'
