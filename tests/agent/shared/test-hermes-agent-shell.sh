#!/usr/bin/env bash

set -euo pipefail

# This test checks that the shell script opens an ephemeral CLI container for one workspace.

# This finds the repo root so the test can reach the script, config, and helpers.
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
source "$ROOT/tests/agent/shared/test-asserts.sh"

# This points at the shared config file the test rewrites for a short time.
CONFIG_PATH="$ROOT/config/agent/shared/hermes-agent-settings-shared.conf"
CONFIG_BACKUP="$(mktemp)"
TMP_DIR="$(mktemp -d)"
backup_created=0

# This puts the real config back and removes the temporary test files.
cleanup() {
  if [[ "$backup_created" == '1' ]]; then
    cp "$CONFIG_BACKUP" "$CONFIG_PATH"
  fi
  rm -rf "$TMP_DIR"
}

trap cleanup EXIT

# This saves the real config before the test writes its own version.
cp "$CONFIG_PATH" "$CONFIG_BACKUP"
backup_created=1

# This folder holds fake commands so the test can watch what the script would do.
FAKE_BIN="$TMP_DIR/fake-bin"
mkdir -p "$FAKE_BIN"

# This fake Podman returns controlled image and container answers for each test case.
cat >"$FAKE_BIN/podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$HERMES_TEST_PODMAN_LOG"

case "$1" in
  images)
    case "${HERMES_TEST_IMAGE_MODE:-present}" in
      missing) ;;
      localhost) printf 'localhost/hermes-agent-0.10.0-20260417-120000-abcdef123456\n' ;;
      *) printf 'hermes-agent-0.10.0-20260417-120000-abcdef123456\n' ;;
    esac
    ;;
  ps)
    case "${HERMES_TEST_CONTAINER_MODE:-present}" in
      present)
        case "$*" in
          *beta*)
            printf 'hermes-agent-0.10.0-20260417-120000-abcdef123456-beta-gateway\n'
            ;;
          *)
            printf 'hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-gateway\n'
            ;;
        esac
        ;;
      multiple)
        printf 'hermes-agent-0.10.0-20260417-120500-bcdef1234567-beta-gateway\n'
        printf 'hermes-agent-0.10.0-20260417-120000-abcdef123456-beta-gateway\n'
        ;;
      collision)
        printf 'hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-prod-gateway\n'
        printf 'hermes-agent-0.10.0-20260417-120500-bcdef1234567-alpha-gateway\n'
        ;;
      mount-mismatch)
        printf 'hermes-agent-0.10.0-20260417-120500-bcdef1234567-beta-gateway\n'
        printf 'hermes-agent-0.10.0-20260417-120000-abcdef123456-beta-gateway\n'
        ;;
    esac
    ;;
  inspect)
    container_name="${*: -1}"
    case "${HERMES_TEST_CONTAINER_MODE:-present}:$container_name" in
      mount-mismatch:*120500*) printf '%s : /workspace/general\n' "${HOME}/tmp/hermes-agent/not-beta/hermes-agent-general" ;;
      *:*-alpha-prod-gateway) printf '%s : /workspace/general\n' "${HOME}/tmp/hermes-agent/alpha-prod/hermes-agent-general" ;;
      *:*-alpha-gateway) printf '%s : /workspace/general\n' "${HOME}/tmp/hermes-agent/alpha/hermes-agent-general" ;;
      *:*-beta-gateway) printf '%s : /workspace/general\n' "${HOME}/tmp/hermes-agent/beta/hermes-agent-general" ;;
    esac
    ;;
  exec)
    ;;
  run)
    printf 'new-cli-container\n'
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
HERMES_AGENT_SHELL_COMMAND="nu"
HERMES_AGENT_BASE_PATH="${HOME}/tmp/hermes-agent"
HERMES_AGENT_WORKSPACES="alpha:100 beta:200"
HERMES_AGENT_CONTAINER_HOME="/opt/data"
HERMES_AGENT_CONTAINER_WORKSPACE="/workspace/general"
HERMES_AGENT_HOST_HOME_DIRNAME="hermes-agent-home"
HERMES_AGENT_HOST_WORKSPACE_DIRNAME="hermes-agent-general"
EOF

PODMAN_LOG="$TMP_DIR/podman.log"
SHELL_STDERR="$TMP_DIR/shell.stderr"

# This is the normal case where beta opens an ephemeral CLI container.
printf 'beta\n' | PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/agent/shared/hermes-agent-shell" >/dev/null 2>"$SHELL_STDERR"

# These checks prove the shell command uses a no-port, no-pod CLI container with the workspace mounts.
assert_file_contains 'Selection:' "$SHELL_STDERR" 'shell should show an explicit selection prompt'
assert_file_contains 'run -i --rm --name hermes-agent-0.10.0-20260417-120000-abcdef123456-beta-cli --workdir /workspace/general' "$PODMAN_LOG" 'shell should run an ephemeral CLI container for the chosen workspace'
assert_file_contains "$HOME/tmp/hermes-agent/beta/hermes-agent-home:/opt/data" "$PODMAN_LOG" 'shell should mount the Hermes data path into the CLI container'
assert_file_contains "$HOME/tmp/hermes-agent/beta/hermes-agent-general:/workspace/general" "$PODMAN_LOG" 'shell should mount the workspace path into the CLI container'
assert_file_contains 'hermes-agent-0.10.0-20260417-120000-abcdef123456 nu' "$PODMAN_LOG" 'shell should run the configured shell command in the CLI container by default'
assert_file_not_contains '--pod' "$PODMAN_LOG" 'shell CLI container should not join the runtime pod'
assert_file_not_contains '-p ' "$PODMAN_LOG" 'shell CLI container should not publish ports'
assert_file_not_contains 'exec -i hermes-agent-0.10.0-20260417-120000-abcdef123456-beta-gateway nu' "$PODMAN_LOG" 'shell should not exec into the persistent gateway container'

# This checks that one workspace argument skips the picker and still opens nushell.
: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/agent/shared/hermes-agent-shell" alpha >/dev/null 2>"$SHELL_STDERR"

assert_file_not_contains 'Selection:' "$SHELL_STDERR" 'shell should not show the picker when a workspace argument is provided'
assert_file_contains 'run -i --rm --name hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-cli --workdir /workspace/general' "$PODMAN_LOG" 'shell should accept a workspace argument and open an ephemeral CLI container'

# This checks that an explicit in-container command passes through unchanged.
: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/agent/shared/hermes-agent-shell" alpha hermes auth list >/dev/null 2>"$SHELL_STDERR"

assert_file_contains 'hermes-agent-0.10.0-20260417-120000-abcdef123456 hermes auth list' "$PODMAN_LOG" 'shell should forward an explicit command vector after the workspace name'

# This checks that a non-Hermes command also passes through unchanged.
: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/agent/shared/hermes-agent-shell" alpha python -V >/dev/null 2>"$SHELL_STDERR"

assert_file_contains 'hermes-agent-0.10.0-20260417-120000-abcdef123456 python -V' "$PODMAN_LOG" 'shell should forward non-Hermes commands after the workspace name'

# This checks that a typed workspace still has to be one of the configured ones.
if PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/agent/shared/hermes-agent-shell" gamma >/dev/null 2>"$TMP_DIR/unconfigured.stderr"; then
  fail 'shell should reject an unconfigured workspace argument'
fi

assert_file_contains 'Workspace gamma is not configured.' "$TMP_DIR/unconfigured.stderr" 'shell should reject unconfigured workspace arguments before looking up containers'

# This checks that localhost-prefixed local images are normalized before CLI container naming.
: >"$PODMAN_LOG"
printf 'beta\n' | PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_IMAGE_MODE="localhost" bash "$ROOT/scripts/agent/shared/hermes-agent-shell" >/dev/null

assert_file_contains 'run -i --rm --name hermes-agent-0.10.0-20260417-120000-abcdef123456-beta-cli' "$PODMAN_LOG" 'shell should normalize localhost image names before naming CLI containers'

# This checks that the script explains the failure when no local image exists.
if printf 'alpha\n' | PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_IMAGE_MODE="missing" bash "$ROOT/scripts/agent/shared/hermes-agent-shell" >/dev/null 2>"$TMP_DIR/missing.stderr"; then
  fail 'shell should fail when no local image exists'
fi

assert_file_contains 'No built Hermes Agent image found. Run scripts/agent/shared/hermes-agent-build first.' "$TMP_DIR/missing.stderr" 'shell should explain missing local images'

# This checks that the shared exec helper drops `-t` when stdin is not a real terminal.
cat >"$FAKE_BIN/podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$HERMES_TEST_PODMAN_LOG"
EOF

chmod +x "$FAKE_BIN/podman"
: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" bash -c 'set -euo pipefail; source "$1"; hermes_exec_podman_interactive_command exec demo-container bash' _ "$ROOT/lib/shell/shared/common.sh" </dev/null >/dev/null

assert_file_contains 'exec -i demo-container bash' "$PODMAN_LOG" 'shared exec helper should drop tty mode when stdin is not interactive'

# This checks that interactive Linux auto mode falls back to plain Podman `-it` when no wrapper is needed.
: >"$PODMAN_LOG"
PATH="$FAKE_BIN:/usr/bin:/bin" ROOT="$ROOT" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_AGENT_FORCE_EXEC_TTY="1" OSTYPE='linux-gnu' /bin/bash -c 'set -euo pipefail; source "$1"; hermes_exec_podman_interactive_command exec demo-container bash' _ "$ROOT/lib/shell/shared/common.sh" >/dev/null

assert_file_contains 'exec -it demo-container bash' "$PODMAN_LOG" 'shared exec helper should use plain interactive Podman when auto mode does not need script'

# This checks that explicit script mode fails clearly when `script` is not installed.
if PATH="$FAKE_BIN" ROOT="$ROOT" HERMES_AGENT_FORCE_EXEC_TTY="1" HERMES_AGENT_PODMAN_TTY_WRAPPER="script" /bin/bash -c 'set -euo pipefail; source "$1"; hermes_exec_podman_interactive_command exec demo-container bash' _ "$ROOT/lib/shell/shared/common.sh" >/dev/null 2>"$TMP_DIR/script-missing.stderr"; then
  fail 'shared exec helper should fail when explicit script mode is requested but unavailable'
fi

assert_file_contains 'HERMES_AGENT_PODMAN_TTY_WRAPPER=script requires script to be installed.' "$TMP_DIR/script-missing.stderr" 'shared exec helper should explain missing script dependency'

printf 'hermes-agent-shell behavior checks passed\n'
