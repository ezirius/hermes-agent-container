#!/usr/bin/env bash

set -euo pipefail

# This test checks that the run script starts the official single-container workspace shape.

# This finds the repo root so the test can reach the script, config, and helpers.
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
source "$ROOT/tests/shared/shared/test-asserts.sh"

# This points at the shared config file the test rewrites for a short time.
CONFIG_PATH="$ROOT/configs/shared/hermes-agent/hermes-agent-settings.conf"
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

# This waits briefly for detached opener processes to write their log lines.
wait_for_file_contains() {
  local needle="$1"
  local file_path="$2"
  local message="$3"
  local attempt

  for attempt in 1 2 3 4 5 6 7 8 9 10; do
    if grep -Fq -- "$needle" "$file_path"; then
      return 0
    fi
    /bin/sleep 0.1
  done

  fail "$message: missing [$needle] in $file_path"
}

# This saves the real config before the test writes its own version.
cp "$CONFIG_PATH" "$CONFIG_BACKUP"
backup_created=1

# This folder holds fake commands so the test can watch what the script would do.
FAKE_BIN="$TMP_DIR/fake-bin"
mkdir -p "$FAKE_BIN"

# This fake Podman models the official single-pod workspace runtime.
cat >"$FAKE_BIN/podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$HERMES_TEST_PODMAN_LOG"

case "$1" in
  pod)
    case "${2:-}" in
      create)
        printf 'new-pod\n'
        ;;
      ps)
        if [[ "${3:-}" == '-aq' ]]; then
          if [[ "${HERMES_TEST_STALE_POD_MODE:-present}" == 'present' ]]; then
            printf 'old-gateway-pod\nold-dashboard-pod\n'
          elif [[ "${HERMES_TEST_STALE_POD_MODE:-present}" == 'workspace-collision' ]]; then
            printf 'hermes-agent-0.9.9-20260401-010101-aaaaaaaaaaaa-alpha-gateway\n'
          fi
          exit 0
        fi

        case "${HERMES_TEST_POD_MODE:-missing}" in
          present)
          printf 'hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha\n'
          ;;
        esac
        ;;
      inspect)
        if [[ "$*" == *'{{.InfraContainerID}}'* ]]; then
          case "${*: -1}" in
            hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha) printf 'fbeaa551b980\n' ;;
            *) printf '58ed0c7f0326\n' ;;
          esac
          exit 0
        fi

        case "${HERMES_TEST_PORT_MODE:-correct}" in
          pod-inspect-correct) printf '{"1234/tcp":[{"HostIp":"127.0.0.1","HostPort":"61234"}]}' ;;
          pod-inspect-external) printf '{"1234/tcp":[{"HostIp":"0.0.0.0","HostPort":"61234"}]}' ;;
          pod-inspect-wrong) printf '{"1234/tcp":[{"HostIp":"127.0.0.1","HostPort":"9999"}]}' ;;
          pod-inspect-mixed) printf '{"1234/tcp":[{"HostIp":"127.0.0.1","HostPort":"61234"},{"HostIp":"0.0.0.0","HostPort":"61234"}]}' ;;
          pod-inspect-extra-lan) printf '{"1234/tcp":[{"HostIp":"127.0.0.1","HostPort":"61234"},{"HostIp":"192.168.1.5","HostPort":"61234"}]}' ;;
          pod-inspect-extra-ipv6) printf '{"1234/tcp":[{"HostIp":"127.0.0.1","HostPort":"61234"},{"HostIp":"::","HostPort":"61234"}]}' ;;
          pod-inspect-extra-loopback-port) printf '{"1234/tcp":[{"HostIp":"127.0.0.1","HostPort":"61234"},{"HostIp":"127.0.0.1","HostPort":"9999"}]}' ;;
          *) printf '{}' ;;
        esac
        ;;
      rm)
        ;;
    esac
    ;;
  images)
    case "${HERMES_TEST_IMAGE_MODE:-present}" in
      missing) ;;
      localhost) printf 'localhost/hermes-agent-0.10.0-20260417-120000-abcdef123456\n' ;;
      *) printf 'hermes-agent-0.10.0-20260417-120000-abcdef123456\n' ;;
    esac
    ;;
  ps)
    if [[ "$2" == '-aq' ]]; then
      if [[ "${HERMES_TEST_CLI_COLLISION_MODE:-}" =~ ^(exact|running)$ && "$*" == *'alpha-cli'* ]]; then
        printf 'hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-cli\n'
        exit 0
      fi

      if [[ "${HERMES_TEST_STALE_MODE:-present}" == 'present' ]]; then
        printf 'old-gateway\nold-dashboard\n'
      elif [[ "${HERMES_TEST_STALE_MODE:-present}" == 'same-name' ]]; then
        printf 'hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-gateway\n'
      elif [[ "${HERMES_TEST_STALE_MODE:-present}" == 'same-name-wrong-mount' ]]; then
        printf 'hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-gateway\n'
      elif [[ "${HERMES_TEST_STALE_MODE:-present}" == 'old-version' ]]; then
        printf 'hermes-agent-0.9.9-20260401-010101-aaaaaaaaaaaa-alpha\n'
      elif [[ "${HERMES_TEST_STALE_MODE:-present}" == 'legacy-role' && "$*" == *gateway* ]]; then
        printf 'hermes-agent-0.9.9-20260401-010101-aaaaaaaaaaaa-alpha-gateway\n'
        printf 'hermes-agent-alpha-dashboard-0.9.9-20260401-010101-aaaaaaaaaaaa\n'
      elif [[ "${HERMES_TEST_STALE_MODE:-present}" == 'workspace-collision' ]]; then
        printf 'hermes-agent-0.9.9-20260401-010101-aaaaaaaaaaaa-alpha-gateway\n'
      fi
      exit 0
    fi

    [[ "${HERMES_TEST_RUNNING_MODE:-running}" == 'never' ]] && exit 0
    if [[ "${HERMES_TEST_CLI_COLLISION_MODE:-}" == 'running' && "$*" == *'alpha-cli'* ]]; then
      printf 'hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-cli\n'
      exit 0
    fi
    case "$*" in
      *beta*) printf 'hermes-agent-0.10.0-20260417-120000-abcdef123456-beta-gateway\n' ;;
      *) printf 'hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-gateway\n' ;;
    esac
    ;;
  run)
    if [[ -n "${HERMES_TEST_EVENT_LOG:-}" ]]; then
      printf 'attach %s\n' "$*" >>"$HERMES_TEST_EVENT_LOG"
    fi
    if [[ "${HERMES_TEST_CLI_COLLISION_MODE:-}" == 'exact' && "$*" == *'alpha-cli'* ]]; then
      if ! grep -Fqx -- 'rm hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-cli' "$HERMES_TEST_PODMAN_LOG"; then
        printf 'Error: container name "hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-cli" is already in use\n' >&2
        exit 125
      fi
    fi
    printf 'new-container\n'
    ;;
  start)
    if [[ "${HERMES_TEST_START_MODE:-ok}" == 'fail' ]]; then
      exit 7
    fi
    if [[ -n "${HERMES_TEST_EVENT_LOG:-}" ]]; then
      printf 'attach %s\n' "$*" >>"$HERMES_TEST_EVENT_LOG"
    fi
    ;;
  rm)
    ;;
  exec)
    if [[ -n "${HERMES_TEST_EVENT_LOG:-}" ]]; then
      printf 'attach %s\n' "$*" >>"$HERMES_TEST_EVENT_LOG"
    fi
    ;;
  port)
    case "${HERMES_TEST_PORT_MODE:-correct}" in
      correct)
        case "$*" in
          *beta*) printf '127.0.0.1:61234\n' ;;
          *) printf '127.0.0.1:61234\n' ;;
        esac
        ;;
      wrong-loopback) printf '127.0.0.1:9999\n' ;;
      external) printf '0.0.0.0:61234\n' ;;
      missing) ;;
      pod-inspect-correct|pod-inspect-external|pod-inspect-wrong|pod-inspect-mixed|pod-inspect-extra-lan|pod-inspect-extra-ipv6|pod-inspect-extra-loopback-port) exit 125 ;;
    esac
    ;;
  inspect)
    if [[ "$*" == *'{{.Name}}'* ]]; then
      case "${*: -1}" in
        fbeaa551b980)
          case "${HERMES_TEST_INFRA_NAME_MODE:-random}" in
            matching) printf 'hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-infrastructure\n' ;;
            *) printf 'fbeaa551b980-infra\n' ;;
          esac
          ;;
        *)
          case "${HERMES_TEST_INFRA_NAME_MODE:-random}" in
            matching) printf 'hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-infrastructure\n' ;;
            *) printf '58ed0c7f0326-infra\n' ;;
          esac
          ;;
      esac
    elif [[ "$*" == *'{{range .Mounts}}'* ]]; then
      container_name="${*: -1}"
      case "$container_name" in
        *-alpha-gateway)
          if [[ "${HERMES_TEST_STALE_MODE:-present}" == 'same-name-wrong-mount' ]]; then
            printf '%s : /workspace/docs\n' "$HERMES_TEST_BASE_PATH/not-alpha/hermes-agent-docs"
          elif [[ "${HERMES_TEST_STALE_MODE:-present}" == 'workspace-collision' ]]; then
            printf '%s : /workspace/docs\n' "$HERMES_TEST_BASE_PATH/alpha-gateway/hermes-agent-docs"
          else
            printf '%s : /workspace/docs\n' "$HERMES_TEST_BASE_PATH/alpha/hermes-agent-docs"
          fi
          ;;
        *-beta) printf '%s : /workspace/docs\n' "$HERMES_TEST_BASE_PATH/beta/hermes-agent-docs" ;;
        *)
          if [[ "${HERMES_TEST_STALE_MODE:-present}" == 'same-name-wrong-mount' ]]; then
            printf '%s : /workspace/docs\n' "$HERMES_TEST_BASE_PATH/not-alpha/hermes-agent-docs"
          else
            printf '%s : /workspace/docs\n' "$HERMES_TEST_BASE_PATH/alpha/hermes-agent-docs"
          fi
          ;;
      esac
    else
      printf 'status=running running=true exit_code=0\n'
    fi
    ;;
  logs)
    printf '(no recent logs)\n'
    ;;
  rename)
    if [[ "${HERMES_TEST_RENAME_MODE:-ok}" == 'fail' ]]; then
      printf 'rename failed\n' >&2
      exit 9
    fi
    ;;
esac
EOF

# This fake opener records dashboard URLs without touching the host browser.
cat >"$FAKE_BIN/xdg-open" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${HERMES_TEST_EVENT_LOG:-}" ]]; then
  printf 'open-start %s\n' "$*" >>"$HERMES_TEST_EVENT_LOG"
fi
if [[ "${HERMES_TEST_XDG_OPEN_MODE:-ok}" == 'fail' ]]; then
  exit 1
fi
printf '%s\n' "$*" >>"$HERMES_TEST_OPEN_LOG"
if [[ "${HERMES_TEST_XDG_OPEN_BLOCK:-0}" == '1' ]]; then
  while [[ ! -f "${HERMES_TEST_OPEN_RELEASE_FILE}" ]]; do
    /bin/sleep 0.1
  done
fi
if [[ -n "${HERMES_TEST_EVENT_LOG:-}" ]]; then
  printf 'open-end %s\n' "$*" >>"$HERMES_TEST_EVENT_LOG"
fi
EOF

# This fake gio records fallback dashboard URLs without touching the host browser.
cat >"$FAKE_BIN/gio" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${HERMES_TEST_EVENT_LOG:-}" ]]; then
  printf 'open-start %s\n' "$*" >>"$HERMES_TEST_EVENT_LOG"
fi
printf '%s\n' "$*" >>"$HERMES_TEST_OPEN_LOG"
if [[ "${HERMES_TEST_GIO_OPEN_BLOCK:-0}" == '1' ]]; then
  while [[ ! -f "${HERMES_TEST_OPEN_RELEASE_FILE}" ]]; do
    /bin/sleep 0.1
  done
fi
if [[ -n "${HERMES_TEST_EVENT_LOG:-}" ]]; then
  printf 'open-end %s\n' "$*" >>"$HERMES_TEST_EVENT_LOG"
fi
EOF

# This fake macOS opener records event ordering without touching the host browser.
cat >"$FAKE_BIN/open" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf 'open-start %s\n' "$*" >>"$HERMES_TEST_EVENT_LOG"
printf '%s\n' "$*" >>"$HERMES_TEST_OPEN_LOG"
if [[ "${HERMES_TEST_OPEN_BLOCK:-}" == '1' ]]; then
  /bin/sleep 0.2
fi
printf 'open-done %s\n' "$*" >>"$HERMES_TEST_EVENT_LOG"
exit "${HERMES_TEST_OPEN_EXIT_CODE:-0}"
EOF

# This fake sleep keeps readiness loops fast.
cat >"$FAKE_BIN/sleep" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
:
EOF

# This fake uname lets the test exercise macOS opener behavior from Linux CI.
cat >"$FAKE_BIN/uname" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "${HERMES_TEST_UNAME:-Linux}"
EOF

# This fake id lets the test exercise root-launched ownership repair safely.
cat >"$FAKE_BIN/id" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
case "$1" in
  -u) printf '%s\n' "${HERMES_TEST_HOST_UID:-1000}" ;;
  -g) printf '%s\n' "${HERMES_TEST_HOST_GID:-1000}" ;;
esac
EOF

# This fake chown records ownership repairs without changing test files.
cat >"$FAKE_BIN/chown" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$*" >>"$HERMES_TEST_CHOWN_LOG"
EOF

# This fake curl lets the run wrapper check upstream freshness without network access.
cat >"$FAKE_BIN/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ -n "${HERMES_TEST_CURL_LOG:-}" ]]; then
  printf '%s\n' "$*" >>"$HERMES_TEST_CURL_LOG"
fi

case "$*" in
  *'--connect-timeout 7 --max-time 11'*) ;;
  *'--connect-timeout 4 --max-time 6 http://127.0.0.1:'*)
    if [[ "${HERMES_TEST_CURL_READY_MODE:-ready}" == 'never' ]]; then
      exit 7
    fi
    exit 0
    ;;
  *)
    printf 'curl missing bounded timeout arguments: %s\n' "$*" >&2
    exit 2
    ;;
esac

case "$*" in
  *'NousResearch/hermes-agent/releases/latest'*)
    case "${HERMES_TEST_LATEST_HERMES_VERSION:-same}" in
      same) printf '{"tag_name":"v2026.4.16"}\n' ;;
      newer) printf '{"tag_name":"v2026.4.17"}\n' ;;
      older) printf '{"tag_name":"v2026.4.15"}\n' ;;
      empty) printf '{}\n' ;;
      fail) exit 7 ;;
      *) printf '{}\n' ;;
    esac
    ;;
  *'nushell/nushell/releases/latest'*)
    case "${HERMES_TEST_LATEST_NUSHELL_VERSION:-same}" in
      same) printf '{"tag_name":"0.103.0"}\n' ;;
      newer) printf '{"tag_name":"0.103.1"}\n' ;;
      older) printf '{"tag_name":"0.102.9"}\n' ;;
      empty) printf '{}\n' ;;
      fail) exit 7 ;;
      *) printf '{}\n' ;;
    esac
    ;;
  *)
    printf '{}\n'
    ;;
esac
EOF

chmod +x "$FAKE_BIN/podman" "$FAKE_BIN/xdg-open" "$FAKE_BIN/gio" "$FAKE_BIN/open" "$FAKE_BIN/sleep" "$FAKE_BIN/uname" "$FAKE_BIN/id" "$FAKE_BIN/chown" "$FAKE_BIN/curl"

# This test config keeps workspace paths, ports, and commands predictable.
cat >"$CONFIG_PATH" <<EOF
# Hermes Agent runtime and build configuration.
HERMES_AGENT_IMAGE_BASENAME="hermes-agent"
HERMES_AGENT_UPSTREAM_IMAGE="docker.io/nousresearch/hermes-agent"
HERMES_AGENT_UID="1000"
HERMES_AGENT_GID="1000"
HERMES_AGENT_VERSION="0.10.0"
HERMES_AGENT_RELEASE_TAG="v2026.4.16"
HERMES_AGENT_NUSHELL_FALLBACK_VERSION="0.103.0"
HERMES_AGENT_NUSHELL_FALLBACK_SHA256_AARCH64="aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
HERMES_AGENT_NUSHELL_FALLBACK_SHA256_X86_64="bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
HERMES_AGENT_RELEASE_CONNECT_TIMEOUT_SECONDS="7"
HERMES_AGENT_RELEASE_MAX_TIMEOUT_SECONDS="11"
HERMES_AGENT_DASHBOARD_PORT="1234"
HERMES_AGENT_CHAT_COMMAND="hermes"
HERMES_AGENT_SHELL_COMMAND="nu"
HERMES_AGENT_BASE_PATH="$TMP_DIR/base"
HERMES_AGENT_CONTAINER_HOME="/opt/data"
HERMES_AGENT_CONTAINER_DOCS="/workspace/docs"
HERMES_AGENT_HOST_HOME_DIRNAME="hermes-agent-home"
HERMES_AGENT_HOST_DOCS_DIRNAME="hermes-agent-docs"
HERMES_AGENT_RELEASE_API_URL="https://api.github.com/repos/NousResearch/hermes-agent/releases/latest"
HERMES_AGENT_NUSHELL_RELEASE_API_URL="https://api.github.com/repos/nushell/nushell/releases/latest"
HERMES_AGENT_RUNNING_WAIT_ATTEMPTS="3"
HERMES_AGENT_RUNNING_WAIT_SECONDS="9"
HERMES_AGENT_STABLE_WAIT_ATTEMPTS="4"
HERMES_AGENT_STABLE_WAIT_SECONDS="8"
HERMES_AGENT_PUBLISHED_URL_WAIT_ATTEMPTS="3"
HERMES_AGENT_PUBLISHED_URL_CONNECT_TIMEOUT_SECONDS="4"
HERMES_AGENT_PUBLISHED_URL_MAX_TIMEOUT_SECONDS="6"
HERMES_AGENT_PUBLISHED_URL_WAIT_SECONDS="7"
EOF

mkdir -p "$TMP_DIR/base/alpha" "$TMP_DIR/base/beta" "$TMP_DIR/base/ezirius" "$TMP_DIR/base/alpha-gateway"

assert_equals '61234' "$(ROOT="$ROOT" bash -c 'set -euo pipefail; source "$1"; hermes_workspace_published_port beta' _ "$ROOT/scripts/shared/hermes-agent/common.sh")" 'published port helper should add the family offset to the dashboard port'
assert_equals 'http://127.0.0.1:61234' "$(ROOT="$ROOT" bash -c 'set -euo pipefail; source "$1"; hermes_workspace_published_url beta' _ "$ROOT/scripts/shared/hermes-agent/common.sh")" 'published URL helper should return the loopback dashboard URL'

running_wait_output="$(ROOT="$ROOT" bash -c 'set -euo pipefail; source "$1"; source "$2"; count=0; sleeps=""; hermes_container_is_running() { count=$((count + 1)); return 1; }; sleep() { sleeps="${sleeps}${1},"; }; if hermes_wait_for_running_container demo-container; then exit 99; fi; printf "%s|%s\n" "$count" "$sleeps"' _ "$ROOT/scripts/shared/hermes-agent/common.sh" "$CONFIG_PATH")" || fail 'running wait helper should honour configured retry settings'
assert_equals '3|9,9,9,' "$running_wait_output" 'running wait helper should use configured attempt and sleep values'

stable_wait_output="$(ROOT="$ROOT" bash -c 'set -euo pipefail; source "$1"; source "$2"; count=0; sleeps=""; hermes_container_is_running() { count=$((count + 1)); return 0; }; sleep() { sleeps="${sleeps}${1},"; }; hermes_wait_for_stable_running_container demo-container >/dev/null; printf "%s|%s\n" "$count" "$sleeps"' _ "$ROOT/scripts/shared/hermes-agent/common.sh" "$CONFIG_PATH")" || fail 'stable wait helper should honour configured retry settings'
assert_equals '5|8,8,8,8,' "$stable_wait_output" 'stable wait helper should use configured attempt and sleep values'

published_url_wait_output="$(ROOT="$ROOT" bash -c 'set -euo pipefail; source "$1"; source "$2"; count=0; curl_args=""; sleeps=""; curl() { count=$((count + 1)); curl_args="$*"; return 1; }; sleep() { sleeps="${sleeps}${1},"; }; if hermes_wait_for_published_url http://127.0.0.1:61234; then exit 99; fi; printf "%s|%s|%s\n" "$count" "$curl_args" "$sleeps"' _ "$ROOT/scripts/shared/hermes-agent/common.sh" "$CONFIG_PATH")" || fail 'published URL wait helper should honour configured retry settings'
assert_equals '3|-fsS --connect-timeout 4 --max-time 6 http://127.0.0.1:61234|7,7,7,' "$published_url_wait_output" 'published URL wait helper should use configured retry and timeout values'

if ROOT="$ROOT" bash -c 'set -euo pipefail; source "$1"; HERMES_AGENT_DASHBOARD_PORT=bad; hermes_workspace_published_port alpha' _ "$ROOT/scripts/shared/hermes-agent/common.sh" >/dev/null 2>"$TMP_DIR/bad-dashboard-port.stderr"; then
  fail 'published port helper should reject nonnumeric dashboard ports'
fi
assert_file_contains 'HERMES_AGENT_DASHBOARD_PORT must be a numeric port from 1 to 65535.' "$TMP_DIR/bad-dashboard-port.stderr" 'published port helper should explain nonnumeric dashboard ports'

if ROOT="$ROOT" bash -c 'set -euo pipefail; source "$1"; HERMES_AGENT_DASHBOARD_PORT=0; hermes_workspace_published_port alpha' _ "$ROOT/scripts/shared/hermes-agent/common.sh" >/dev/null 2>"$TMP_DIR/zero-dashboard-port.stderr"; then
  fail 'published port helper should reject zero dashboard ports'
fi
assert_file_contains 'HERMES_AGENT_DASHBOARD_PORT must be a numeric port from 1 to 65535.' "$TMP_DIR/zero-dashboard-port.stderr" 'published port helper should explain zero dashboard ports'

if ROOT="$ROOT" bash -c 'set -euo pipefail; source "$1"; HERMES_AGENT_WORKSPACE_NAMES=(alpha); HERMES_AGENT_WORKSPACE_OFFSETS=(60000); HERMES_AGENT_DASHBOARD_PORT=6000; hermes_workspace_published_port alpha' _ "$ROOT/scripts/shared/hermes-agent/common.sh" >/dev/null 2>"$TMP_DIR/overflow-dashboard-port.stderr"; then
  fail 'published port helper should reject overflow dashboard ports'
fi
assert_file_contains 'Published dashboard port for alpha must be from 1 to 65535.' "$TMP_DIR/overflow-dashboard-port.stderr" 'published port helper should explain overflow dashboard ports'

filtered_workspaces_output="$(ROOT="$ROOT" bash -c 'set -euo pipefail; source "$1"; HERMES_AGENT_DASHBOARD_PORT=6000; HERMES_AGENT_BASE_PATH="$2"; hermes_load_workspaces; printf "%s\n" "${HERMES_AGENT_WORKSPACE_NAMES[@]}"' _ "$ROOT/scripts/shared/hermes-agent/common.sh" "$TMP_DIR/base")" || fail 'workspace loading should keep only workspaces with possible published dashboard ports'
assert_equals 'ezirius' "$filtered_workspaces_output" 'workspace loading should skip discovered workspaces whose published dashboard port would overflow'

if ROOT="$ROOT" bash -c 'set -euo pipefail; source "$1"; HERMES_AGENT_DASHBOARD_PORT=6000; HERMES_AGENT_BASE_PATH="$2"; hermes_resolve_workspace_arg alpha' _ "$ROOT/scripts/shared/hermes-agent/common.sh" "$TMP_DIR/base" >/dev/null 2>"$TMP_DIR/filtered-workspace.stderr"; then
  fail 'workspace resolution should reject filtered workspaces whose published dashboard port would overflow'
fi
assert_file_contains 'Workspace alpha is not configured.' "$TMP_DIR/filtered-workspace.stderr" 'workspace resolution should treat filtered overflow workspaces as unavailable'

if ROOT="$ROOT" bash -c 'set -euo pipefail; source "$1"; HERMES_AGENT_BASE_PATH="/"; hermes_validate_safe_host_base_path' _ "$ROOT/scripts/shared/hermes-agent/common.sh" >/dev/null 2>"$TMP_DIR/root-base-path.stderr"; then
  fail 'host base path validation should reject filesystem root'
fi
assert_file_contains 'HERMES_AGENT_BASE_PATH must point to a managed subdirectory, not /.' "$TMP_DIR/root-base-path.stderr" 'host base path validation should explain filesystem root rejection'

if ROOT="$ROOT" bash -c 'set -euo pipefail; source "$1"; HERMES_AGENT_BASE_PATH="${HOME}"; hermes_validate_safe_host_base_path' _ "$ROOT/scripts/shared/hermes-agent/common.sh" >/dev/null 2>"$TMP_DIR/home-base-path.stderr"; then
  fail 'host base path validation should reject the home directory itself'
fi
assert_file_contains 'HERMES_AGENT_BASE_PATH must point to a managed subdirectory, not the home directory itself.' "$TMP_DIR/home-base-path.stderr" 'host base path validation should explain home directory rejection'

if ROOT="$ROOT" bash -c 'set -euo pipefail; source "$1"; HERMES_AGENT_BASE_PATH="${HOME}/.."; hermes_validate_safe_host_base_path' _ "$ROOT/scripts/shared/hermes-agent/common.sh" >/dev/null 2>"$TMP_DIR/parent-base-path.stderr"; then
  fail 'host base path validation should reject parent-directory path components'
fi
assert_file_contains 'HERMES_AGENT_BASE_PATH must not contain parent-directory components.' "$TMP_DIR/parent-base-path.stderr" 'host base path validation should explain parent-directory rejection'

if ROOT="$ROOT" bash -c 'set -euo pipefail; source "$1"; HERMES_AGENT_HOST_HOME_DIRNAME="../escape"; hermes_validate_safe_host_dirnames' _ "$ROOT/scripts/shared/hermes-agent/common.sh" >/dev/null 2>"$TMP_DIR/bad-home-dirname.stderr"; then
  fail 'host home dirname validation should reject parent-directory components'
fi
assert_file_contains 'HERMES_AGENT_HOST_HOME_DIRNAME must be a single safe directory name.' "$TMP_DIR/bad-home-dirname.stderr" 'host home dirname validation should explain parent-directory rejection'

if ROOT="$ROOT" bash -c 'set -euo pipefail; source "$1"; HERMES_AGENT_HOST_DOCS_DIRNAME="nested/path"; hermes_validate_safe_host_dirnames' _ "$ROOT/scripts/shared/hermes-agent/common.sh" >/dev/null 2>"$TMP_DIR/bad-workspace-dirname.stderr"; then
  fail 'host docs dirname validation should reject slashes'
fi
assert_file_contains 'HERMES_AGENT_HOST_DOCS_DIRNAME must be a single safe directory name.' "$TMP_DIR/bad-workspace-dirname.stderr" 'host docs dirname validation should explain slash rejection'

SYMLINK_BASE="$TMP_DIR/symlink-base"
mkdir -p "$SYMLINK_BASE/alpha" "$TMP_DIR/symlink-target"
ln -s "$TMP_DIR/symlink-target" "$SYMLINK_BASE/alpha/hermes-agent-home"

if ROOT="$ROOT" bash -c 'set -euo pipefail; source "$1"; HERMES_AGENT_BASE_PATH="$2"; hermes_reject_symlinked_managed_path "$(hermes_host_home_dir alpha)"' _ "$ROOT/scripts/shared/hermes-agent/common.sh" "$SYMLINK_BASE" >/dev/null 2>"$TMP_DIR/symlink-home.stderr"; then
  fail 'managed path validation should reject symlinked host home paths'
fi
assert_file_contains 'Managed host path must not be a symlink:' "$TMP_DIR/symlink-home.stderr" 'managed path validation should explain symlink rejection'

rm -f "$SYMLINK_BASE/alpha/hermes-agent-home"
ln -s "$TMP_DIR/symlink-target" "$SYMLINK_BASE/alpha/hermes-agent-docs"

if ROOT="$ROOT" bash -c 'set -euo pipefail; source "$1"; HERMES_AGENT_BASE_PATH="$2"; hermes_reject_symlinked_managed_path "$(hermes_host_docs_dir alpha)"' _ "$ROOT/scripts/shared/hermes-agent/common.sh" "$SYMLINK_BASE" >/dev/null 2>"$TMP_DIR/symlink-workspace.stderr"; then
  fail 'managed path validation should reject symlinked host workspace paths'
fi
assert_file_contains 'Managed host path must not be a symlink:' "$TMP_DIR/symlink-workspace.stderr" 'managed path validation should explain workspace symlink rejection'

rm -rf "$SYMLINK_BASE/alpha"
ln -s "$TMP_DIR/symlink-target" "$SYMLINK_BASE/alpha"

if ROOT="$ROOT" bash -c 'set -euo pipefail; source "$1"; HERMES_AGENT_BASE_PATH="$2"; hermes_reject_symlinked_managed_path "$(hermes_host_home_dir alpha)"' _ "$ROOT/scripts/shared/hermes-agent/common.sh" "$SYMLINK_BASE" >/dev/null 2>"$TMP_DIR/symlink-parent.stderr"; then
  fail 'managed path validation should reject symlinked workspace parent paths'
fi
assert_file_contains 'Managed host path parent must not be a symlink:' "$TMP_DIR/symlink-parent.stderr" 'managed path validation should explain parent symlink rejection'

SYMLINK_ROOT="$TMP_DIR/symlink-root"
SYMLINK_TARGET="$TMP_DIR/symlink-root-target"
mkdir -p "$SYMLINK_TARGET/alpha"
ln -s "$SYMLINK_TARGET" "$SYMLINK_ROOT"

ROOT="$ROOT" bash -c 'set -euo pipefail; source "$1"; HERMES_AGENT_BASE_PATH="$2"; hermes_reject_symlinked_managed_path "$(hermes_host_home_dir alpha)"' _ "$ROOT/scripts/shared/hermes-agent/common.sh" "$SYMLINK_ROOT" || fail 'managed path validation should allow a symlinked configured base path'

# This checks that helper-only callers can resolve workspace offsets without preloading first.
offset_output="$(ROOT="$ROOT" bash -c 'set -euo pipefail; source "$1"; hermes_workspace_offset alpha' _ "$ROOT/scripts/shared/hermes-agent/common.sh" 2>"$TMP_DIR/offset.stderr")" || fail 'workspace offset helper should load configured workspaces when needed'
assert_equals '60000' "$offset_output" 'workspace offset helper should resolve discovered workspace offsets without explicit preload'

# This keeps unsafe path tokens out of workspace-derived host paths and container names.
if ROOT="$ROOT" bash -c 'set -euo pipefail; source "$1"; hermes_validate_workspace_name "."' _ "$ROOT/scripts/shared/hermes-agent/common.sh" >/dev/null 2>"$TMP_DIR/dot-workspace.stderr"; then
  fail 'workspace validation should reject dot as a workspace name'
fi
assert_file_contains "Workspace name . may only contain letters, numbers, dots, underscores, and hyphens, and must not be '.' or '..'." "$TMP_DIR/dot-workspace.stderr" 'workspace validation should explain dot rejection'

if ROOT="$ROOT" bash -c 'set -euo pipefail; source "$1"; hermes_validate_workspace_name ".."' _ "$ROOT/scripts/shared/hermes-agent/common.sh" >/dev/null 2>"$TMP_DIR/dotdot-workspace.stderr"; then
  fail 'workspace validation should reject dotdot as a workspace name'
fi
assert_file_contains "Workspace name .. may only contain letters, numbers, dots, underscores, and hyphens, and must not be '.' or '..'." "$TMP_DIR/dotdot-workspace.stderr" 'workspace validation should explain dotdot rejection'

# This keeps the picker usable by retrying invalid answers before accepting a configured workspace.
picker_output="$(printf 'bad\nbeta\n' | ROOT="$ROOT" bash -c 'set -euo pipefail; source "$1"; hermes_pick_workspace' _ "$ROOT/scripts/shared/hermes-agent/common.sh" 2>"$TMP_DIR/picker-retry.stderr")" || fail 'workspace picker should retry after invalid input'
assert_equals 'beta' "$picker_output" 'workspace picker should accept a valid answer after one invalid answer'
assert_file_contains 'Please pick one of the configured workspaces.' "$TMP_DIR/picker-retry.stderr" 'workspace picker should explain invalid answers before retrying'

if printf 'q\n' | ROOT="$ROOT" bash -c 'set -euo pipefail; source "$1"; hermes_pick_workspace' _ "$ROOT/scripts/shared/hermes-agent/common.sh" >/dev/null 2>"$TMP_DIR/picker-cancel.stderr"; then
  fail 'workspace picker should reject q as cancellation'
fi
assert_file_contains 'Selection cancelled.' "$TMP_DIR/picker-cancel.stderr" 'workspace picker should explain cancellation'

if ROOT="$ROOT" bash -c 'set -euo pipefail; source "$1"; hermes_pick_workspace' _ "$ROOT/scripts/shared/hermes-agent/common.sh" </dev/null >/dev/null 2>"$TMP_DIR/picker-eof.stderr"; then
  fail 'workspace picker should reject EOF as an aborted selection'
fi
assert_file_contains 'Selection aborted.' "$TMP_DIR/picker-eof.stderr" 'workspace picker should explain EOF selection aborts'

PODMAN_LOG="$TMP_DIR/podman.log"
OPEN_LOG="$TMP_DIR/open.log"
CURL_LOG="$TMP_DIR/curl.log"
CHOWN_LOG="$TMP_DIR/chown.log"
EVENT_LOG="$TMP_DIR/events.log"
RUN_STDOUT="$TMP_DIR/run.stdout"
RUN_STDERR="$TMP_DIR/run.stderr"
export HERMES_TEST_BASE_PATH="$TMP_DIR/base"

# This checks that run help prints the family-style usage contract.
PATH="$FAKE_BIN:$PATH" bash "$ROOT/scripts/shared/hermes-agent/hermes-agent-run" --help >"$TMP_DIR/run-help.stdout" 2>"$TMP_DIR/run-help.stderr"
assert_file_contains 'Usage: scripts/shared/hermes-agent/hermes-agent-run [workspace]' "$TMP_DIR/run-help.stdout" 'run help should print the family-style usage line'
assert_file_contains 'This script takes zero or one argument: [workspace]. See --help.' "$TMP_DIR/run-help.stdout" 'run help should explain the workspace argument contract'
test ! -s "$TMP_DIR/run-help.stderr" || fail 'run help should not write to stderr'

# This checks that Linux browser opening falls back to gio when xdg-open fails.
: >"$OPEN_LOG"
PATH="$FAKE_BIN:/usr/bin:/bin" ROOT="$ROOT" OSTYPE='linux-gnu' HERMES_TEST_XDG_OPEN_MODE='fail' HERMES_TEST_OPEN_LOG="$OPEN_LOG" bash -c 'set -euo pipefail; source "$1"; hermes_open_published_url_detached "http://127.0.0.1:9434"' _ "$ROOT/scripts/shared/hermes-agent/common.sh"
wait_for_file_contains 'open http://127.0.0.1:9434' "$OPEN_LOG" 'published URL opener should fall back to gio open when xdg-open fails'

# This normal case starts one pod with dashboard and gateway role containers for the selected workspace.
: >"$OPEN_LOG"
printf 'beta\n' | PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_CURL_LOG="$CURL_LOG" bash "$ROOT/scripts/shared/hermes-agent/hermes-agent-run" >"$RUN_STDOUT" 2>"$RUN_STDERR"

assert_file_contains 'Selection:' "$RUN_STDERR" 'run should show an explicit selection prompt'
assert_file_contains 'api.github.com/repos/NousResearch/hermes-agent/releases/latest' "$CURL_LOG" 'run should check the latest upstream Hermes Agent release before container work'
assert_file_not_contains 'newer stable Hermes Agent version available' "$RUN_STDERR" 'run should not warn when the upstream release matches the pinned release tag'
assert_file_contains 'pod create --userns keep-id --name hermes-agent-0.10.0-20260417-120000-abcdef123456-beta --infra-name hermes-agent-0.10.0-20260417-120000-abcdef123456-beta-infrastructure -p 127.0.0.1:61234:1234' "$PODMAN_LOG" 'run should put keep-id user namespace and a deterministic infra name on the workspace pod for non-root runs'
assert_file_contains 'run -d --name hermes-agent-0.10.0-20260417-120000-abcdef123456-beta-dashboard' "$PODMAN_LOG" 'run should create a dashboard role container for the workspace'
assert_file_contains 'run -d --name hermes-agent-0.10.0-20260417-120000-abcdef123456-beta-gateway' "$PODMAN_LOG" 'run should create a gateway role container for the workspace'
assert_file_contains 'gateway run' "$PODMAN_LOG" 'run should start the gateway role with the official Hermes gateway command'
assert_file_not_contains 'sleep infinity' "$PODMAN_LOG" 'run should not keep the gateway role alive with a placeholder command'
assert_file_contains_in_order 'run -d --name hermes-agent-0.10.0-20260417-120000-abcdef123456-beta-gateway' 'rm -f old-gateway' "$PODMAN_LOG" 'run should remove stale containers after replacement creation'
assert_file_contains_in_order 'ps --format {{.Names}} --filter name=^hermes-agent-0\.10\.0-20260417-120000-abcdef123456-beta-gateway$' 'rm -f old-gateway' "$PODMAN_LOG" 'run should remove stale containers after a running gateway check'
assert_file_contains '--pod hermes-agent-0.10.0-20260417-120000-abcdef123456-beta' "$PODMAN_LOG" 'run should place role containers in the workspace pod'
assert_file_contains '--userns keep-id' "$PODMAN_LOG" 'run should use Podman keep-id user mapping for mounted workspace paths'
assert_file_not_contains '-e HERMES_UID=' "$PODMAN_LOG" 'run should not pass legacy UID environment variables to the upstream image'
assert_file_not_contains '-e HERMES_GID=' "$PODMAN_LOG" 'run should not pass legacy GID environment variables to the upstream image'
assert_file_contains '--workdir /workspace/docs' "$PODMAN_LOG" 'run should use the mounted docs path as the container working directory'
assert_file_contains 'dashboard --host 0.0.0.0 --port 1234 --no-open --insecure' "$PODMAN_LOG" 'run should use the dashboard command required for non-loopback binding'
assert_file_not_contains 'python -c' "$PODMAN_LOG" 'run health checks should not depend on python being available in the derived image'
assert_file_not_contains 'curl -fsS' "$PODMAN_LOG" 'run health checks should not depend on curl being available in the derived image'
assert_file_not_contains 'gateway_state.json' "$PODMAN_LOG" 'run should not inspect Hermes gateway internals before attaching'
assert_file_not_contains 'config.yaml' "$PODMAN_LOG" 'run should not block attach on first-run setup files'
assert_file_not_contains 'run -d --name hermes-agent-0.10.0-20260417-120000-abcdef123456-beta-dashboard -e HERMES_UID=1000 -e HERMES_GID=1000 -p 127.0.0.1:61234:1234' "$PODMAN_LOG" 'run should publish dashboard ports on the pod, not the dashboard container'
assert_file_contains "$TMP_DIR/base/beta/hermes-agent-home:/opt/data" "$PODMAN_LOG" 'run should mount Hermes state at the official data path'
assert_file_contains "$TMP_DIR/base/beta/hermes-agent-docs:/workspace/docs" "$PODMAN_LOG" 'run should mount the docs path'
assert_file_contains 'rm -f old-gateway' "$PODMAN_LOG" 'run should remove stale containers only after replacements are healthy'
assert_file_contains 'rm -f old-dashboard' "$PODMAN_LOG" 'run should remove stale containers only after replacements are healthy'
assert_file_contains 'pod rm -f old-gateway' "$PODMAN_LOG" 'run should remove stale pods after replacements are healthy'
assert_file_contains 'pod rm -f old-dashboard' "$PODMAN_LOG" 'run should remove stale pods after replacements are healthy'
assert_file_contains 'pod rm -f old-gateway-pod' "$PODMAN_LOG" 'run should remove stale gateway pods even when their containers are gone'
assert_file_contains 'pod rm -f old-dashboard-pod' "$PODMAN_LOG" 'run should remove stale dashboard pods even when their containers are gone'
assert_file_contains 'http://127.0.0.1:61234' "$OPEN_LOG" 'run should open the derived dashboard URL'
assert_file_contains 'http://127.0.0.1:61234' "$CURL_LOG" 'run should wait for the published dashboard URL before opening the browser'
assert_file_contains 'Started workspace: beta' "$RUN_STDOUT" 'run should print a concise started-workspace line'
assert_file_contains 'Dashboard: http://localhost:61234' "$RUN_STDOUT" 'run should print the concise dashboard URL with localhost'
assert_file_not_contains 'Dashboard container ID:' "$RUN_STDOUT" 'run should not print raw dashboard container ids on success'
assert_file_not_contains 'Gateway container ID:' "$RUN_STDOUT" 'run should not print raw gateway container ids on success'
assert_file_not_contains 'new-container' "$RUN_STDOUT" 'run should not leak raw container ids on success'
assert_file_contains 'create -i --name hermes-agent-0.10.0-20260417-120000-abcdef123456-beta-cli --workdir /workspace/docs' "$PODMAN_LOG" 'run should keep stdin open when the attach path is non-interactive'
assert_file_contains 'hermes-agent-0.10.0-20260417-120000-abcdef123456 hermes' "$PODMAN_LOG" 'run should create the CLI container with the Hermes command'
assert_file_contains 'start -ai hermes-agent-0.10.0-20260417-120000-abcdef123456-beta-cli' "$PODMAN_LOG" 'run should attach by starting the exact CLI container'
assert_file_not_contains 'rename abcdef1234567890fedcba0987654321abcdef1234567890fedcba0987654321 hermes-agent-0.10.0-20260417-120000-abcdef123456-beta-cli-abcdef123456' "$PODMAN_LOG" 'run should not rename CLI containers to include a container-id suffix'
assert_file_not_contains 'exec -i --workdir /workspace/docs hermes-agent-0.10.0-20260417-120000-abcdef123456-beta-gateway /opt/hermes/docker/entrypoint.sh' "$PODMAN_LOG" 'run should not attach through the persistent gateway container'

# This checks that sudo-launched root runs restore caller ownership.
: >"$CHOWN_LOG"
: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_HOST_UID='0' HERMES_TEST_HOST_GID='0' SUDO_UID='4242' SUDO_GID='4343' HERMES_TEST_CHOWN_LOG="$CHOWN_LOG" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_CURL_LOG="$CURL_LOG" bash "$ROOT/scripts/shared/hermes-agent/hermes-agent-run" alpha >"$RUN_STDOUT" 2>"$RUN_STDERR"
assert_file_contains '-R 4242:4343' "$CHOWN_LOG" 'run should restore caller ownership when sudo creates mount directories'
assert_file_not_contains '--userns keep-id' "$PODMAN_LOG" 'run should not pass rootless keep-id mode when launched as root'

# This checks that forced-interactive runs create the CLI attach container with tty and stdin enabled.
: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_AGENT_FORCE_EXEC_TTY='1' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_CURL_LOG="$CURL_LOG" bash "$ROOT/scripts/shared/hermes-agent/hermes-agent-run" alpha >"$RUN_STDOUT" 2>"$RUN_STDERR"
assert_file_contains 'create -i -t --name hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-cli --workdir /workspace/docs' "$PODMAN_LOG" 'run should create interactive CLI attach containers with tty and stdin enabled'

# This checks that direct root runs preserve root ownership.
: >"$CHOWN_LOG"
: >"$PODMAN_LOG"
env -u SUDO_UID -u SUDO_GID PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_HOST_UID='0' HERMES_TEST_HOST_GID='0' HERMES_TEST_CHOWN_LOG="$CHOWN_LOG" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_CURL_LOG="$CURL_LOG" bash "$ROOT/scripts/shared/hermes-agent/hermes-agent-run" alpha >"$RUN_STDOUT" 2>"$RUN_STDERR"
assert_file_contains '-R 0:0' "$CHOWN_LOG" 'run should preserve root ownership when invoked directly as root'
assert_file_not_contains '--userns keep-id' "$PODMAN_LOG" 'run should not pass rootless keep-id mode when invoked directly as root'

# This checks that an unchanged existing runtime does not reopen the browser on every attach.
: >"$PODMAN_LOG"
: >"$OPEN_LOG"
PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_STALE_MODE='same-name' HERMES_TEST_POD_MODE='present' HERMES_TEST_STALE_POD_MODE='missing' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_CURL_LOG="$CURL_LOG" bash "$ROOT/scripts/shared/hermes-agent/hermes-agent-run" alpha >"$RUN_STDOUT" 2>"$RUN_STDERR"
assert_file_not_contains 'http://127.0.0.1:61234' "$OPEN_LOG" 'run should not reopen the browser when both matching pods and containers are reused unchanged'
assert_file_contains 'rename fbeaa551b980 hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-infrastructure' "$PODMAN_LOG" 'run should rename the exact current pod infra container to the canonical current image workspace name'

# This checks that matching infra container names are left unchanged on reuse.
: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_STALE_MODE='same-name' HERMES_TEST_POD_MODE='present' HERMES_TEST_STALE_POD_MODE='missing' HERMES_TEST_INFRA_NAME_MODE='matching' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_CURL_LOG="$CURL_LOG" bash "$ROOT/scripts/shared/hermes-agent/hermes-agent-run" alpha >"$RUN_STDOUT" 2>"$RUN_STDERR"
assert_file_not_contains 'rename fbeaa551b980 hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-infrastructure' "$PODMAN_LOG" 'run should not rename infra containers that already have the expected name'

# This checks that exact infra rename failures get a clear wrapper-owned message.
: >"$PODMAN_LOG"
if PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_STALE_MODE='same-name' HERMES_TEST_POD_MODE='present' HERMES_TEST_STALE_POD_MODE='missing' HERMES_TEST_RENAME_MODE='fail' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_CURL_LOG="$CURL_LOG" bash "$ROOT/scripts/shared/hermes-agent/hermes-agent-run" alpha >"$RUN_STDOUT" 2>"$TMP_DIR/infra-rename.stderr"; then
  fail 'run should fail when exact pod infra container rename fails'
fi
assert_file_contains 'Failed to rename Hermes pod infra container fbeaa551b980 to hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-infrastructure.' "$TMP_DIR/infra-rename.stderr" 'run should explain exact infra rename failures'

# This checks that exact-name containers with stale mounts are removed before recreation.
: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_STALE_MODE='same-name-wrong-mount' HERMES_TEST_POD_MODE='present' HERMES_TEST_STALE_POD_MODE='missing' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_CURL_LOG="$CURL_LOG" bash "$ROOT/scripts/shared/hermes-agent/hermes-agent-run" alpha >"$RUN_STDOUT" 2>"$RUN_STDERR"
assert_file_contains 'rm -f hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-gateway' "$PODMAN_LOG" 'run should remove exact-name gateway containers whose workspace mount no longer matches'
assert_file_contains 'rm -f hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-dashboard' "$PODMAN_LOG" 'run should remove exact-name dashboard containers when the gateway mount no longer matches'
assert_file_contains 'run -d --name hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-gateway' "$PODMAN_LOG" 'run should recreate exact-name wrong-mount gateway containers after removal'

# This checks that a reused exact pod with the wrong loopback port is replaced before runtime creation.
: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_STALE_MODE='missing' HERMES_TEST_POD_MODE='present' HERMES_TEST_STALE_POD_MODE='missing' HERMES_TEST_PORT_MODE='wrong-loopback' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_CURL_LOG="$CURL_LOG" bash "$ROOT/scripts/shared/hermes-agent/hermes-agent-run" alpha >"$RUN_STDOUT" 2>"$RUN_STDERR"
assert_file_contains 'pod rm -f hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha' "$PODMAN_LOG" 'run should remove exact pods that publish the wrong loopback port'
assert_file_contains 'pod create --userns keep-id --name hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha --infra-name hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-infrastructure -p 127.0.0.1:61234:1234' "$PODMAN_LOG" 'run should recreate exact pods with the expected loopback publish and infra-name contract'

# This checks that real pod inspection can keep a correctly published exact pod reusable.
: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_STALE_MODE='same-name' HERMES_TEST_POD_MODE='present' HERMES_TEST_STALE_POD_MODE='missing' HERMES_TEST_PORT_MODE='pod-inspect-correct' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_CURL_LOG="$CURL_LOG" bash "$ROOT/scripts/shared/hermes-agent/hermes-agent-run" alpha >"$RUN_STDOUT" 2>"$RUN_STDERR"
if grep -Fx -- 'rm -f hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha' "$PODMAN_LOG" >/dev/null; then
  fail 'run should not remove an exact container when pod inspect shows the expected loopback publish contract'
fi
assert_file_not_contains 'pod rm -f hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha' "$PODMAN_LOG" 'run should not remove an exact pod when pod inspect shows the expected loopback publish contract'

# This checks that pod inspection does not hide extra unsafe dashboard bindings.
: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_STALE_MODE='same-name' HERMES_TEST_POD_MODE='present' HERMES_TEST_STALE_POD_MODE='missing' HERMES_TEST_PORT_MODE='pod-inspect-mixed' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_CURL_LOG="$CURL_LOG" bash "$ROOT/scripts/shared/hermes-agent/hermes-agent-run" alpha >"$RUN_STDOUT" 2>"$RUN_STDERR"
assert_file_contains 'rm -f hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha' "$PODMAN_LOG" 'run should remove exact containers when pod inspect shows extra unsafe dashboard bindings'
assert_file_contains 'pod rm -f hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha' "$PODMAN_LOG" 'run should remove exact pods when pod inspect shows extra unsafe dashboard bindings'

: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_STALE_MODE='same-name' HERMES_TEST_POD_MODE='present' HERMES_TEST_STALE_POD_MODE='missing' HERMES_TEST_PORT_MODE='pod-inspect-extra-lan' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_CURL_LOG="$CURL_LOG" bash "$ROOT/scripts/shared/hermes-agent/hermes-agent-run" alpha >"$RUN_STDOUT" 2>"$RUN_STDERR"
assert_file_contains 'rm -f hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha' "$PODMAN_LOG" 'run should remove exact containers when pod inspect shows an extra LAN dashboard binding'
assert_file_contains 'pod rm -f hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha' "$PODMAN_LOG" 'run should remove exact pods when pod inspect shows an extra LAN dashboard binding'

: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_STALE_MODE='same-name' HERMES_TEST_POD_MODE='present' HERMES_TEST_STALE_POD_MODE='missing' HERMES_TEST_PORT_MODE='pod-inspect-extra-ipv6' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_CURL_LOG="$CURL_LOG" bash "$ROOT/scripts/shared/hermes-agent/hermes-agent-run" alpha >"$RUN_STDOUT" 2>"$RUN_STDERR"
assert_file_contains 'pod rm -f hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha' "$PODMAN_LOG" 'run should remove exact pods when pod inspect shows an extra IPv6 dashboard binding'

: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_STALE_MODE='same-name' HERMES_TEST_POD_MODE='present' HERMES_TEST_STALE_POD_MODE='missing' HERMES_TEST_PORT_MODE='pod-inspect-extra-loopback-port' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_CURL_LOG="$CURL_LOG" bash "$ROOT/scripts/shared/hermes-agent/hermes-agent-run" alpha >"$RUN_STDOUT" 2>"$RUN_STDERR"
assert_file_contains 'pod rm -f hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha' "$PODMAN_LOG" 'run should remove exact pods when pod inspect shows an extra loopback dashboard port'

# This checks that externally published exact pods are replaced before reuse.
: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_STALE_MODE='same-name' HERMES_TEST_POD_MODE='present' HERMES_TEST_STALE_POD_MODE='missing' HERMES_TEST_PORT_MODE='external' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_CURL_LOG="$CURL_LOG" bash "$ROOT/scripts/shared/hermes-agent/hermes-agent-run" alpha >"$RUN_STDOUT" 2>"$RUN_STDERR"
assert_file_contains 'rm -f hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha' "$PODMAN_LOG" 'run should remove exact containers whose pod publishes externally'
assert_file_contains 'pod rm -f hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha' "$PODMAN_LOG" 'run should remove exact pods whose dashboard publish is external'

# This checks that attach still happens when the published URL never becomes ready.
: >"$PODMAN_LOG"
: >"$OPEN_LOG"
: >"$CURL_LOG"
PATH="$FAKE_BIN:$PATH" HERMES_TEST_UNAME='Darwin' HERMES_TEST_CURL_READY_MODE='never' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_CURL_LOG="$CURL_LOG" bash "$ROOT/scripts/shared/hermes-agent/hermes-agent-run" alpha >"$RUN_STDOUT" 2>"$RUN_STDERR"
assert_file_contains 'create -i --name hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-cli --workdir /workspace/docs' "$PODMAN_LOG" 'run should still create the temporary CLI container with stdin open when published dashboard URL never becomes ready'
test ! -s "$OPEN_LOG" || fail 'run should not open browser before published dashboard URL is ready'

# This checks that blocking macOS browser open does not block attach.
: >"$PODMAN_LOG"
: >"$OPEN_LOG"
: >"$EVENT_LOG"
PATH="$FAKE_BIN:$PATH" HERMES_TEST_UNAME='Darwin' HERMES_TEST_OPEN_BLOCK='1' HERMES_TEST_EVENT_LOG="$EVENT_LOG" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_CURL_LOG="$CURL_LOG" bash "$ROOT/scripts/shared/hermes-agent/hermes-agent-run" alpha >"$RUN_STDOUT" 2>"$RUN_STDERR"
wait_for_file_contains 'open-start http://127.0.0.1:61234' "$EVENT_LOG" 'run should start macOS browser opener'
wait_for_file_contains 'attach start -ai hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-cli' "$EVENT_LOG" 'run should attach through the exact CLI container while browser opener is detached'

# This checks that blocking Linux browser open does not block attach.
: >"$PODMAN_LOG"
: >"$OPEN_LOG"
: >"$EVENT_LOG"
rm -f "$TMP_DIR/linux-open.release"
PATH="$FAKE_BIN:$PATH" HERMES_TEST_UNAME='Linux' HERMES_TEST_XDG_OPEN_BLOCK='1' HERMES_TEST_OPEN_RELEASE_FILE="$TMP_DIR/linux-open.release" HERMES_TEST_EVENT_LOG="$EVENT_LOG" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_CURL_LOG="$CURL_LOG" bash "$ROOT/scripts/shared/hermes-agent/hermes-agent-run" alpha >"$RUN_STDOUT" 2>"$RUN_STDERR" &
linux_run_pid="$!"
wait_for_file_contains 'open-start http://127.0.0.1:61234' "$EVENT_LOG" 'run should start Linux browser opener'
wait_for_file_contains 'attach start -ai hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-cli' "$EVENT_LOG" 'run should attach through the exact CLI container while Linux browser opener is detached'
touch "$TMP_DIR/linux-open.release"
wait "$linux_run_pid"

# This checks that failed starts still reach the wrapper's startup diagnostics.
: >"$PODMAN_LOG"
if PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_STALE_MODE='same-name' HERMES_TEST_POD_MODE='present' HERMES_TEST_STALE_POD_MODE='missing' HERMES_TEST_RUNNING_MODE='never' HERMES_TEST_START_MODE='fail' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_CURL_LOG="$CURL_LOG" bash "$ROOT/scripts/shared/hermes-agent/hermes-agent-run" alpha >"$RUN_STDOUT" 2>"$TMP_DIR/start-fail.stderr"; then
  fail 'run should fail when reused containers cannot be started and replacements do not stay running'
fi
assert_file_contains 'Hermes Agent container failed to stay running' "$TMP_DIR/start-fail.stderr" 'run should report startup failure after a failed container start'
assert_file_contains 'Container state:' "$TMP_DIR/start-fail.stderr" 'run should print container state diagnostics after a failed container start'
assert_file_contains 'Recent container logs:' "$TMP_DIR/start-fail.stderr" 'run should print recent logs after a failed container start'

# This checks that run removes a stale exact CLI container before opening Hermes.
: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_CLI_COLLISION_MODE='exact' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_CURL_LOG="$CURL_LOG" bash "$ROOT/scripts/shared/hermes-agent/hermes-agent-run" alpha >"$RUN_STDOUT" 2>"$RUN_STDERR"
assert_file_contains 'rm hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-cli' "$PODMAN_LOG" 'run should remove a stale exact CLI container before opening Hermes'
assert_file_contains_in_order 'rm hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-cli' 'create -i --name hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-cli --workdir /workspace/docs' "$PODMAN_LOG" 'run should clear stale CLI name collisions before create'
assert_file_contains 'start -ai hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha-cli' "$PODMAN_LOG" 'run should start the exact CLI container after replacing a stale stopped one'

# This checks that run fails when the exact CLI container name is already running.
: >"$PODMAN_LOG"
if PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_CLI_COLLISION_MODE='running' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_CURL_LOG="$CURL_LOG" bash "$ROOT/scripts/shared/hermes-agent/hermes-agent-run" alpha >"$RUN_STDOUT" 2>"$TMP_DIR/running-cli.stderr"; then
  fail 'run should fail when the exact CLI container name is already running'
fi

assert_file_contains 'Hermes CLI container already running for alpha.' "$TMP_DIR/running-cli.stderr" 'run should explain single-instance CLI collisions'

# This checks that a poisoned exact-match runtime is removed and recreated once before final diagnostics.
: >"$PODMAN_LOG"
if PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_STALE_MODE='same-name' HERMES_TEST_POD_MODE='present' HERMES_TEST_STALE_POD_MODE='missing' HERMES_TEST_RUNNING_MODE='never' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_CURL_LOG="$CURL_LOG" bash "$ROOT/scripts/shared/hermes-agent/hermes-agent-run" alpha >"$RUN_STDOUT" 2>"$TMP_DIR/poisoned.stderr"; then
  fail 'run should fail after one poisoned exact-match recreation attempt when replacements never stay running'
fi
assert_file_contains 'rm -f hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha' "$PODMAN_LOG" 'run should remove poisoned exact-match containers before recreating them'
assert_file_contains 'pod rm -f hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha' "$PODMAN_LOG" 'run should remove poisoned exact-match pods before recreating them'
assert_file_contains 'Hermes Agent container failed to stay running' "$TMP_DIR/poisoned.stderr" 'run should print diagnostics after one poisoned recreation attempt fails'

# This checks old-version workspace containers are removed after current replacements are running.
: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_STALE_MODE='old-version' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_CURL_LOG="$CURL_LOG" bash "$ROOT/scripts/shared/hermes-agent/hermes-agent-run" alpha >"$RUN_STDOUT" 2>"$RUN_STDERR"
assert_file_contains 'rm -f hermes-agent-0.9.9-20260401-010101-aaaaaaaaaaaa-alpha' "$PODMAN_LOG" 'run should remove old-version containers after replacements are running'

# This checks role-suffixed containers from earlier layouts are still cleaned up after migration.
: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_STALE_MODE='legacy-role' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_CURL_LOG="$CURL_LOG" bash "$ROOT/scripts/shared/hermes-agent/hermes-agent-run" alpha >"$RUN_STDOUT" 2>"$RUN_STDERR"
assert_file_contains 'rm -f hermes-agent-0.9.9-20260401-010101-aaaaaaaaaaaa-alpha-gateway' "$PODMAN_LOG" 'run should remove current-order role-suffixed containers after migration'
assert_file_contains 'rm -f hermes-agent-alpha-dashboard-0.9.9-20260401-010101-aaaaaaaaaaaa' "$PODMAN_LOG" 'run should remove older OpenCode-order role-suffixed containers after migration'

# This checks that cleanup does not remove another workspace whose name ends like an old role token.
: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_STALE_MODE='workspace-collision' HERMES_TEST_STALE_POD_MODE='workspace-collision' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_CURL_LOG="$CURL_LOG" bash "$ROOT/scripts/shared/hermes-agent/hermes-agent-run" alpha >"$RUN_STDOUT" 2>"$RUN_STDERR"
assert_file_not_contains 'rm -f hermes-agent-0.9.9-20260401-010101-aaaaaaaaaaaa-alpha-gateway' "$PODMAN_LOG" 'run should not remove a different workspace whose name looks like a legacy role suffix'
assert_file_not_contains 'pod rm -f hermes-agent-0.9.9-20260401-010101-aaaaaaaaaaaa-alpha-gateway' "$PODMAN_LOG" 'run should not remove a different workspace pod whose name looks like a legacy role suffix'

# This checks that run warns but continues when a newer upstream release exists.
: >"$PODMAN_LOG"
: >"$CURL_LOG"
PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_LATEST_HERMES_VERSION='newer' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_CURL_LOG="$CURL_LOG" bash "$ROOT/scripts/shared/hermes-agent/hermes-agent-run" alpha >"$RUN_STDOUT" 2>"$RUN_STDERR"
assert_file_contains 'Warning: newer stable Hermes Agent version available: 2026.4.17' "$RUN_STDERR" 'run should warn when upstream has a newer Hermes Agent release'
assert_file_contains 'run -d --name hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha' "$PODMAN_LOG" 'run should continue after a newer-version warning'

# This checks that run does not warn when pinned release is newer than latest.
: >"$PODMAN_LOG"
: >"$CURL_LOG"
PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_LATEST_HERMES_VERSION='older' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_CURL_LOG="$CURL_LOG" bash "$ROOT/scripts/shared/hermes-agent/hermes-agent-run" alpha >"$RUN_STDOUT" 2>"$RUN_STDERR"
assert_file_not_contains 'newer stable Hermes Agent version available' "$RUN_STDERR" 'run should not warn when pinned release is newer than latest upstream'
assert_file_contains 'run -d --name hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha' "$PODMAN_LOG" 'run should continue when pinned release is newer than latest upstream'

# This checks that run does not warn when latest release cannot be parsed.
: >"$PODMAN_LOG"
: >"$CURL_LOG"
PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_LATEST_HERMES_VERSION='empty' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_CURL_LOG="$CURL_LOG" bash "$ROOT/scripts/shared/hermes-agent/hermes-agent-run" alpha >"$RUN_STDOUT" 2>"$RUN_STDERR"
assert_file_not_contains 'newer stable Hermes Agent version available' "$RUN_STDERR" 'run should not warn when latest upstream release cannot be parsed'
assert_file_not_contains $'\033[' "$RUN_STDERR" 'run should keep warning text plain when stderr is not a terminal'
assert_file_not_contains 'Press Enter to continue.' "$RUN_STDERR" 'run should not pause for release warnings in non-interactive runs'

# This checks that localhost-prefixed local images are normalized before container naming.
: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_IMAGE_MODE='localhost' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" bash "$ROOT/scripts/shared/hermes-agent/hermes-agent-run" alpha >"$RUN_STDOUT" 2>"$RUN_STDERR"
assert_file_contains 'run -d --name hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha' "$PODMAN_LOG" 'run should normalize localhost image names before naming containers'

# This checks that missing images fail with a clear message.
if PATH="$FAKE_BIN:$PATH" HERMES_TEST_IMAGE_MODE='missing' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" bash "$ROOT/scripts/shared/hermes-agent/hermes-agent-run" alpha >/dev/null 2>"$TMP_DIR/missing.stderr"; then
  fail 'run should fail when no local derived image exists'
fi
assert_file_contains 'No built Hermes Agent image found. Run scripts/shared/hermes-agent/hermes-agent-build first.' "$TMP_DIR/missing.stderr" 'run should explain missing local images'

# This checks wrapper option parsing while preserving the one-workspace argument surface.
if PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_CURL_LOG="$CURL_LOG" bash "$ROOT/scripts/shared/hermes-agent/hermes-agent-run" --bad >/dev/null 2>"$TMP_DIR/bad-option.stderr"; then
  fail 'run should reject unsupported options before workspace validation'
fi
assert_file_contains 'Unsupported option: --bad. See --help.' "$TMP_DIR/bad-option.stderr" 'run should explain unsupported options with the family-style wording'

: >"$PODMAN_LOG"
PATH="$FAKE_BIN:$PATH" OSTYPE='linux-gnu' HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_CURL_LOG="$CURL_LOG" bash "$ROOT/scripts/shared/hermes-agent/hermes-agent-run" 1 >"$RUN_STDOUT" 2>"$RUN_STDERR"
assert_file_contains 'run -d --name hermes-agent-0.10.0-20260417-120000-abcdef123456-alpha' "$PODMAN_LOG" 'run should accept numeric workspace arguments as picker indexes'

if PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" HERMES_TEST_CURL_LOG="$CURL_LOG" bash "$ROOT/scripts/shared/hermes-agent/hermes-agent-run" alpha beta >/dev/null 2>"$TMP_DIR/too-many.stderr"; then
  fail 'run should reject more than one workspace argument'
fi
assert_file_contains 'This script takes zero or one argument: [workspace]. See --help.' "$TMP_DIR/too-many.stderr" 'run should keep the one positional argument contract with family-style wording'

# This checks that unconfigured workspaces are rejected before container creation.
if PATH="$FAKE_BIN:$PATH" HERMES_TEST_PODMAN_LOG="$PODMAN_LOG" HERMES_TEST_OPEN_LOG="$OPEN_LOG" bash "$ROOT/scripts/shared/hermes-agent/hermes-agent-run" gamma >/dev/null 2>"$TMP_DIR/workspace.stderr"; then
  fail 'run should reject unconfigured workspace names'
fi
assert_file_contains 'Workspace gamma is not configured.' "$TMP_DIR/workspace.stderr" 'run should explain unconfigured workspaces'
assert_equals '1' "$(grep -Fc 'Workspace gamma is not configured.' "$TMP_DIR/workspace.stderr")" 'run should report unconfigured workspace names once'

printf 'hermes-agent-run behavior checks passed\n'
