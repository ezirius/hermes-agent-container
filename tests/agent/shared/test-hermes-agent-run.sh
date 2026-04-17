#!/usr/bin/env bash

set -euo pipefail

# This test checks that the run script picks the right workspace, paths, ports, and containers.

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

# This fake Podman returns controlled image and container answers for each test case.
cat >"$FAKE_BIN/podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$HERMES_TEST_PODMAN_LOG"

case "$1" in
  images)
    case "${HERMES_TEST_IMAGE_MODE:-present}" in
      present)
        printf 'hermes-agent-0.10.0-20260417-120000-123\n'
        ;;
      localhost)
        printf 'localhost/hermes-agent-0.10.0-20260417-120000-123\n'
        ;;
      multiple)
        printf 'localhost/hermes-agent-0.10.0-20260417-120001-124\n'
        printf 'hermes-agent-0.10.0-20260417-120000-123\n'
        ;;
    esac
    ;;
  ps)
    if [[ "$2" == '-aq' ]]; then
      if [[ "${HERMES_TEST_STALE_MODE:-present}" == "present" ]]; then
        printf 'stale-1\nstale-2\n'
      elif [[ "${HERMES_TEST_STALE_MODE:-present}" == "same-name" ]]; then
        printf 'hermes-agent-alpha-0.10.0-20260417-120000-123\n'
      fi
    elif [[ "${HERMES_TEST_RUNNING_MODE:-running}" == "dies-before-exec" ]]; then
      if [[ -f "${HERMES_TEST_PODMAN_LOG}.ran" && ! -f "${HERMES_TEST_PODMAN_LOG}.running-once" ]]; then
        : >"${HERMES_TEST_PODMAN_LOG}.running-once"
        case "$*" in
          *beta*)
            printf 'hermes-agent-beta-0.10.0-20260417-120000-123\n'
            ;;
          *)
            printf 'hermes-agent-alpha-0.10.0-20260417-120000-123\n'
            ;;
        esac
      fi
    elif [[ "${HERMES_TEST_RUNNING_MODE:-running}" == "dies-after-open" ]]; then
      if [[ ! -f "${HERMES_TEST_OPEN_LOG}.opened" ]]; then
        case "$*" in
          *beta*)
            printf 'hermes-agent-beta-0.10.0-20260417-120000-123\n'
            ;;
          *)
            printf 'hermes-agent-alpha-0.10.0-20260417-120000-123\n'
            ;;
        esac
      fi
    elif [[ "${HERMES_TEST_RUNNING_MODE:-running}" == "stopped" && -f "${HERMES_TEST_PODMAN_LOG}.started" ]]; then
      case "$*" in
        *beta*)
          printf 'hermes-agent-beta-0.10.0-20260417-120000-123\n'
          ;;
        *)
          printf 'hermes-agent-alpha-0.10.0-20260417-120000-123\n'
          ;;
      esac
    elif [[ "${HERMES_TEST_RUNNING_MODE:-running}" != "never" && "${HERMES_TEST_RUNNING_MODE:-running}" != "stopped" ]]; then
      case "$*" in
        *beta*)
          printf 'hermes-agent-beta-0.10.0-20260417-120000-123\n'
          ;;
        *)
          printf 'hermes-agent-alpha-0.10.0-20260417-120000-123\n'
          ;;
      esac
    fi
    ;;
  rm)
    ;;
  run)
    if [[ "${HERMES_TEST_RUN_FAIL:-0}" == "1" ]]; then
      exit 1
    fi
    : >"${HERMES_TEST_PODMAN_LOG}.ran"
    printf 'new-container\n'
    ;;
  start)
    : >"${HERMES_TEST_PODMAN_LOG}.started"
    ;;
  exec)
    if [[ "${HERMES_TEST_EXEC_FAIL:-0}" == "1" ]]; then
      exit 1
    fi
    ;;
esac
EOF

# These fake opener commands let the test watch dashboard-open behavior on the host.
cat >"$FAKE_BIN/open" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${HERMES_TEST_OPEN_FAIL:-0}" == "1" ]]; then
  exit 1
fi
: >"${HERMES_TEST_OPEN_LOG}.opened"
printf '%s\n' "$*" >>"$HERMES_TEST_OPEN_LOG"
EOF

cat >"$FAKE_BIN/xdg-open" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${HERMES_TEST_XDG_OPEN_FAIL:-0}" == "1" ]]; then
  exit 1
fi
: >"${HERMES_TEST_OPEN_LOG}.opened"
printf '%s\n' "$*" >>"$HERMES_TEST_OPEN_LOG"
EOF

chmod +x "$FAKE_BIN/podman" "$FAKE_BIN/open" "$FAKE_BIN/xdg-open"

# This test config keeps the workspace names, paths, and offsets predictable.
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
HERMES_AGENT_OPEN_COMMAND="auto"
HERMES_AGENT_BASE_PATH="${TMP_DIR}/base"
HERMES_AGENT_WORKSPACES="alpha:100 beta:200"
HERMES_AGENT_CONTAINER_HOME="/home/hermes-agent"
HERMES_AGENT_CONTAINER_WORKSPACE="/workspace/general"
HERMES_AGENT_HOST_HOME_DIRNAME="hermes-agent-home"
HERMES_AGENT_HOST_WORKSPACE_DIRNAME="hermes-agent-general"
EOF

PODMAN_LOG="$TMP_DIR/podman.log"
OPEN_LOG="$TMP_DIR/open.log"
RUN_STDOUT="$TMP_DIR/run.stdout"
RUN_STDERR="$TMP_DIR/run.stderr"

# This is the normal happy path for choosing beta and starting its workspace container.
printf '2\n' | PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" bash "$ROOT/scripts/agent/shared/hermes-agent-run" >"$RUN_STDOUT" 2>"$RUN_STDERR"

# These checks prove the script used the saved workspace offset, mounts, and dashboard URL.
assert_file_contains 'Selection:' "$RUN_STDERR" 'run should show an explicit selection prompt'
assert_file_contains '--filter name=^hermes-agent-beta-' "$PODMAN_LOG" 'run should clean matching workspace containers'
assert_file_contains '-p 9434:9234' "$PODMAN_LOG" 'run should derive host port from config offset'
assert_file_contains "$TMP_DIR/base/beta/hermes-agent-home:/home/hermes-agent" "$PODMAN_LOG" 'run should derive host home from shared base path'
assert_file_contains "$TMP_DIR/base/beta/hermes-agent-general:/workspace/general" "$PODMAN_LOG" 'run should derive host workspace from shared base path'
assert_file_contains 'http://127.0.0.1:9434' "$OPEN_LOG" 'run should open derived dashboard url'
assert_file_contains 'http://127.0.0.1:9434' "$OPEN_LOG" 'run should open derived dashboard url'
assert_file_contains 'exec -i hermes-agent-beta-0.10.0-20260417-120000-123 hermes' "$PODMAN_LOG" 'run should exec configured chat command'

# This checks that localhost-prefixed local images are normalized before use.
: >"$PODMAN_LOG"
: >"$OPEN_LOG"
printf '1\n' | PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_IMAGE_MODE='localhost' bash "$ROOT/scripts/agent/shared/hermes-agent-run" >"$RUN_STDOUT" 2>"$RUN_STDERR"

assert_file_contains 'run -d --name hermes-agent-alpha-0.10.0-20260417-120000-123' "$PODMAN_LOG" 'run should normalize localhost-prefixed local images before naming the container'
assert_file_contains 'exec -i hermes-agent-alpha-0.10.0-20260417-120000-123 hermes' "$PODMAN_LOG" 'run should attach using the normalized container name'

# This checks that one workspace argument skips the picker and still runs correctly.
: >"$PODMAN_LOG"
: >"$OPEN_LOG"
PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" bash "$ROOT/scripts/agent/shared/hermes-agent-run" alpha >"$RUN_STDOUT" 2>"$RUN_STDERR"

assert_file_contains 'run -d --name hermes-agent-alpha-0.10.0-20260417-120000-123' "$PODMAN_LOG" 'run should accept a workspace argument and skip the picker'
assert_file_not_contains 'Selection:' "$RUN_STDERR" 'run should not show the picker when a workspace argument is provided'

# This checks that extra arguments are rejected with a clear usage message.
if PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" bash "$ROOT/scripts/agent/shared/hermes-agent-run" alpha extra >/dev/null 2>"$TMP_DIR/run-args.stderr"; then
  fail 'run should reject more than one argument'
fi

assert_file_contains 'This script takes zero or one argument: [workspace].' "$TMP_DIR/run-args.stderr" 'run should explain its accepted argument count'

# This checks that a broken opener does not stop the CLI from attaching.
: >"$PODMAN_LOG"
: >"$OPEN_LOG"
printf '1\n' | PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_XDG_OPEN_FAIL='1' bash "$ROOT/scripts/agent/shared/hermes-agent-run" >"$RUN_STDOUT"

assert_file_contains 'exec -i hermes-agent-alpha-0.10.0-20260417-120000-123 hermes' "$PODMAN_LOG" 'run should still attach when the dashboard opener fails'

# This checks that the script still works when the host has no opener at all.
: >"$PODMAN_LOG"
: >"$OPEN_LOG"
printf '1\n' | PATH="$FAKE_BIN:/bin" OSTYPE='linux-gnu' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" bash "$ROOT/scripts/agent/shared/hermes-agent-run" >"$RUN_STDOUT"

assert_file_contains 'exec -i hermes-agent-alpha-0.10.0-20260417-120000-123 hermes' "$PODMAN_LOG" 'run should still attach when no supported opener exists on the host'

# This checks that the script fails clearly when the container never becomes runnable.
: >"$PODMAN_LOG"
if printf '1\n' | PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_RUNNING_MODE='never' HERMES_TEST_EXEC_FAIL='1' bash "$ROOT/scripts/agent/shared/hermes-agent-run" >"$RUN_STDOUT" 2>"$TMP_DIR/not-running.stderr"; then
  fail 'run should fail clearly when the container never becomes runnable'
fi

assert_file_contains 'Hermes Agent container failed to stay running: hermes-agent-alpha-0.10.0-20260417-120000-123' "$TMP_DIR/not-running.stderr" 'run should report a clear startup error when the container is not running after startup'

# This checks that stale containers are not removed when the replacement never starts.
: >"$PODMAN_LOG"
if printf '1\n' | PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_RUN_FAIL='1' bash "$ROOT/scripts/agent/shared/hermes-agent-run" >"$RUN_STDOUT" 2>"$TMP_DIR/run-fail.stderr"; then
  fail 'run should fail when podman run fails'
fi

# This helper checks that a file does not contain text we should never have written.
assert_file_not_contains() {
  local needle="$1"
  local file_path="$2"
  local message="$3"

  if grep -Fq -- "$needle" "$file_path"; then
    fail "$message: unexpected [$needle] in $file_path"
  fi
}

# These checks prove old containers are left alone when replacement startup fails.
assert_file_not_contains 'rm -f stale-1' "$PODMAN_LOG" 'run should not remove existing workspace containers before replacement startup succeeds'
assert_file_not_contains 'rm -f stale-2' "$PODMAN_LOG" 'run should not remove other workspace containers before replacement startup succeeds'

# This checks that old containers are still kept when a new container starts and then dies right away.
: >"$PODMAN_LOG"
if printf '1\n' | PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_RUNNING_MODE='never' bash "$ROOT/scripts/agent/shared/hermes-agent-run" >"$RUN_STDOUT" 2>"$TMP_DIR/crash-after-start.stderr"; then
  fail 'run should fail when a replacement container does not stay running'
fi

assert_file_not_contains 'rm -f stale-1' "$PODMAN_LOG" 'run should not remove old containers when the replacement exits before the running check passes'
assert_file_not_contains 'rm -f stale-2' "$PODMAN_LOG" 'run should keep other old containers when the replacement exits before the running check passes'

# This checks that the wrapper fails cleanly if the container dies after startup but before exec.
: >"$PODMAN_LOG"
: >"$OPEN_LOG"
rm -f "${PODMAN_LOG}.ran"
rm -f "${PODMAN_LOG}.running-once"
if printf '1\n' | PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_RUNNING_MODE='dies-before-exec' bash "$ROOT/scripts/agent/shared/hermes-agent-run" >"$RUN_STDOUT" 2>"$TMP_DIR/dies-before-exec.stderr"; then
  fail 'run should fail when the container stops after the initial running check'
fi

assert_file_contains 'Hermes Agent container stopped before attach: hermes-agent-alpha-0.10.0-20260417-120000-123' "$TMP_DIR/dies-before-exec.stderr" 'run should explain when the container dies after startup but before exec'
assert_file_not_contains 'exec -i hermes-agent-alpha-0.10.0-20260417-120000-123 hermes' "$PODMAN_LOG" 'run should not try to exec into a container that has already stopped'

# This checks that the wrapper still fails cleanly if the container dies after the dashboard open step.
: >"$PODMAN_LOG"
: >"$OPEN_LOG"
rm -f "${OPEN_LOG}.opened"
if printf '1\n' | PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_RUNNING_MODE='dies-after-open' bash "$ROOT/scripts/agent/shared/hermes-agent-run" >"$RUN_STDOUT" 2>"$TMP_DIR/dies-after-open.stderr"; then
  fail 'run should fail when the container stops after the dashboard open step'
fi

assert_file_contains 'Hermes Agent container stopped before attach: hermes-agent-alpha-0.10.0-20260417-120000-123' "$TMP_DIR/dies-after-open.stderr" 'run should explain when the container dies after the dashboard open step'
assert_file_not_contains 'exec -i hermes-agent-alpha-0.10.0-20260417-120000-123 hermes' "$PODMAN_LOG" 'run should not try to exec into a container that stops during dashboard open handling'

# This checks that an exact matching container is reused instead of recreated.
: >"$PODMAN_LOG"
: >"$OPEN_LOG"
printf '1\n' | PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_STALE_MODE='same-name' bash "$ROOT/scripts/agent/shared/hermes-agent-run" >"$RUN_STDOUT"

assert_file_not_contains 'run -d --name hermes-agent-alpha-0.10.0-20260417-120000-123' "$PODMAN_LOG" 'run should reuse an existing matching workspace container instead of recreating it'
assert_file_contains 'exec -i hermes-agent-alpha-0.10.0-20260417-120000-123 hermes' "$PODMAN_LOG" 'run should attach to the existing matching workspace container'

# This checks that a matching stopped container is started instead of replaced.
: >"$PODMAN_LOG"
: >"$OPEN_LOG"
rm -f "$PODMAN_LOG.started"
printf '1\n' | PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_STALE_MODE='same-name' HERMES_TEST_RUNNING_MODE='stopped' bash "$ROOT/scripts/agent/shared/hermes-agent-run" >"$RUN_STDOUT"

assert_file_contains 'start hermes-agent-alpha-0.10.0-20260417-120000-123' "$PODMAN_LOG" 'run should start a matching stopped workspace container before attaching'
assert_file_contains 'exec -i hermes-agent-alpha-0.10.0-20260417-120000-123 hermes' "$PODMAN_LOG" 'run should attach after starting a matching stopped workspace container'

# This rewrites the config with a bad offset to check config validation.
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
HERMES_AGENT_OPEN_COMMAND="auto"
HERMES_AGENT_BASE_PATH="${TMP_DIR}/base"
HERMES_AGENT_WORKSPACES="alpha:not-a-number beta:200"
HERMES_AGENT_CONTAINER_HOME="/home/hermes-agent"
HERMES_AGENT_CONTAINER_WORKSPACE="/workspace/general"
HERMES_AGENT_HOST_HOME_DIRNAME="hermes-agent-home"
HERMES_AGENT_HOST_WORKSPACE_DIRNAME="hermes-agent-general"
EOF

if printf '1\n' | PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" bash "$ROOT/scripts/agent/shared/hermes-agent-run" >"$RUN_STDOUT" 2>"$TMP_DIR/offset.stderr"; then
  fail 'run should fail when a workspace offset is non-numeric'
fi

assert_file_contains 'Workspace offset for alpha must be numeric.' "$TMP_DIR/offset.stderr" 'run should explain invalid workspace offsets'

# This rewrites the config with a bad workspace name to check name validation.
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
HERMES_AGENT_OPEN_COMMAND="auto"
HERMES_AGENT_BASE_PATH="${TMP_DIR}/base"
HERMES_AGENT_WORKSPACES="alpha[1]:100 beta:200"
HERMES_AGENT_CONTAINER_HOME="/home/hermes-agent"
HERMES_AGENT_CONTAINER_WORKSPACE="/workspace/general"
HERMES_AGENT_HOST_HOME_DIRNAME="hermes-agent-home"
HERMES_AGENT_HOST_WORKSPACE_DIRNAME="hermes-agent-general"
EOF

if printf '1\n' | PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" bash "$ROOT/scripts/agent/shared/hermes-agent-run" >"$RUN_STDOUT" 2>"$TMP_DIR/workspace-name.stderr"; then
  fail 'run should fail when a workspace name contains regex characters'
fi

assert_file_contains 'Workspace name alpha[1] may only contain letters, numbers, dots, underscores, and hyphens.' "$TMP_DIR/workspace-name.stderr" 'run should explain invalid workspace names'

# These direct helper checks make sure regex escaping and opener validation stay safe.
assert_equals '^hermes-agent-alpha\.one-0\.10\.0-' "$(bash -lc 'set -euo pipefail; source "$1"; hermes_container_filter_regex "alpha.one"' _ "$ROOT/lib/shell/shared/common.sh")" 'workspace regex helpers should escape dots and anchor the workspace boundary against the version'
assert_equals '^hermes-agent-0\.10\.0-[0-9]{8}-[0-9]{6}-[0-9]{3}$' "$(bash -lc 'set -euo pipefail; source "$1"; hermes_image_name_regex' _ "$ROOT/lib/shell/shared/common.sh")" 'image regex helper should escape dots in the configured version'

if bash -lc 'set -euo pipefail; source "$1"; HERMES_AGENT_OPEN_COMMAND="bad-opener"; hermes_open_dashboard "http://127.0.0.1:1"' _ "$ROOT/lib/shell/shared/common.sh" >/dev/null 2>"$TMP_DIR/open-command.stderr"; then
  fail 'invalid opener config should fail fast'
fi

assert_file_contains 'Unsupported HERMES_AGENT_OPEN_COMMAND: bad-opener' "$TMP_DIR/open-command.stderr" 'invalid opener config should surface a clear error'

# This restores a good config before checking menu and missing-image failures.
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
HERMES_AGENT_OPEN_COMMAND="auto"
HERMES_AGENT_BASE_PATH="${TMP_DIR}/base"
HERMES_AGENT_WORKSPACES="alpha:100 beta:200"
HERMES_AGENT_CONTAINER_HOME="/home/hermes-agent"
HERMES_AGENT_CONTAINER_WORKSPACE="/workspace/general"
HERMES_AGENT_HOST_HOME_DIRNAME="hermes-agent-home"
HERMES_AGENT_HOST_WORKSPACE_DIRNAME="hermes-agent-general"
EOF

if printf '9\n' | PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" bash "$ROOT/scripts/agent/shared/hermes-agent-run" >/dev/null 2>"$TMP_DIR/invalid.stderr"; then
  fail 'run should reject invalid workspace selection'
fi

assert_file_contains 'Please pick one of the configured workspaces.' "$TMP_DIR/invalid.stderr" 'run should explain invalid workspace selection'

# This checks that the script fails clearly when no image exists yet.
if printf '1\n' | PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_IMAGE_MODE="missing" bash "$ROOT/scripts/agent/shared/hermes-agent-run" >/dev/null 2>"$TMP_DIR/missing.stderr"; then
  fail 'run should fail when no image exists'
fi

assert_file_contains 'No built Hermes Agent image found.' "$TMP_DIR/missing.stderr" 'run should explain missing image'

printf 'hermes-agent-run behavior checks passed\n'
