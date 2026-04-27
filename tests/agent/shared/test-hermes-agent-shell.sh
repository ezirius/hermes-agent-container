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
    if [[ "$2" == '-aq' ]]; then
      case "${HERMES_TEST_CLI_COLLISION_MODE:-}" in
        exact|mount-mismatch|running)
          printf 'hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-cli\n'
          exit 0
          ;;
      esac

      if [[ "${HERMES_TEST_RENAMED_CLI_MODE:-}" == 'leftover' && "$*" == *'alpha-cli-'* ]]; then
        printf 'hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-cli-abcdef123456\n'
        exit 0
      fi

      if [[ "${HERMES_TEST_RENAMED_CLI_MODE:-}" == 'running-leftover' && "$*" == *'alpha-cli-'* ]]; then
        printf 'hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-cli-abcdef123456\n'
        exit 0
      fi

      exit 0
    fi

    if [[ "${HERMES_TEST_CLI_COLLISION_MODE:-}" == 'running' && "$*" == *'alpha-cli'* ]]; then
      printf 'hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-cli\n'
      exit 0
    fi
    if [[ "${HERMES_TEST_RENAMED_CLI_MODE:-}" == 'running-leftover' && "$*" == *'alpha-cli-abcdef123456'* ]]; then
      printf 'hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-cli-abcdef123456\n'
      exit 0
    fi
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
    case "${HERMES_TEST_CLI_COLLISION_MODE:-}:$container_name" in
      exact:*-alpha-cli) printf '%s : /workspace/general\n' "${HOME}/tmp/hermes-agent/alpha/hermes-agent-general" ; exit 0 ;;
      mount-mismatch:*-alpha-cli) printf '%s : /workspace/general\n' "${HOME}/tmp/hermes-agent/not-alpha/hermes-agent-general" ; exit 0 ;;
      running:*-alpha-cli) printf '%s : /workspace/general\n' "${HOME}/tmp/hermes-agent/alpha/hermes-agent-general" ; exit 0 ;;
    esac

    case "${HERMES_TEST_RENAMED_CLI_MODE:-}:$container_name" in
      leftover:*-alpha-cli-abcdef123456) printf '%s : /workspace/general\n' "${HOME}/tmp/hermes-agent/alpha/hermes-agent-general" ; exit 0 ;;
      running-leftover:*-alpha-cli-abcdef123456) printf '%s : /workspace/general\n' "${HOME}/tmp/hermes-agent/alpha/hermes-agent-general" ; exit 0 ;;
    esac

    case "${HERMES_TEST_CONTAINER_MODE:-present}:$container_name" in
      mount-mismatch:*120500*) printf '%s : /workspace/general\n' "${HOME}/tmp/hermes-agent/not-beta/hermes-agent-general" ;;
      *:*-alpha-prod-gateway) printf '%s : /workspace/general\n' "${HOME}/tmp/hermes-agent/alpha-prod/hermes-agent-general" ;;
      *:*-alpha-gateway) printf '%s : /workspace/general\n' "${HOME}/tmp/hermes-agent/alpha/hermes-agent-general" ;;
      *:*-beta-gateway) printf '%s : /workspace/general\n' "${HOME}/tmp/hermes-agent/beta/hermes-agent-general" ;;
    esac
    ;;
  exec)
    ;;
  rm)
    ;;
  create)
    if [[ "${HERMES_TEST_CLI_COLLISION_MODE:-}" == 'exact' ]]; then
      expected_name='hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-cli'
      if ! grep -Fqx -- "rm ${expected_name}" "$HERMES_TEST_PODMAN_LOG"; then
        printf 'Error: container name "%s" is already in use\n' "$expected_name" >&2
        exit 125
      fi
    fi
    printf 'abcdef1234567890fedcba0987654321abcdef1234567890fedcba0987654321\n'
    ;;
  start)
    ;;
  rename)
    if [[ "${HERMES_TEST_CLI_RENAME_MODE:-ok}" == 'fail' ]]; then
      printf 'rename failed\n' >&2
      exit 9
    fi
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

rm -f "$HOME/tmp/hermes-agent/alpha/hermes-agent-home/.hermes-agent-shell-launch.lock"
rm -f "$HOME/tmp/hermes-agent/beta/hermes-agent-home/.hermes-agent-shell-launch.lock"

# This is the normal case where beta opens an ephemeral CLI container.
printf 'beta\n' | PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/agent/shared/hermes-agent-shell" >/dev/null 2>"$SHELL_STDERR"

# These checks prove the shell command uses a no-port, no-pod CLI container with the workspace mounts.
assert_file_contains 'Selection:' "$SHELL_STDERR" 'shell should show an explicit selection prompt'
assert_file_contains 'create --name hermes-agent-0.10.0-20260417-120000-abcdef123456-beta-cli --workdir /workspace/general' "$PODMAN_LOG" 'shell should create the CLI container with the temporary exact name first'
assert_file_contains "$HOME/tmp/hermes-agent/beta/hermes-agent-home:/opt/data" "$PODMAN_LOG" 'shell should mount the Hermes data path into the CLI container'
assert_file_contains "$HOME/tmp/hermes-agent/beta/hermes-agent-general:/workspace/general" "$PODMAN_LOG" 'shell should mount the workspace path into the CLI container'
assert_file_contains 'rename abcdef1234567890fedcba0987654321abcdef1234567890fedcba0987654321 hermes-agent-0.10.0-20260417-120000-abcdef123456-beta-cli-abcdef123456' "$PODMAN_LOG" 'shell should rename the CLI container to include the first 12 chars of the real container id'
assert_file_contains 'hermes-agent-0.10.0-20260417-120000-abcdef123456 nu' "$PODMAN_LOG" 'shell should create the CLI container with the configured shell command'
assert_file_contains 'start -ai hermes-agent-0.10.0-20260417-120000-abcdef123456-beta-cli-abcdef123456' "$PODMAN_LOG" 'shell should attach by starting the renamed CLI container'
assert_file_contains 'rm -f hermes-agent-0.10.0-20260417-120000-abcdef123456-beta-cli-abcdef123456' "$PODMAN_LOG" 'shell should remove the renamed CLI container after the session ends'
assert_file_not_contains '--pod' "$PODMAN_LOG" 'shell CLI container should not join the runtime pod'
assert_file_not_contains '-p ' "$PODMAN_LOG" 'shell CLI container should not publish ports'
assert_file_not_contains 'exec -i hermes-agent-0.10.0-20260417-120000-abcdef123456-beta-gateway nu' "$PODMAN_LOG" 'shell should not exec into the persistent gateway container'

# This checks that one workspace argument skips the picker and still opens nushell.
: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/agent/shared/hermes-agent-shell" alpha >/dev/null 2>"$SHELL_STDERR"

assert_file_not_contains 'Selection:' "$SHELL_STDERR" 'shell should not show the picker when a workspace argument is provided'
assert_file_contains 'create --name hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-cli --workdir /workspace/general' "$PODMAN_LOG" 'shell should accept a workspace argument and create the temporary CLI container'
assert_file_contains 'start -ai hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-cli-abcdef123456' "$PODMAN_LOG" 'shell should attach through the renamed CLI container when a workspace argument is provided'

# This checks that a rename failure cleans up the temporary CLI container name.
: >"$PODMAN_LOG"
if PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_CLI_RENAME_MODE='fail' bash "$ROOT/scripts/agent/shared/hermes-agent-shell" alpha >/dev/null 2>"$TMP_DIR/rename-fail.stderr"; then
  fail 'shell should fail when renaming the CLI container fails'
fi

assert_file_contains 'rename failed' "$TMP_DIR/rename-fail.stderr" 'shell should surface CLI rename failures'
if ! grep -Fxq -- 'rm -f hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-cli' "$PODMAN_LOG"; then
  fail 'shell should clean up the temporary CLI container when rename fails'
fi

# This checks that a stale exact CLI container name is removed before launching a replacement.
: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_CLI_COLLISION_MODE='exact' bash "$ROOT/scripts/agent/shared/hermes-agent-shell" alpha >/dev/null 2>"$SHELL_STDERR"

assert_file_contains 'rm hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-cli' "$PODMAN_LOG" 'shell should remove a stale exact CLI container name before opening a replacement'
assert_file_contains 'create --name hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-cli --workdir /workspace/general' "$PODMAN_LOG" 'shell should create a replacement temporary CLI container after removing the stale exact name'
assert_file_contains 'rename abcdef1234567890fedcba0987654321abcdef1234567890fedcba0987654321 hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-cli-abcdef123456' "$PODMAN_LOG" 'shell should rename the replacement CLI container after create'

# This checks that shell removes a leftover renamed CLI session container before launching a new one.
: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_RENAMED_CLI_MODE='leftover' bash "$ROOT/scripts/agent/shared/hermes-agent-shell" alpha >/dev/null 2>"$SHELL_STDERR"

assert_file_contains 'rm -f hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-cli-abcdef123456' "$PODMAN_LOG" 'shell should remove a leftover renamed CLI session container before launching a new one'
assert_file_contains_in_order 'rm -f hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-cli-abcdef123456' 'create --name hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-cli --workdir /workspace/general' "$PODMAN_LOG" 'shell should remove leftover renamed CLI session containers before creating the next CLI container'

# This checks that shell refuses to kill a still-running renamed CLI session container.
: >"$PODMAN_LOG"
if PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_RENAMED_CLI_MODE='running-leftover' bash "$ROOT/scripts/agent/shared/hermes-agent-shell" alpha >/dev/null 2>"$TMP_DIR/running-leftover.stderr"; then
  fail 'shell should fail when a renamed CLI session container is still running'
fi

assert_file_contains 'Hermes CLI session container already running for alpha: hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-cli-abcdef123456' "$TMP_DIR/running-leftover.stderr" 'shell should explain running renamed CLI session collisions'

# This checks that shell refuses to kill a still-running exact CLI container.
: >"$PODMAN_LOG"
if PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_CLI_COLLISION_MODE='running' bash "$ROOT/scripts/agent/shared/hermes-agent-shell" alpha >/dev/null 2>"$TMP_DIR/running-cli.stderr"; then
  fail 'shell should fail when the exact CLI container name is already running'
fi

assert_file_contains 'Hermes CLI container already running for alpha.' "$TMP_DIR/running-cli.stderr" 'shell should explain live CLI container name collisions'
assert_file_not_contains 'rm hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-cli' "$PODMAN_LOG" 'shell should not remove a still-running CLI container'

# This checks that shell does not remove an exact-name CLI container with the wrong workspace mount.
: >"$PODMAN_LOG"
if PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_CLI_COLLISION_MODE='mount-mismatch' bash "$ROOT/scripts/agent/shared/hermes-agent-shell" alpha >/dev/null 2>"$TMP_DIR/wrong-mount-cli.stderr"; then
  fail 'shell should fail when the exact CLI name belongs to a different workspace mount'
fi

assert_file_contains 'Hermes CLI container name already in use with a different workspace mount for alpha.' "$TMP_DIR/wrong-mount-cli.stderr" 'shell should explain exact-name CLI mount collisions'
assert_file_not_contains 'rm hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-cli' "$PODMAN_LOG" 'shell should not remove an exact-name CLI container with a different workspace mount'

# This checks that shell recovers from a stale launch lock left by a dead process.
printf '999999|stale|%s|alpha\n' "$ROOT" >"$HOME/tmp/hermes-agent/alpha/hermes-agent-home/.hermes-agent-shell-launch.lock"
: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/agent/shared/hermes-agent-shell" alpha >/dev/null 2>"$SHELL_STDERR"

assert_file_contains 'create --name hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-cli --workdir /workspace/general' "$PODMAN_LOG" 'shell should recover from a stale launch lock and still create the temporary CLI container'

# This checks that shell respects an active launch lock for the same worktree and workspace.
sleep 30 &
lock_pid="$!"
lock_started="$(awk '{print $22}' "/proc/$lock_pid/stat")"
printf '%s|%s|%s|alpha\n' "$lock_pid" "$lock_started" "$ROOT" >"$HOME/tmp/hermes-agent/alpha/hermes-agent-home/.hermes-agent-shell-launch.lock"
: >"$PODMAN_LOG"
if PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/agent/shared/hermes-agent-shell" alpha >/dev/null 2>"$TMP_DIR/active-lock.stderr"; then
  kill "$lock_pid" >/dev/null 2>&1 || true
  fail 'shell should fail when another launch lock is still active'
fi
kill "$lock_pid" >/dev/null 2>&1 || true

assert_file_contains 'Another Hermes CLI launch is already in progress for alpha.' "$TMP_DIR/active-lock.stderr" 'shell should explain active launch locks'

# This checks that an explicit in-container command passes through unchanged.
: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/agent/shared/hermes-agent-shell" alpha hermes auth list >/dev/null 2>"$SHELL_STDERR"

assert_file_contains 'create --name hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-cli --workdir /workspace/general' "$PODMAN_LOG" 'shell should create the temporary CLI container for explicit commands'
assert_file_contains 'hermes-agent-0.10.0-20260417-120000-abcdef123456 hermes auth list' "$PODMAN_LOG" 'shell should forward an explicit command vector into the created CLI container'
assert_file_contains 'start -ai hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-cli-abcdef123456' "$PODMAN_LOG" 'shell should start the renamed CLI container for explicit commands'

# This checks that a non-Hermes command also passes through unchanged.
: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/agent/shared/hermes-agent-shell" alpha python -V >/dev/null 2>"$SHELL_STDERR"

assert_file_contains 'hermes-agent-0.10.0-20260417-120000-abcdef123456 python -V' "$PODMAN_LOG" 'shell should forward non-Hermes commands into the created CLI container'
assert_file_contains 'start -ai hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-cli-abcdef123456' "$PODMAN_LOG" 'shell should start the renamed CLI container for non-Hermes commands'

# This checks that a typed workspace still has to be one of the configured ones.
if PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" bash "$ROOT/scripts/agent/shared/hermes-agent-shell" gamma >/dev/null 2>"$TMP_DIR/unconfigured.stderr"; then
  fail 'shell should reject an unconfigured workspace argument'
fi

assert_file_contains 'Workspace gamma is not configured.' "$TMP_DIR/unconfigured.stderr" 'shell should reject unconfigured workspace arguments before looking up containers'

# This checks that localhost-prefixed local images are normalized before CLI container naming.
: >"$PODMAN_LOG"
printf 'beta\n' | PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_IMAGE_MODE="localhost" bash "$ROOT/scripts/agent/shared/hermes-agent-shell" >/dev/null

assert_file_contains 'create --name hermes-agent-0.10.0-20260417-120000-abcdef123456-beta-cli' "$PODMAN_LOG" 'shell should normalize localhost image names before naming temporary CLI containers'
assert_file_contains 'rename abcdef1234567890fedcba0987654321abcdef1234567890fedcba0987654321 hermes-agent-0.10.0-20260417-120000-abcdef123456-beta-cli-abcdef123456' "$PODMAN_LOG" 'shell should rename normalized-image CLI containers using the returned container id'

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

# This checks that the shared attached-start helper drops tty mode when stdin is not interactive.
: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" bash -c 'set -euo pipefail; source "$1"; hermes_run_podman_attached_start_command demo-container' _ "$ROOT/lib/shell/shared/common.sh" </dev/null >/dev/null

assert_file_contains 'start -ai demo-container' "$PODMAN_LOG" 'shared attached-start helper should keep stdin open without tty mode when stdin is not interactive'

# This checks that interactive Linux auto mode falls back to plain Podman `-it` when no wrapper is needed.
: >"$PODMAN_LOG"
PATH="$FAKE_BIN:/usr/bin:/bin" ROOT="$ROOT" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_AGENT_FORCE_EXEC_TTY="1" OSTYPE='linux-gnu' /bin/bash -c 'set -euo pipefail; source "$1"; hermes_exec_podman_interactive_command exec demo-container bash' _ "$ROOT/lib/shell/shared/common.sh" >/dev/null

assert_file_contains 'exec -it demo-container bash' "$PODMAN_LOG" 'shared exec helper should use plain interactive Podman when auto mode does not need script'

# This checks that interactive Linux attached-start mode uses plain Podman `-ai` when no wrapper is needed.
: >"$PODMAN_LOG"
PATH="$FAKE_BIN:/usr/bin:/bin" ROOT="$ROOT" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_AGENT_FORCE_EXEC_TTY="1" OSTYPE='linux-gnu' /bin/bash -c 'set -euo pipefail; source "$1"; hermes_run_podman_attached_start_command demo-container' _ "$ROOT/lib/shell/shared/common.sh" >/dev/null

assert_file_contains 'start -ai demo-container' "$PODMAN_LOG" 'shared attached-start helper should use plain interactive Podman when auto mode does not need script'

# This checks that explicit script mode fails clearly when `script` is not installed.
if PATH="$FAKE_BIN" ROOT="$ROOT" HERMES_AGENT_FORCE_EXEC_TTY="1" HERMES_AGENT_PODMAN_TTY_WRAPPER="script" /bin/bash -c 'set -euo pipefail; source "$1"; hermes_exec_podman_interactive_command exec demo-container bash' _ "$ROOT/lib/shell/shared/common.sh" >/dev/null 2>"$TMP_DIR/script-missing.stderr"; then
  fail 'shared exec helper should fail when explicit script mode is requested but unavailable'
fi

assert_file_contains 'HERMES_AGENT_PODMAN_TTY_WRAPPER=script requires script to be installed.' "$TMP_DIR/script-missing.stderr" 'shared exec helper should explain missing script dependency'

printf 'hermes-agent-shell behavior checks passed\n'
