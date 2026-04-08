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

write_value() {
  printf '%s' "$2" > "$STATE_DIR/$1"
}

read_value() {
  [[ -f "$STATE_DIR/$1" ]] && cat "$STATE_DIR/$1"
}

add_image() {
  local ref="$1" lane="$2" upstream="$3" wrapper="$4" commitstamp="$5"
  touch "$STATE_DIR/image_exists_${ref//[:\/]/_}"
  printf '%s\n' "$ref" >> "$STATE_DIR/images.list"
  write_value "image_id_${ref//[:\/]/_}" "image-${lane}-${upstream}-${wrapper}"
  write_value "image_label_hermes_lane_${ref//[:\/]/_}" "$lane"
  write_value "image_label_hermes_ref_${ref//[:\/]/_}" "$upstream"
  write_value "image_label_hermes_wrapper_context_${ref//[:\/]/_}" "$wrapper"
  write_value "image_label_hermes_commitstamp_${ref//[:\/]/_}" "$commitstamp"
  write_value "image_label_hermes_wrapper_fingerprint_${ref//[:\/]/_}" fp
}

add_container() {
  local name="$1" lane="$2" upstream="$3" wrapper="$4" commitstamp="$5" running="$6" image_ref="$7"
  printf '%s\n' "$name" >> "$STATE_DIR/containers.list"
  touch "$STATE_DIR/container_exists_$name"
  write_value "container_running_$name" "$running"
  write_value "container_image_$name" "$(read_value "image_id_${image_ref//[:\/]/_}")"
  write_value "container_label_lane_$name" "$lane"
  write_value "container_label_ref_$name" "$upstream"
  write_value "container_label_wrapper_$name" "$wrapper"
  write_value "container_label_commitstamp_$name" "$commitstamp"
}

reset_state() {
  rm -f "$STATE_DIR"/*
  : > "$STATE_DIR/podman.log"
  : > "$STATE_DIR/images.list"
  : > "$STATE_DIR/containers.list"
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
  images)
    log_call "images $*"
    cat "$STATE_DIR/images.list" ;;
  ps)
    log_call "ps $*"
    cat "$STATE_DIR/containers.list" ;;
  image)
    action="${1:?}"; shift || true
    case "$action" in
      exists)
        log_call "image exists $*"
        [[ -f "$STATE_DIR/image_exists_${1//[:\/]/_}" ]] ;;
      inspect)
        log_call "image inspect $*"
        format="$2"; ref="$3"
        case "$format" in
          '{{ index .Labels "hermes.lane" }}') read_value "image_label_hermes_lane_${ref//[:\/]/_}" ;;
          '{{ index .Labels "hermes.ref" }}') read_value "image_label_hermes_ref_${ref//[:\/]/_}" ;;
          '{{ index .Labels "hermes.wrapper_context" }}') read_value "image_label_hermes_wrapper_context_${ref//[:\/]/_}" ;;
          '{{ index .Labels "hermes.commitstamp" }}') read_value "image_label_hermes_commitstamp_${ref//[:\/]/_}" ;;
          '{{ index .Labels "hermes.wrapper_fingerprint" }}') read_value "image_label_hermes_wrapper_fingerprint_${ref//[:\/]/_}" ;;
          '{{.Id}}') read_value "image_id_${ref//[:\/]/_}" ;;
        esac ;;
      rm)
        log_call "image rm $*" ;;
    esac ;;
  build)
    log_call "build $*"
    target=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        -t) target="$2"; touch "$STATE_DIR/image_exists_${target//[:\/]/_}"; printf '%s\n' "$target" >> "$STATE_DIR/images.list"; write_value "image_id_${target//[:\/]/_}" "built-${target//[:\/]/_}"; shift 2 ;;
        --label)
          case "$2" in
            hermes.lane=*) write_value "image_label_hermes_lane_${target//[:\/]/_}" "${2#hermes.lane=}" ;;
            hermes.ref=*) write_value "image_label_hermes_ref_${target//[:\/]/_}" "${2#hermes.ref=}" ;;
            hermes.wrapper_context=*) write_value "image_label_hermes_wrapper_context_${target//[:\/]/_}" "${2#hermes.wrapper_context=}" ;;
            hermes.commitstamp=*) write_value "image_label_hermes_commitstamp_${target//[:\/]/_}" "${2#hermes.commitstamp=}" ;;
            hermes.wrapper_fingerprint=*) write_value "image_label_hermes_wrapper_fingerprint_${target//[:\/]/_}" "${2#hermes.wrapper_fingerprint=}" ;;
          esac
          shift 2 ;;
        *) shift ;;
      esac
    done ;;
  container)
    action="${1:?}"; shift || true
    case "$action" in
      exists)
        log_call "container exists $*"
        [[ -f "$STATE_DIR/container_exists_$1" ]] ;;
    esac ;;
  inspect)
    log_call "inspect $*"
    if [[ "$1" == "-f" ]]; then
      format="$2"; name="$3"
      case "$format" in
        '{{.State.Running}}') read_value "container_running_$name" ;;
        '{{.Image}}') read_value "container_image_$name" ;;
        '{{index .Config.Labels "hermes.lane"}}|{{index .Config.Labels "hermes.ref"}}|{{index .Config.Labels "hermes.wrapper_context"}}|{{index .Config.Labels "hermes.commitstamp"}}|{{.State.Running}}')
          printf '%s|%s|%s|%s|%s' "$(read_value "container_label_lane_$name")" "$(read_value "container_label_ref_$name")" "$(read_value "container_label_wrapper_$name")" "$(read_value "container_label_commitstamp_$name")" "$(read_value "container_running_$name")" ;;
      esac
    else
      printf '{"Name":"%s"}\n' "$1"
    fi ;;
  run)
    log_call "run $*"
    name=""; image_ref=""; lane=""; ref=""; wrapper=""; commitstamp=""
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --name) name="$2"; shift 2 ;;
        --label)
          case "$2" in
            hermes.lane=*) lane="${2#hermes.lane=}" ;;
            hermes.ref=*) ref="${2#hermes.ref=}" ;;
            hermes.wrapper_context=*) wrapper="${2#hermes.wrapper_context=}" ;;
            hermes.commitstamp=*) commitstamp="${2#hermes.commitstamp=}" ;;
          esac
          shift 2 ;;
        -*) shift ;;
        *) image_ref="$1"; break ;;
      esac
    done
    touch "$STATE_DIR/container_exists_$name"
    printf '%s\n' "$name" >> "$STATE_DIR/containers.list"
    write_value "container_running_$name" true
    write_value "container_image_$name" "$(read_value "image_id_${image_ref//[:\/]/_}")"
    write_value "container_label_lane_$name" "$lane"
    write_value "container_label_ref_$name" "$ref"
    write_value "container_label_wrapper_$name" "$wrapper"
    write_value "container_label_commitstamp_$name" "$commitstamp" ;;
  start)
    log_call "start $*"
    write_value "container_running_$1" true ;;
  stop)
    log_call "stop $*"
    write_value "container_running_$1" false ;;
  rm)
    log_call "rm $*" ;;
  exec)
    log_call "exec $*"
    printf 'mock exec\n' ;;
  logs)
    log_call "logs $*"
    printf 'mock logs\n' ;;
esac
EOF
chmod +x "$MOCK_BIN/podman"

cat > "$MOCK_BIN/script" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
STATE_DIR="${STATE_DIR:?}"
printf 'script %s\n' "$*" >> "$STATE_DIR/podman.log"
exec "$@"
EOF
chmod +x "$MOCK_BIN/script"

export PATH="$MOCK_BIN:$PATH"
export STATE_DIR
export HERMES_BASE_ROOT="$TMPDIR/workspaces"
export HERMES_IMAGE_NAME="mock-hermes-image"
export HERMES_ALLOW_DIRTY=1
export HERMES_UBUNTU_LTS_VERSION="24.04"
export HERMES_NODE_LTS_VERSION="22"
export HERMES_SKIP_UBUNTU_LTS_CHECK=1
export HERMES_SKIP_NODE_LTS_CHECK=1
export HERMES_SKIP_PRODUCTION_GUARDS=1
export HERMES_WRAPPER_CONTEXT_OVERRIDE="main"
export HERMES_COMMITSTAMP_OVERRIDE="20260408-153210-ab12cd3"
export HERMES_RELEASE_OPTION_CACHE=$'1.2.3\tv1.2.3'

reset_state
"$ROOT/scripts/shared/hermes-build" production 1.2.3 > "$STATE_DIR/build.out"
assert_contains "$STATE_DIR/build.out" 'Building Hermes image' 'build reports build start'
assert_contains "$STATE_DIR/build.out" 'Git ref:       v1.2.3' 'build reports resolved git ref'
assert_contains "$STATE_DIR/podman.log" 'mock-hermes-image:production-1.2.3-main-20260408-153210-ab12cd3' 'build uses human upstream version in immutable image tag'
assert_contains "$STATE_DIR/build.out" 'Node LTS:      22' 'build reports configured node lts pin'

reset_state
IMAGE_REF="mock-hermes-image:production-1.2.3-main-20260408-153210-ab12cd3"
add_image "$IMAGE_REF" production 1.2.3 main 20260408-153210-ab12cd3

export HERMES_SELECT_INDEX=1
"$ROOT/scripts/shared/hermes-start" ezirius > "$STATE_DIR/start.out"
assert_contains "$STATE_DIR/podman.log" 'run -d --name hermes-agent-ezirius-production-1.2.3-main' 'start creates workspace container from selected image'

export HERMES_SELECT_INDEX=1
"$ROOT/scripts/shared/hermes-open" ezirius doctor > "$STATE_DIR/open.out"
assert_contains "$STATE_DIR/podman.log" 'exec -i --workdir /workspace hermes-agent-ezirius-production-1.2.3-main hermes doctor' 'open execs hermes inside selected container'

export HERMES_SELECT_INDEX=1,1
"$ROOT/scripts/shared/hermes-bootstrap" ezirius --help > "$STATE_DIR/bootstrap.out"
assert_contains "$STATE_DIR/podman.log" 'exec -i --workdir /workspace hermes-agent-ezirius-production-1.2.3-main hermes --help' 'hermes-bootstrap selects target then opens hermes'

export HERMES_SELECT_INDEX=1
"$ROOT/scripts/shared/hermes-shell" ezirius pwd > "$STATE_DIR/shell.out"
assert_contains "$STATE_DIR/podman.log" 'exec -i --workdir /workspace hermes-agent-ezirius-production-1.2.3-main pwd' 'shell runs explicit command in container'

export HERMES_SELECT_INDEX=1
"$ROOT/scripts/shared/hermes-logs" ezirius -f > "$STATE_DIR/logs.out"
assert_contains "$STATE_DIR/podman.log" 'logs hermes-agent-ezirius-production-1.2.3-main -f' 'logs forwards podman args'

export HERMES_SELECT_INDEX=1
"$ROOT/scripts/shared/hermes-status" ezirius > "$STATE_DIR/status.out"
assert_contains "$STATE_DIR/podman.log" 'inspect hermes-agent-ezirius-production-1.2.3-main' 'status inspects selected container'

export HERMES_SELECT_INDEX=1
"$ROOT/scripts/shared/hermes-stop" ezirius > "$STATE_DIR/stop.out"
assert_contains "$STATE_DIR/podman.log" 'stop hermes-agent-ezirius-production-1.2.3-main' 'stop stops selected container'

SECOND_IMAGE_REF="mock-hermes-image:test-main-improve-production-and-testing-20260407-101500-deadbee"
add_image "$SECOND_IMAGE_REF" test main improve-production-and-testing 20260407-101500-deadbee
add_container "hermes-agent-nala-test-main-improve-production-and-testing" test main improve-production-and-testing 20260407-101500-deadbee false "$SECOND_IMAGE_REF"

export HERMES_SELECT_INDEX=3
"$ROOT/scripts/shared/hermes-remove" image > "$STATE_DIR/remove-image.out"
assert_contains "$STATE_DIR/podman.log" 'image rm -f mock-hermes-image:production-1.2.3-main-20260408-153210-ab12cd3' 'remove image removes selected image'

export HERMES_SELECT_INDEX=3
"$ROOT/scripts/shared/hermes-remove" container > "$STATE_DIR/remove-container.out"
assert_contains "$STATE_DIR/podman.log" 'rm -f hermes-agent-ezirius-production-1.2.3-main' 'remove container removes selected container'

echo "Runtime checks passed"
