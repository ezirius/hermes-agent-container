#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

MOCK_BIN="$TMPDIR/bin"
STATE_DIR="$TMPDIR/state"
mkdir -p "$MOCK_BIN" "$STATE_DIR"

assert_contains() {
  local file="$1" needle="$2" message="$3"
  grep -Fq -- "$needle" "$file" || { printf 'assertion failed: %s\nmissing: %s\n' "$message" "$needle" >&2; exit 1; }
}

assert_not_contains() {
  local file="$1" needle="$2" message="$3"
  if grep -Fq -- "$needle" "$file"; then
    printf 'assertion failed: %s\nunexpected: %s\n' "$message" "$needle" >&2
    exit 1
  fi
}

write_file() {
  printf '%s' "${2-}" > "$1"
}

reset_state() {
  rm -f "$STATE_DIR"/*
  : > "$STATE_DIR/podman.log"
}

cat > "$MOCK_BIN/podman" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="${STATE_DIR:?}"
LOG_FILE="$STATE_DIR/podman.log"
log_call(){ printf '%s\n' "$*" >> "$LOG_FILE"; }
read_value(){ [[ -f "$STATE_DIR/$1" ]] && cat "$STATE_DIR/$1"; }
write_value(){ printf '%s' "$2" > "$STATE_DIR/$1"; }
subcommand="${1:?}"; shift || true
case "$subcommand" in
  image)
    action="${1:?}"; shift || true
    case "$action" in
      exists)
        log_call "image exists $*"
        target="${1:-}"
        if [[ -n "$target" && -f "$STATE_DIR/${target}_exists" ]]; then
          [[ "$(read_value ${target}_exists)" == "1" ]]
        else
          [[ "$(read_value image_exists)" == "1" ]]
        fi ;;
      inspect) log_call "image inspect $*"; format="$2"; case "$format" in
        '{{ index .Labels "hermes.repo_url" }}') printf '%s\n' "$(read_value image_label_hermes_repo_url)" ;;
        '{{ index .Labels "hermes.ref" }}') printf '%s\n' "$(read_value image_label_hermes_ref)" ;;
        '{{ index .Labels "hermes.wrapper_fingerprint" }}') printf '%s\n' "$(read_value image_label_hermes_wrapper_fingerprint)" ;;
        '{{.Id}}') printf '%s\n' "$(read_value image_id)" ;;
        *) exit 1 ;;
      esac ;;
      rm)
        log_call "image rm $*"
        target="${*: -1}"
        if [[ "$target" == "mock-hermes-image-upgrade-tmp" ]]; then
          rm -f "$STATE_DIR/mock-hermes-image-upgrade-tmp_exists"
        else
          rm -f "$STATE_DIR/image_exists" "$STATE_DIR/image_label_hermes_repo_url" "$STATE_DIR/image_label_hermes_ref" "$STATE_DIR/image_label_hermes_wrapper_fingerprint" "$STATE_DIR/image_id"
        fi ;;
      *) exit 1 ;;
    esac ;;
  tag)
    log_call "tag $*"
    write_value image_exists 1
    write_value image_id "$(read_value temp_image_id)"
    write_value image_label_hermes_repo_url "$(read_value temp_image_label_hermes_repo_url)"
    write_value image_label_hermes_ref "$(read_value temp_image_label_hermes_ref)"
    write_value image_label_hermes_wrapper_fingerprint "$(read_value temp_image_label_hermes_wrapper_fingerprint)" ;;
  build)
    log_call "build $*"
    target_image=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -t)
          target_image="$2"
          shift 2 ;;
        --label)
          case "$2" in
            hermes.repo_url=*)
              if [[ "$target_image" == "mock-hermes-image-upgrade-tmp" ]]; then
                write_value temp_image_label_hermes_repo_url "${2#hermes.repo_url=}"
              else
                write_value image_label_hermes_repo_url "${2#hermes.repo_url=}"
              fi ;;
            hermes.ref=*)
              if [[ "$target_image" == "mock-hermes-image-upgrade-tmp" ]]; then
                write_value temp_image_label_hermes_ref "${2#hermes.ref=}"
              else
                write_value image_label_hermes_ref "${2#hermes.ref=}"
              fi ;;
            hermes.wrapper_fingerprint=*)
              if [[ "$target_image" == "mock-hermes-image-upgrade-tmp" ]]; then
                write_value temp_image_label_hermes_wrapper_fingerprint "${2#hermes.wrapper_fingerprint=}"
              else
                write_value image_label_hermes_wrapper_fingerprint "${2#hermes.wrapper_fingerprint=}"
              fi ;;
          esac
          shift 2 ;;
        *) shift ;;
      esac
    done
    if [[ "$target_image" == "mock-hermes-image-upgrade-tmp" ]]; then
      write_value mock-hermes-image-upgrade-tmp_exists 1
      write_value temp_image_id image-b
    else
      write_value image_exists 1
      write_value image_id image-a
    fi ;;
  container)
    action="${1:?}"; shift || true
    case "$action" in
      exists) log_call "container exists $*"; [[ "$(read_value container_exists)" == "1" ]] ;;
      *) exit 1 ;;
    esac ;;
  inspect)
    log_call "inspect $*"
    if [[ $# -eq 1 ]]; then
      printf '{"Name":"%s"}\n' "$1"
      exit 0
    fi
    format="$2"
    case "$format" in
      '{{.State.Running}}') printf '%s\n' "$(read_value container_running)" ;;
      '{{.Image}}') printf '%s\n' "$(read_value container_image_id)" ;;
      *) exit 1 ;;
    esac ;;
  rm) log_call "rm $*"; rm -f "$STATE_DIR/container_exists" "$STATE_DIR/container_running" "$STATE_DIR/container_image_id" ;;
  start) log_call "start $*"; write_value container_exists 1; write_value container_running true ;;
  stop) log_call "stop $*"; write_value container_running false ;;
  run) log_call "run $*"; write_value container_exists 1; write_value container_running true; write_value container_image_id "$(read_value image_id)" ;;
  exec) log_call "exec $*"; printf 'mock exec\n' ;;
  ps) log_call "ps $*"; printf 'mock ps\n' ;;
  logs) log_call "logs $*"; printf 'mock logs\n' ;;
  *) exit 1 ;;
esac
EOF
chmod +x "$MOCK_BIN/podman"

cat > "$MOCK_BIN/script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="${STATE_DIR:?}"
printf '%s\n' "script $*" >> "$STATE_DIR/podman.log"
[[ "$1" == "-q" ]] || exit 1
[[ "$2" == "/dev/null" ]] || exit 1
shift 2
exec "$@"
EOF
chmod +x "$MOCK_BIN/script"

export PATH="$MOCK_BIN:$PATH"
export STATE_DIR
export HERMES_BASE_ROOT="$TMPDIR/workspaces"
export HERMES_IMAGE_NAME="mock-hermes-image"
export HERMES_REPO_URL="https://github.com/NousResearch/hermes-agent.git"
export HERMES_REF="v1.2.3"
EXPECTED_BUILD_FINGERPRINT="$({ ROOT="$ROOT" bash -lc '. "$ROOT/lib/shell/common.sh"; local_build_fingerprint'; })"

reset_state
write_file "$STATE_DIR/image_exists" "1"
"$ROOT/scripts/shared/hermes-build" > "$STATE_DIR/build-skip.out"
assert_contains "$STATE_DIR/build-skip.out" 'Hermes image already exists: mock-hermes-image' 'build reports existing image'
assert_not_contains "$STATE_DIR/podman.log" 'build ' 'build skip path does not build'

reset_state
"$ROOT/scripts/shared/hermes-build" > "$STATE_DIR/build-run.out"
assert_contains "$STATE_DIR/build-run.out" 'Building Hermes image' 'build reports image build'
assert_contains "$STATE_DIR/build-run.out" 'Local build fingerprint:' 'build reports local build fingerprint'
assert_contains "$STATE_DIR/podman.log" 'build --pull=always' 'build invokes podman build'
assert_contains "$STATE_DIR/podman.log" 'hermes.wrapper_fingerprint=' 'build labels image with local fingerprint'

reset_state
write_file "$STATE_DIR/image_exists" "1"
write_file "$STATE_DIR/image_label_hermes_repo_url" 'https://github.com/NousResearch/hermes-agent.git'
write_file "$STATE_DIR/image_label_hermes_ref" 'v1.2.3'
write_file "$STATE_DIR/image_label_hermes_wrapper_fingerprint" "$EXPECTED_BUILD_FINGERPRINT"
"$ROOT/scripts/shared/hermes-upgrade" > "$STATE_DIR/upgrade-skip.out"
assert_contains "$STATE_DIR/upgrade-skip.out" 'No upgrade needed' 'upgrade skips when source matches'

reset_state
write_file "$STATE_DIR/image_exists" "1"
write_file "$STATE_DIR/image_label_hermes_repo_url" 'https://github.com/NousResearch/hermes-agent.git'
write_file "$STATE_DIR/image_label_hermes_ref" 'v1.2.2'
"$ROOT/scripts/shared/hermes-upgrade" > "$STATE_DIR/upgrade-run.out"
assert_contains "$STATE_DIR/upgrade-run.out" 'Upgrading Hermes image: mock-hermes-image' 'upgrade rebuilds when ref differs'
assert_contains "$STATE_DIR/upgrade-run.out" 'Building replacement image first: mock-hermes-image-upgrade-tmp' 'upgrade stages a replacement image before swapping'
assert_contains "$STATE_DIR/podman.log" 'image exists mock-hermes-image-upgrade-tmp' 'upgrade checks whether the staged image already exists'
assert_contains "$STATE_DIR/podman.log" 'image rm -f mock-hermes-image' 'upgrade removes the old image only after replacement build'
assert_contains "$STATE_DIR/podman.log" 'tag mock-hermes-image-upgrade-tmp mock-hermes-image' 'upgrade retags the staged image into place'

reset_state
write_file "$STATE_DIR/image_exists" "1"
write_file "$STATE_DIR/image_label_hermes_repo_url" 'https://github.com/NousResearch/hermes-agent.git'
write_file "$STATE_DIR/image_label_hermes_ref" 'v1.2.3'
write_file "$STATE_DIR/image_label_hermes_wrapper_fingerprint" 'stale-fingerprint'
"$ROOT/scripts/shared/hermes-upgrade" > "$STATE_DIR/upgrade-fingerprint-run.out"
assert_contains "$STATE_DIR/upgrade-fingerprint-run.out" 'Upgrading Hermes image: mock-hermes-image' 'upgrade rebuilds when local build fingerprint differs'
assert_contains "$STATE_DIR/upgrade-fingerprint-run.out" 'Target local build fingerprint:' 'upgrade reports target local build fingerprint'
assert_contains "$STATE_DIR/podman.log" 'tag mock-hermes-image-upgrade-tmp mock-hermes-image' 'fingerprint-driven upgrade also swaps in the staged image'

reset_state
write_file "$STATE_DIR/image_exists" "1"
write_file "$STATE_DIR/image_id" 'image-a'
write_file "$STATE_DIR/image_label_hermes_repo_url" 'https://github.com/NousResearch/hermes-agent.git'
write_file "$STATE_DIR/image_label_hermes_ref" 'v1.2.3'
write_file "$STATE_DIR/image_label_hermes_wrapper_fingerprint" "$EXPECTED_BUILD_FINGERPRINT"
mkdir -p "$HERMES_BASE_ROOT/ezirius"
mkdir -p "$HERMES_BASE_ROOT/ezirius/hermes-home"
touch "$HERMES_BASE_ROOT/ezirius/hermes-home/.env"
printf 'OPENAI_API_KEY=test-key\n' >> "$HERMES_BASE_ROOT/ezirius/hermes-home/.env"
printf 'HERMES_IMAGE_NAME=workspace-override\n' >> "$HERMES_BASE_ROOT/ezirius/hermes-home/.env"
"$ROOT/scripts/shared/bootstrap" ezirius --help > "$STATE_DIR/bootstrap.out"
assert_contains "$STATE_DIR/bootstrap.out" 'No upgrade needed' 'bootstrap checks upgrade before start'
assert_contains "$STATE_DIR/podman.log" 'run -d --name hermes-agent-ezirius' 'bootstrap starts container'
assert_contains "$STATE_DIR/podman.log" '--restart unless-stopped' 'bootstrap configures unless-stopped restart policy'
assert_contains "$STATE_DIR/podman.log" "$HERMES_BASE_ROOT/ezirius/hermes-home:/opt/data" 'bootstrap mounts Hermes home separately'
assert_contains "$STATE_DIR/podman.log" "$HERMES_BASE_ROOT/ezirius/workspace:/workspace" 'bootstrap mounts persistent workspace directory'
assert_not_contains "$STATE_DIR/podman.log" '--env-file ' 'bootstrap does not inject workspace env via podman'
assert_contains "$STATE_DIR/podman.log" 'mock-hermes-image gateway run' 'bootstrap keeps wrapper image selection outside workspace env and runs gateway through the entrypoint model'
assert_contains "$STATE_DIR/podman.log" 'run -i --rm' 'bootstrap opens Hermes with a transient interactive container'
assert_contains "$STATE_DIR/podman.log" "$HERMES_BASE_ROOT/ezirius/hermes-home:/opt/data" 'bootstrap interactive Hermes container mounts Hermes home'
assert_contains "$STATE_DIR/podman.log" "$HERMES_BASE_ROOT/ezirius/workspace:/workspace" 'bootstrap interactive Hermes container mounts workspace'
assert_contains "$STATE_DIR/podman.log" 'mock-hermes-image --help' 'bootstrap opens Hermes CLI from the shared image through the entrypoint model'

reset_state
write_file "$STATE_DIR/image_exists" '1'
write_file "$STATE_DIR/image_id" 'image-a'
write_file "$STATE_DIR/container_exists" '1'
write_file "$STATE_DIR/container_running" 'true'
write_file "$STATE_DIR/container_image_id" 'image-a'
mkdir -p "$HERMES_BASE_ROOT/test/hermes-home" "$HERMES_BASE_ROOT/test/workspace"
touch "$HERMES_BASE_ROOT/test/hermes-home/.env"
touch "$HERMES_BASE_ROOT/test/workspace/old.txt"
"$ROOT/scripts/shared/bootstrap-test" doctor > "$STATE_DIR/bootstrap-test.out"
assert_contains "$STATE_DIR/podman.log" 'rm -f hermes-agent-test' 'bootstrap-test removes the previous test container'
assert_contains "$STATE_DIR/podman.log" 'image rm -f hermes-agent-local-test' 'bootstrap-test removes the previous test image'
assert_contains "$STATE_DIR/podman.log" 'container exists hermes-agent-test' 'bootstrap-test resolves the dedicated test container before cleanup'
assert_contains "$STATE_DIR/podman.log" 'build --pull=always --label hermes.repo_url=https://github.com/NousResearch/hermes-agent.git --label hermes.ref=v1.2.3' 'bootstrap-test rebuilds the test image from scratch'
assert_contains "$STATE_DIR/podman.log" 'run -d --name hermes-agent-test' 'bootstrap-test starts the dedicated test container'
assert_contains "$STATE_DIR/podman.log" 'hermes-agent-local-test gateway run' 'bootstrap-test uses the dedicated test image for the gateway'
assert_contains "$STATE_DIR/podman.log" 'hermes-agent-local-test doctor' 'bootstrap-test opens Hermes from the dedicated test image'
assert_not_contains "$STATE_DIR/podman.log" 'hermes-agent-ezirius' 'bootstrap-test does not touch the live ezirius container'
assert_not_contains "$STATE_DIR/podman.log" 'mock-hermes-image' 'bootstrap-test does not use the live image name'
test ! -e "$HERMES_BASE_ROOT/test/workspace/old.txt"

reset_state
write_file "$STATE_DIR/image_exists" '1'
write_file "$STATE_DIR/image_id" 'image-a'
write_file "$STATE_DIR/container_exists" '1'
write_file "$STATE_DIR/container_running" 'false'
write_file "$STATE_DIR/container_image_id" 'image-a'
"$ROOT/scripts/shared/hermes-start" ezirius > "$STATE_DIR/start-reuse.out"
assert_contains "$STATE_DIR/start-reuse.out" 'Starting existing stopped Hermes Gateway container:' 'start reports restarting stopped gateway container'

reset_state
write_file "$STATE_DIR/container_exists" '1'
"$ROOT/scripts/shared/hermes-status" ezirius > "$STATE_DIR/status.out"
assert_contains "$STATE_DIR/podman.log" 'inspect hermes-agent-ezirius' 'status inspects the exact target container'

reset_state
write_file "$STATE_DIR/container_exists" '1'
"$ROOT/scripts/shared/hermes-logs" ezirius > "$STATE_DIR/logs.out"
assert_contains "$STATE_DIR/podman.log" 'logs hermes-agent-ezirius' 'logs streams container logs'

reset_state
write_file "$STATE_DIR/image_exists" '1'
write_file "$STATE_DIR/image_id" 'image-a'
write_file "$STATE_DIR/container_exists" '1'
write_file "$STATE_DIR/container_running" 'true'
write_file "$STATE_DIR/container_image_id" 'image-a'
"$ROOT/scripts/shared/hermes-open" ezirius doctor > "$STATE_DIR/open.out"
assert_contains "$STATE_DIR/podman.log" 'run -i --rm' 'open uses a transient non-tty container when no tty is available'
assert_contains "$STATE_DIR/podman.log" "$HERMES_BASE_ROOT/ezirius/hermes-home:/opt/data" 'open mounts Hermes home at /opt/data'
assert_contains "$STATE_DIR/podman.log" "$HERMES_BASE_ROOT/ezirius/workspace:/workspace" 'open mounts the workspace at /workspace'
assert_contains "$STATE_DIR/podman.log" 'mock-hermes-image doctor' 'open forwards Hermes CLI arguments through the shared image'

reset_state
write_file "$STATE_DIR/image_exists" '1'
write_file "$STATE_DIR/image_id" 'image-b'
write_file "$STATE_DIR/container_exists" '1'
write_file "$STATE_DIR/container_running" 'true'
write_file "$STATE_DIR/container_image_id" 'image-a'
"$ROOT/scripts/shared/hermes-open" ezirius doctor > "$STATE_DIR/open-stale.out"
assert_contains "$STATE_DIR/open-stale.out" 'Workspace container image is stale; reconciling with the current shared image' 'open detects stale running gateway image'
assert_contains "$STATE_DIR/podman.log" 'rm -f hermes-agent-ezirius' 'open reconciles stale gateway image through hermes-start'
assert_contains "$STATE_DIR/podman.log" 'run -d --name hermes-agent-ezirius' 'open restarts the gateway container before launching the transient CLI'

reset_state
write_file "$STATE_DIR/container_exists" '1'
write_file "$STATE_DIR/container_running" 'true'
HERMES_FORCE_EXEC_TTY=1 OSTYPE=darwin24 "$ROOT/scripts/shared/hermes-open" ezirius chat > "$STATE_DIR/open-darwin.out"
assert_contains "$STATE_DIR/podman.log" 'script -q /dev/null podman run -it --rm' 'open uses script tty wrapper for transient macOS interactive container'

reset_state
write_file "$STATE_DIR/image_exists" '1'
write_file "$STATE_DIR/image_id" 'image-a'
write_file "$STATE_DIR/container_exists" '1'
write_file "$STATE_DIR/container_running" 'true'
write_file "$STATE_DIR/container_image_id" 'image-a'
"$ROOT/scripts/shared/hermes-shell" ezirius > "$STATE_DIR/shell.out"
assert_contains "$STATE_DIR/podman.log" 'run -i --rm' 'shell uses a transient non-tty container when no tty is available'
assert_contains "$STATE_DIR/podman.log" '--entrypoint /bin/bash' 'shell bypasses the entrypoint for direct bash access'
assert_contains "$STATE_DIR/podman.log" "$HERMES_BASE_ROOT/ezirius/hermes-home:/opt/data" 'shell mounts Hermes home at /opt/data'

reset_state
write_file "$STATE_DIR/image_exists" '1'
write_file "$STATE_DIR/image_id" 'image-b'
write_file "$STATE_DIR/container_exists" '1'
write_file "$STATE_DIR/container_running" 'true'
write_file "$STATE_DIR/container_image_id" 'image-a'
"$ROOT/scripts/shared/hermes-shell" ezirius > "$STATE_DIR/shell-stale.out"
assert_contains "$STATE_DIR/shell-stale.out" 'Workspace container image is stale; reconciling with the current shared image' 'shell detects stale running gateway image'
assert_contains "$STATE_DIR/podman.log" 'rm -f hermes-agent-ezirius' 'shell reconciles stale gateway image through hermes-start'
assert_contains "$STATE_DIR/podman.log" 'run -d --name hermes-agent-ezirius' 'shell restarts the gateway container before launching the transient shell'

reset_state
write_file "$STATE_DIR/container_exists" '1'
write_file "$STATE_DIR/container_running" 'true'
HERMES_FORCE_EXEC_TTY=1 OSTYPE=darwin24 "$ROOT/scripts/shared/hermes-shell" ezirius > "$STATE_DIR/shell-darwin.out"
assert_contains "$STATE_DIR/podman.log" 'script -q /dev/null podman run -it --rm' 'shell uses script tty wrapper for transient macOS interactive container'

reset_state
write_file "$STATE_DIR/container_exists" '1'
write_file "$STATE_DIR/container_running" 'true'
"$ROOT/scripts/shared/hermes-stop" ezirius > "$STATE_DIR/stop.out"
assert_contains "$STATE_DIR/stop.out" 'Stopping Hermes Gateway container:' 'stop reports running container stop'
assert_contains "$STATE_DIR/podman.log" 'stop hermes-agent-ezirius' 'stop calls podman stop'

reset_state
write_file "$STATE_DIR/container_exists" '1'
"$ROOT/scripts/shared/hermes-remove" ezirius > "$STATE_DIR/remove.out"
assert_contains "$STATE_DIR/remove.out" 'Removing Hermes container:' 'remove reports container removal'
assert_contains "$STATE_DIR/podman.log" 'rm -f hermes-agent-ezirius' 'remove calls podman rm'

echo "Runtime behaviour checks passed"
