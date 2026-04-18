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
    elif [[ "${HERMES_TEST_RUNNING_MODE:-running}" == "exact-match-dies-before-exec" ]]; then
      if [[ ! -f "${HERMES_TEST_PODMAN_LOG}.ran" ]]; then
        if [[ ! -f "${HERMES_TEST_PODMAN_LOG}.running-once" ]]; then
          : >"${HERMES_TEST_PODMAN_LOG}.running-once"
          case "$*" in
            *beta*)
              printf 'hermes-agent-beta-0.10.0-20260417-120000-123\n'
              ;;
            *)
              printf 'hermes-agent-alpha-0.10.0-20260417-120000-123\n'
              ;;
          esac
        elif [[ ! -f "${HERMES_TEST_PODMAN_LOG}.running-twice" ]]; then
          : >"${HERMES_TEST_PODMAN_LOG}.running-twice"
          case "$*" in
            *beta*)
              printf 'hermes-agent-beta-0.10.0-20260417-120000-123\n'
              ;;
            *)
              printf 'hermes-agent-alpha-0.10.0-20260417-120000-123\n'
              ;;
          esac
        fi
      else
        case "$*" in
          *beta*)
            printf 'hermes-agent-beta-0.10.0-20260417-120000-123\n'
            ;;
          *)
            printf 'hermes-agent-alpha-0.10.0-20260417-120000-123\n'
            ;;
        esac
      fi
    elif [[ "${HERMES_TEST_RUNNING_MODE:-running}" == "started-dies-during-wait" ]]; then
      if [[ -f "${HERMES_TEST_PODMAN_LOG}.ran" ]]; then
        case "$*" in
          *beta*)
            printf 'hermes-agent-beta-0.10.0-20260417-120000-123\n'
            ;;
          *)
            printf 'hermes-agent-alpha-0.10.0-20260417-120000-123\n'
            ;;
        esac
      fi
    elif [[ "${HERMES_TEST_RUNNING_MODE:-running}" == "started-dies-before-exec" ]]; then
      if [[ -f "${HERMES_TEST_PODMAN_LOG}.ran" ]]; then
        case "$*" in
          *beta*)
            printf 'hermes-agent-beta-0.10.0-20260417-120000-123\n'
            ;;
          *)
            printf 'hermes-agent-alpha-0.10.0-20260417-120000-123\n'
            ;;
        esac
      elif [[ -f "${HERMES_TEST_PODMAN_LOG}.started" && ! -f "${HERMES_TEST_PODMAN_LOG}.running-once" ]]; then
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
    elif [[ "${HERMES_TEST_RUNNING_MODE:-running}" == "dies-during-dashboard-window" ]]; then
      if [[ -f "${HERMES_TEST_OPEN_LOG}.opened" && -f "${HERMES_TEST_SLEEP_LOG}.post-open-1" ]]; then
        exit 0
      fi

      case "$*" in
        *beta*)
          printf 'hermes-agent-beta-0.10.0-20260417-120000-123\n'
          ;;
        *)
          printf 'hermes-agent-alpha-0.10.0-20260417-120000-123\n'
          ;;
      esac
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
  port)
    case "${HERMES_TEST_PORT_MODE:-loopback}" in
      public)
        printf '0.0.0.0:9234\n'
        ;;
      *)
        printf '127.0.0.1:9234\n'
        ;;
    esac
    ;;
  inspect)
    if [[ "${HERMES_TEST_DIAGNOSTICS_FAIL:-0}" == "1" ]]; then
      exit 1
    fi
    case "$*" in
      *'.ImageName'*)
        printf 'image=hermes-agent-0.10.0-20260417-120000-123\n'
        ;;
      *)
        printf 'status=exited running=false exit_code=125\n'
        ;;
    esac
    ;;
  logs)
    if [[ "${HERMES_TEST_DIAGNOSTICS_FAIL:-0}" == "1" ]]; then
      exit 1
    fi
    printf 'boot line 1\nboot line 2\n'
    ;;
  exec)
    if [[ "$*" == *'hermes setup'* ]]; then
      if [[ "${HERMES_TEST_HEALTH_MODE:-healthy}" == "first-run-setup" ]]; then
        : >"${HERMES_TEST_PODMAN_LOG}.setup-complete"
      fi
    fi

    if [[ "$*" == *'config.toml'* && "$*" != *'gateway_state.json'* ]]; then
      if [[ "${HERMES_TEST_HEALTH_MODE:-healthy}" == "first-run-setup" && ! -f "${HERMES_TEST_PODMAN_LOG}.setup-complete" ]]; then
        exit 1
      fi

      exit 0
    fi

    if [[ "$*" == *'gateway_state.json'* ]]; then
      probe_log="${HERMES_TEST_PODMAN_LOG}.health-probes"
      probe_count="$(wc -l <"$probe_log" 2>/dev/null || printf '0')"
      printf 'probe\n' >>"$probe_log"

      case "${HERMES_TEST_HEALTH_MODE:-healthy}" in
        first-run-setup)
          if [[ ! -f "${HERMES_TEST_PODMAN_LOG}.setup-complete" ]]; then
            exit 1
          fi
          ;;
        delayed-healthy)
          if (( probe_count < 2 )); then
            exit 1
          fi
          ;;
        delayed-healthy-after-entrypoint-slack)
          if (( probe_count < 10 )); then
            exit 1
          fi
          ;;
        setup-incomplete|services-unhealthy)
          exit 1
          ;;
        setup-incomplete-once|services-unhealthy-once)
          if [[ ! -f "${HERMES_TEST_PODMAN_LOG}.ran" ]]; then
            exit 1
          fi
          ;;
      esac

      exit 0
    fi

    if [[ "${HERMES_TEST_HEALTH_MODE:-healthy}" == "delayed-healthy" ]]; then
      probe_count="$(wc -l <"${HERMES_TEST_PODMAN_LOG}.health-probes" 2>/dev/null || printf '0')"
      if (( probe_count < 3 )); then
        : >"${HERMES_TEST_PODMAN_LOG}.attached-before-healthy"
      fi
    fi

    if [[ "${HERMES_TEST_EXEC_FAIL:-0}" == "1" ]]; then
      exit 1
    fi
    ;;
esac
EOF

# This fake sleep lets the test distinguish pre-open waits from post-open readiness checks.
cat >"$FAKE_BIN/sleep" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${HERMES_TEST_SLEEP_LOG:-}" ]]; then
  exit 0
fi

printf '%s\n' "$*" >>"$HERMES_TEST_SLEEP_LOG"

if [[ -f "${HERMES_TEST_OPEN_LOG}.opened" ]]; then
  post_open_count="$(grep -c '^' "$HERMES_TEST_SLEEP_LOG" 2>/dev/null || true)"
  : >"${HERMES_TEST_SLEEP_LOG}.post-open-${post_open_count}"
fi
EOF

# These fake opener commands let the test watch dashboard-open behavior on the host.
cat >"$FAKE_BIN/open" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${HERMES_TEST_OPEN_FAIL:-0}" == "1" ]]; then
  exit 1
fi

if [[ "${HERMES_TEST_HEALTH_MODE:-healthy}" == "delayed-healthy" ]]; then
  probe_count="$(wc -l <"${HERMES_TEST_PODMAN_LOG}.health-probes" 2>/dev/null || printf '0')"
  if (( probe_count < 3 )); then
    : >"${HERMES_TEST_PODMAN_LOG}.opened-before-healthy"
  fi
fi

: >"${HERMES_TEST_OPEN_LOG}.opened"
printf 'host-open %s\n' "$*" >>"$HERMES_TEST_PODMAN_LOG"
printf '%s\n' "$*" >>"$HERMES_TEST_OPEN_LOG"
EOF

cat >"$FAKE_BIN/xdg-open" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${HERMES_TEST_XDG_OPEN_FAIL:-0}" == "1" ]]; then
  exit 1
fi

if [[ "${HERMES_TEST_HEALTH_MODE:-healthy}" == "delayed-healthy" ]]; then
  probe_count="$(wc -l <"${HERMES_TEST_PODMAN_LOG}.health-probes" 2>/dev/null || printf '0')"
  if (( probe_count < 3 )); then
    : >"${HERMES_TEST_PODMAN_LOG}.opened-before-healthy"
  fi
fi

: >"${HERMES_TEST_OPEN_LOG}.opened"
printf 'host-open %s\n' "$*" >>"$HERMES_TEST_PODMAN_LOG"
printf '%s\n' "$*" >>"$HERMES_TEST_OPEN_LOG"
EOF

chmod +x "$FAKE_BIN/podman" "$FAKE_BIN/open" "$FAKE_BIN/xdg-open" "$FAKE_BIN/sleep"

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
SLEEP_LOG="$TMP_DIR/sleep.log"
RUN_STDOUT="$TMP_DIR/run.stdout"
RUN_STDERR="$TMP_DIR/run.stderr"

# This is the normal happy path for choosing beta and starting its workspace container.
printf '2\n' | PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" bash "$ROOT/scripts/agent/shared/hermes-agent-run" >"$RUN_STDOUT" 2>"$RUN_STDERR"

# These checks prove the script used the saved workspace offset, mounts, and dashboard URL.
assert_file_contains 'Selection:' "$RUN_STDERR" 'run should show an explicit selection prompt'
assert_file_contains '--filter name=^hermes-agent-beta-' "$PODMAN_LOG" 'run should clean matching workspace containers'
assert_file_contains '-p 127.0.0.1:9434:9234' "$PODMAN_LOG" 'run should publish the dashboard port on host loopback only'
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
assert_file_contains 'Container image: image=hermes-agent-0.10.0-20260417-120000-123' "$TMP_DIR/not-running.stderr" 'run should print the selected image name when startup fails'
assert_file_contains 'Container state: status=exited running=false exit_code=125' "$TMP_DIR/not-running.stderr" 'run should print a short state summary when startup fails'
assert_file_contains 'Recent container logs:' "$TMP_DIR/not-running.stderr" 'run should print recent logs when startup fails'
assert_file_contains 'boot line 1' "$TMP_DIR/not-running.stderr" 'run should include recent container log output when startup fails'

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

# This checks that the wrapper fails cleanly if the container dies before it ever becomes healthy.
: >"$PODMAN_LOG"
: >"$OPEN_LOG"
rm -f "${PODMAN_LOG}.ran"
rm -f "${PODMAN_LOG}.running-once"
if printf '1\n' | PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_RUNNING_MODE='dies-before-exec' bash "$ROOT/scripts/agent/shared/hermes-agent-run" >"$RUN_STDOUT" 2>"$TMP_DIR/dies-before-exec.stderr"; then
  fail 'run should fail when the container stops after the initial running check'
fi

assert_file_contains 'Hermes Agent container failed to become healthy: hermes-agent-alpha-0.10.0-20260417-120000-123' "$TMP_DIR/dies-before-exec.stderr" 'run should explain when the container dies before it ever becomes healthy'
assert_file_contains 'Container image: image=hermes-agent-0.10.0-20260417-120000-123' "$TMP_DIR/dies-before-exec.stderr" 'run should print the selected image name when the container fails before health checks pass'
assert_file_contains 'Container state: status=exited running=false exit_code=125' "$TMP_DIR/dies-before-exec.stderr" 'run should print a short state summary when the container fails before health checks pass'
assert_file_contains 'Recent container logs:' "$TMP_DIR/dies-before-exec.stderr" 'run should print recent logs when the container fails before health checks pass'
assert_file_contains 'boot line 2' "$TMP_DIR/dies-before-exec.stderr" 'run should include recent container logs when the container fails before health checks pass'
assert_file_not_contains 'exec -i hermes-agent-alpha-0.10.0-20260417-120000-123 hermes' "$PODMAN_LOG" 'run should not try to exec into a container that has already stopped'

# This checks that the wrapper still fails cleanly if the container dies after the dashboard open step.
: >"$PODMAN_LOG"
: >"$OPEN_LOG"
rm -f "${OPEN_LOG}.opened"
if printf '1\n' | PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_RUNNING_MODE='dies-after-open' bash "$ROOT/scripts/agent/shared/hermes-agent-run" >"$RUN_STDOUT" 2>"$TMP_DIR/dies-after-open.stderr"; then
  fail 'run should fail when the container stops after the dashboard open step'
fi

assert_file_contains 'Hermes Agent container stopped before attach: hermes-agent-alpha-0.10.0-20260417-120000-123' "$TMP_DIR/dies-after-open.stderr" 'run should explain when the container dies after the dashboard open step'
assert_file_contains 'Container image: image=hermes-agent-0.10.0-20260417-120000-123' "$TMP_DIR/dies-after-open.stderr" 'run should print the selected image name when the container stops after the dashboard open step'
assert_file_contains 'Container state: status=exited running=false exit_code=125' "$TMP_DIR/dies-after-open.stderr" 'run should print a short state summary when the container stops after the dashboard open step'
assert_file_contains 'Recent container logs:' "$TMP_DIR/dies-after-open.stderr" 'run should print recent logs when the container stops after the dashboard open step'
assert_file_contains 'boot line 1' "$TMP_DIR/dies-after-open.stderr" 'run should include recent container logs when the container stops after the dashboard open step'
assert_file_not_contains 'exec -i hermes-agent-alpha-0.10.0-20260417-120000-123 hermes' "$PODMAN_LOG" 'run should not try to exec into a container that stops during dashboard open handling'

# This checks that startup diagnostics fall back cleanly when Podman cannot inspect or read logs.
: >"$PODMAN_LOG"
if printf '1\n' | PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_RUNNING_MODE='never' HERMES_TEST_DIAGNOSTICS_FAIL='1' bash "$ROOT/scripts/agent/shared/hermes-agent-run" >"$RUN_STDOUT" 2>"$TMP_DIR/diagnostics-fail.stderr"; then
  fail 'run should still fail cleanly when startup diagnostics cannot be collected'
fi

assert_file_contains 'Hermes Agent container failed to stay running: hermes-agent-alpha-0.10.0-20260417-120000-123' "$TMP_DIR/diagnostics-fail.stderr" 'run should keep the main startup error when diagnostics fail'
assert_file_contains 'Container image: unavailable' "$TMP_DIR/diagnostics-fail.stderr" 'run should fall back to an unavailable image summary when inspect fails'
assert_file_contains 'Container state: unavailable' "$TMP_DIR/diagnostics-fail.stderr" 'run should fall back to an unavailable state summary when inspect fails'
assert_file_contains 'Recent container logs: unavailable' "$TMP_DIR/diagnostics-fail.stderr" 'run should fall back to unavailable logs when log collection fails'

# This checks that an exact matching container is reused instead of recreated.
: >"$PODMAN_LOG"
: >"$OPEN_LOG"
printf '1\n' | PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_STALE_MODE='same-name' bash "$ROOT/scripts/agent/shared/hermes-agent-run" >"$RUN_STDOUT"

assert_file_not_contains 'run -d --name hermes-agent-alpha-0.10.0-20260417-120000-123' "$PODMAN_LOG" 'run should reuse an existing matching workspace container instead of recreating it'
assert_file_contains 'exec -i hermes-agent-alpha-0.10.0-20260417-120000-123 hermes' "$PODMAN_LOG" 'run should attach to the existing matching workspace container'

# This checks that a matching running container is replaced when setup or service health is not ready.
: >"$PODMAN_LOG"
: >"$OPEN_LOG"
rm -f "$PODMAN_LOG.ran"
printf '1\n' | PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_STALE_MODE='same-name' HERMES_TEST_HEALTH_MODE='setup-incomplete-once' bash "$ROOT/scripts/agent/shared/hermes-agent-run" >"$RUN_STDOUT"

assert_file_contains 'rm -f hermes-agent-alpha-0.10.0-20260417-120000-123' "$PODMAN_LOG" 'run should remove a matching running container that is still waiting for setup or healthy services'
assert_file_contains 'run -d --name hermes-agent-alpha-0.10.0-20260417-120000-123' "$PODMAN_LOG" 'run should recreate a matching running container that is still waiting for setup or healthy services'
assert_file_contains 'exec -i hermes-agent-alpha-0.10.0-20260417-120000-123 hermes' "$PODMAN_LOG" 'run should attach after recreating a matching running container that was not ready'

# This checks that a first-run container runs interactive setup before opening the dashboard or attaching.
: >"$PODMAN_LOG"
: >"$OPEN_LOG"
rm -f "$PODMAN_LOG.health-probes" "$PODMAN_LOG.setup-complete"
if printf '1\n' | PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_HEALTH_MODE='first-run-setup' bash "$ROOT/scripts/agent/shared/hermes-agent-run" >"$RUN_STDOUT" 2>"$TMP_DIR/first-run-setup.stderr"; then
  :
else
  fail 'run should complete first-run setup instead of treating setup wait as a hard failure'
fi

assert_file_contains 'exec -i hermes-agent-alpha-0.10.0-20260417-120000-123 hermes setup' "$PODMAN_LOG" 'run should launch hermes setup when the container is still waiting for setup'

# This checks that first-run setup finishes before the host dashboard opener is invoked.
setup_line="$(grep -Fn 'exec -i hermes-agent-alpha-0.10.0-20260417-120000-123 hermes setup' "$PODMAN_LOG" | head -n 1 | cut -d: -f1)"
open_line="$(grep -Fn 'host-open http://127.0.0.1:9334' "$PODMAN_LOG" | head -n 1 | cut -d: -f1)"
if [[ -z "$setup_line" || -z "$open_line" || "$open_line" -le "$setup_line" ]]; then
  fail 'run should not open the dashboard before first-run setup completes'
fi

assert_file_contains 'host-open http://127.0.0.1:9334' "$PODMAN_LOG" 'run should open the dashboard after first-run setup completes and services become healthy'
assert_file_contains 'exec -i hermes-agent-alpha-0.10.0-20260417-120000-123 hermes' "$PODMAN_LOG" 'run should attach to Hermes after first-run setup completes'

# This checks that a healthy matching running container is reused as-is.
: >"$PODMAN_LOG"
: >"$OPEN_LOG"
printf '1\n' | PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_STALE_MODE='same-name' HERMES_TEST_HEALTH_MODE='healthy' bash "$ROOT/scripts/agent/shared/hermes-agent-run" >"$RUN_STDOUT"

assert_file_not_contains 'rm -f hermes-agent-alpha-0.10.0-20260417-120000-123' "$PODMAN_LOG" 'run should keep a matching running container when setup and both services are healthy'
assert_file_not_contains 'run -d --name hermes-agent-alpha-0.10.0-20260417-120000-123' "$PODMAN_LOG" 'run should not recreate a matching running container when it is already healthy'
assert_file_contains 'exec -i hermes-agent-alpha-0.10.0-20260417-120000-123 hermes' "$PODMAN_LOG" 'run should attach to a matching running container once it is healthy'

# This checks that the wrapper waits for health before opening the dashboard or attaching.
: >"$PODMAN_LOG"
: >"$OPEN_LOG"
: >"$SLEEP_LOG"
rm -f "$PODMAN_LOG.health-probes"
: >"$PODMAN_LOG.opened-before-healthy"
: >"$PODMAN_LOG.attached-before-healthy"
printf '1\n' | PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_SLEEP_LOG="$SLEEP_LOG" HERMES_TEST_HEALTH_MODE='delayed-healthy' bash "$ROOT/scripts/agent/shared/hermes-agent-run" >"$RUN_STDOUT"

assert_file_contains 'gateway_state.json' "$PODMAN_LOG" 'run should probe the official gateway status file before opening the dashboard'
assert_file_not_contains 'opened-before-healthy' "$PODMAN_LOG.opened-before-healthy" 'run should not open the dashboard before health checks pass'
assert_file_not_contains 'attached-before-healthy' "$PODMAN_LOG.attached-before-healthy" 'run should not attach before health checks pass'
assert_file_contains 'host-open http://127.0.0.1:9334' "$PODMAN_LOG" 'run should open the dashboard only after the delayed health checks succeed'
assert_file_contains 'exec -i hermes-agent-alpha-0.10.0-20260417-120000-123 hermes' "$PODMAN_LOG" 'run should attach after the delayed health checks succeed'

# This checks that the wrapper allows enough host-side health slack for normal entrypoint polling.
: >"$PODMAN_LOG"
: >"$OPEN_LOG"
rm -f "$PODMAN_LOG.health-probes"
if printf '1\n' | PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_HEALTH_MODE='delayed-healthy-after-entrypoint-slack' bash "$ROOT/scripts/agent/shared/hermes-agent-run" >"$RUN_STDOUT" 2>"$TMP_DIR/delayed-healthy-after-entrypoint-slack.stderr"; then
  :
else
  fail 'run should allow enough health wait slack for delayed but normal entrypoint startup'
fi

assert_file_contains 'host-open http://127.0.0.1:9334' "$PODMAN_LOG" 'run should still open the dashboard when health succeeds just beyond the old host-side wait budget'
assert_file_contains 'exec -i hermes-agent-alpha-0.10.0-20260417-120000-123 hermes' "$PODMAN_LOG" 'run should still attach when health succeeds just beyond the old host-side wait budget'

# This checks that a matching stopped container is started instead of replaced.
: >"$PODMAN_LOG"
: >"$OPEN_LOG"
rm -f "$PODMAN_LOG.started"
printf '1\n' | PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_STALE_MODE='same-name' HERMES_TEST_RUNNING_MODE='stopped' bash "$ROOT/scripts/agent/shared/hermes-agent-run" >"$RUN_STDOUT"

assert_file_contains 'start hermes-agent-alpha-0.10.0-20260417-120000-123' "$PODMAN_LOG" 'run should start a matching stopped workspace container before attaching'
assert_file_contains 'exec -i hermes-agent-alpha-0.10.0-20260417-120000-123 hermes' "$PODMAN_LOG" 'run should attach after starting a matching stopped workspace container'

# This checks that a matching stopped container is recreated once if it dies during the initial running wait.
: >"$PODMAN_LOG"
: >"$OPEN_LOG"
rm -f "$PODMAN_LOG.ran" "$PODMAN_LOG.running-once" "$PODMAN_LOG.running-twice" "$PODMAN_LOG.started"
printf '1\n' | PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_STALE_MODE='same-name' HERMES_TEST_RUNNING_MODE='started-dies-during-wait' bash "$ROOT/scripts/agent/shared/hermes-agent-run" >"$RUN_STDOUT"

assert_file_contains 'start hermes-agent-alpha-0.10.0-20260417-120000-123' "$PODMAN_LOG" 'run should try starting a matching stopped container before recreating it'
assert_file_contains 'rm -f hermes-agent-alpha-0.10.0-20260417-120000-123' "$PODMAN_LOG" 'run should remove a matching stopped container that dies during the initial running wait'
assert_file_contains 'run -d --name hermes-agent-alpha-0.10.0-20260417-120000-123' "$PODMAN_LOG" 'run should recreate a matching stopped container that dies during the initial running wait'
assert_file_contains 'exec -i hermes-agent-alpha-0.10.0-20260417-120000-123 hermes' "$PODMAN_LOG" 'run should attach after recreating a matching stopped container that dies during the initial running wait'

# This checks that a matching running container is recreated once if it dies before attach.
: >"$PODMAN_LOG"
: >"$OPEN_LOG"
rm -f "$PODMAN_LOG.ran" "$PODMAN_LOG.running-once" "$PODMAN_LOG.running-twice" "$PODMAN_LOG.started"
printf '1\n' | PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_STALE_MODE='same-name' HERMES_TEST_RUNNING_MODE='exact-match-dies-before-exec' bash "$ROOT/scripts/agent/shared/hermes-agent-run" >"$RUN_STDOUT"

assert_file_contains 'rm -f hermes-agent-alpha-0.10.0-20260417-120000-123' "$PODMAN_LOG" 'run should remove a matching running container that dies before attach'
assert_file_contains 'run -d --name hermes-agent-alpha-0.10.0-20260417-120000-123' "$PODMAN_LOG" 'run should recreate a matching running container that dies before attach'
assert_file_contains 'exec -i hermes-agent-alpha-0.10.0-20260417-120000-123 hermes' "$PODMAN_LOG" 'run should attach after recreating a matching running container that died before attach'

# This checks that a matching stopped container is recreated once if it dies after being started.
: >"$PODMAN_LOG"
: >"$OPEN_LOG"
rm -f "$PODMAN_LOG.ran" "$PODMAN_LOG.running-once" "$PODMAN_LOG.started"
printf '1\n' | PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_STALE_MODE='same-name' HERMES_TEST_RUNNING_MODE='started-dies-before-exec' bash "$ROOT/scripts/agent/shared/hermes-agent-run" >"$RUN_STDOUT"

assert_file_contains 'start hermes-agent-alpha-0.10.0-20260417-120000-123' "$PODMAN_LOG" 'run should first start a matching stopped container before checking whether it survives to attach'
assert_file_contains 'rm -f hermes-agent-alpha-0.10.0-20260417-120000-123' "$PODMAN_LOG" 'run should remove a matching stopped container that dies before attach after being started'
assert_file_contains 'run -d --name hermes-agent-alpha-0.10.0-20260417-120000-123' "$PODMAN_LOG" 'run should recreate a matching stopped container that dies before attach after being started'
assert_file_contains 'exec -i hermes-agent-alpha-0.10.0-20260417-120000-123 hermes' "$PODMAN_LOG" 'run should attach after recreating a matching stopped container that died before attach after being started'

# This checks that an exact matching container with a public dashboard bind is replaced.
: >"$PODMAN_LOG"
: >"$OPEN_LOG"
printf '1\n' | PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_STALE_MODE='same-name' HERMES_TEST_PORT_MODE='public' bash "$ROOT/scripts/agent/shared/hermes-agent-run" >"$RUN_STDOUT"

assert_file_contains 'rm -f hermes-agent-alpha-0.10.0-20260417-120000-123' "$PODMAN_LOG" 'run should remove a matching container whose dashboard port is not loopback-only'
assert_file_contains 'run -d --name hermes-agent-alpha-0.10.0-20260417-120000-123' "$PODMAN_LOG" 'run should recreate a matching container when its dashboard publish contract is outdated'
assert_file_contains 'exec -i hermes-agent-alpha-0.10.0-20260417-120000-123 hermes' "$PODMAN_LOG" 'run should attach after recreating a matching container with an outdated dashboard publish contract'

# This checks that the wrapper does not attach if the container dies during the dashboard-open readiness window.
: >"$PODMAN_LOG"
: >"$OPEN_LOG"
: >"$SLEEP_LOG"
rm -f "${OPEN_LOG}.opened"
rm -f "$SLEEP_LOG".post-open-*
if printf '1\n' | PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_SLEEP_LOG="$SLEEP_LOG" HERMES_TEST_RUNNING_MODE='dies-during-dashboard-window' bash "$ROOT/scripts/agent/shared/hermes-agent-run" >"$RUN_STDOUT" 2>"$TMP_DIR/dies-during-dashboard-window.stderr"; then
  fail 'run should fail when the container dies during the dashboard-open readiness window'
fi

assert_file_contains 'Hermes Agent container stopped before attach: hermes-agent-alpha-0.10.0-20260417-120000-123' "$TMP_DIR/dies-during-dashboard-window.stderr" 'run should explain when the container dies during the dashboard-open readiness window'
assert_file_not_contains 'exec -i hermes-agent-alpha-0.10.0-20260417-120000-123 hermes' "$PODMAN_LOG" 'run should not exec into a container that dies during the dashboard-open readiness window'

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
