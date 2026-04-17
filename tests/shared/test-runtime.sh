#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT/lib/shell/common.sh"
export HERMES_LABEL_NAMESPACE HERMES_LABEL_WORKSPACE HERMES_LABEL_LANE HERMES_LABEL_UPSTREAM HERMES_LABEL_WRAPPER HERMES_LABEL_COMMITSTAMP
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
  write_value "image_id_${ref//[:\/]/_}" "image-${lane}-${upstream}-${wrapper}-${commitstamp}"
  write_value "image_label_hermes_lane_${ref//[:\/]/_}" "$lane"
  write_value "image_label_hermes_ref_${ref//[:\/]/_}" "$upstream"
  write_value "image_label_hermes_wrapper_context_${ref//[:\/]/_}" "$wrapper"
  write_value "image_label_hermes_commitstamp_${ref//[:\/]/_}" "$commitstamp"
  write_value "image_label_hermes_wrapper_fingerprint_${ref//[:\/]/_}" fp
}

add_container() {
  local name="$1" lane="$2" upstream="$3" wrapper="$4" commitstamp="$5" running="$6" image_ref="$7" workspace_label="$8"
  printf '%s\n' "$name" >> "$STATE_DIR/containers.list"
  touch "$STATE_DIR/container_exists_$name"
  write_value "container_running_$name" "$running"
  write_value "container_image_$name" "$(read_value "image_id_${image_ref//[:\/]/_}")"
  write_value "container_label_lane_$name" "$lane"
  write_value "container_label_ref_$name" "$upstream"
  write_value "container_label_wrapper_$name" "$wrapper"
  write_value "container_label_commitstamp_$name" "$commitstamp"
  write_value "container_label_workspace_$name" "$workspace_label"
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
          "{{ index .Labels \"$HERMES_LABEL_LANE\" }}") read_value "image_label_hermes_lane_${ref//[:\/]/_}" ;;
          "{{index .Labels \"$HERMES_LABEL_LANE\"}}") read_value "image_label_hermes_lane_${ref//[:\/]/_}" ;;
          "{{ index .Labels \"$HERMES_LABEL_UPSTREAM\" }}") read_value "image_label_hermes_ref_${ref//[:\/]/_}" ;;
          "{{index .Labels \"$HERMES_LABEL_UPSTREAM\"}}") read_value "image_label_hermes_ref_${ref//[:\/]/_}" ;;
          "{{ index .Labels \"$HERMES_LABEL_WRAPPER\" }}") read_value "image_label_hermes_wrapper_context_${ref//[:\/]/_}" ;;
          "{{index .Labels \"$HERMES_LABEL_WRAPPER\"}}") read_value "image_label_hermes_wrapper_context_${ref//[:\/]/_}" ;;
          "{{ index .Labels \"$HERMES_LABEL_COMMITSTAMP\" }}") read_value "image_label_hermes_commitstamp_${ref//[:\/]/_}" ;;
          "{{index .Labels \"$HERMES_LABEL_COMMITSTAMP\"}}") read_value "image_label_hermes_commitstamp_${ref//[:\/]/_}" ;;
          "{{ index .Labels \"${HERMES_LABEL_NAMESPACE}.build_fingerprint\" }}") read_value "image_label_hermes_wrapper_fingerprint_${ref//[:\/]/_}" ;;
          "{{index .Labels \"${HERMES_LABEL_NAMESPACE}.build_fingerprint\"}}") read_value "image_label_hermes_wrapper_fingerprint_${ref//[:\/]/_}" ;;
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
            "${HERMES_LABEL_LANE}"=*) write_value "image_label_hermes_lane_${target//[:\/]/_}" "${2#*=}" ;;
            "${HERMES_LABEL_UPSTREAM}"=*) write_value "image_label_hermes_ref_${target//[:\/]/_}" "${2#*=}" ;;
            "${HERMES_LABEL_WRAPPER}"=*) write_value "image_label_hermes_wrapper_context_${target//[:\/]/_}" "${2#*=}" ;;
            "${HERMES_LABEL_COMMITSTAMP}"=*) write_value "image_label_hermes_commitstamp_${target//[:\/]/_}" "${2#*=}" ;;
            "${HERMES_LABEL_NAMESPACE}.build_fingerprint"=*) write_value "image_label_hermes_wrapper_fingerprint_${target//[:\/]/_}" "${2#*=}" ;;
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
        "{{index .Config.Labels \"$HERMES_LABEL_WORKSPACE\"}}") read_value "container_label_workspace_$name" ;;
        "{{index .Config.Labels \"$HERMES_LABEL_LANE\"}}|{{index .Config.Labels \"$HERMES_LABEL_UPSTREAM\"}}|{{index .Config.Labels \"$HERMES_LABEL_WRAPPER\"}}|{{index .Config.Labels \"$HERMES_LABEL_COMMITSTAMP\"}}|{{.State.Running}}")
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
            "${HERMES_LABEL_LANE}"=*) lane="${2#*=}" ;;
            "${HERMES_LABEL_UPSTREAM}"=*) ref="${2#*=}" ;;
            "${HERMES_LABEL_WRAPPER}"=*) wrapper="${2#*=}" ;;
            "${HERMES_LABEL_COMMITSTAMP}"=*) commitstamp="${2#*=}" ;;
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

cat > "$MOCK_BIN/python3" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == "-" ]]; then
  printf 'test-fingerprint\n'
  exit 0
fi
printf 'unexpected python3 invocation in test-runtime.sh\n' >&2
exit 1
EOF
chmod +x "$MOCK_BIN/python3"

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
assert_contains "$STATE_DIR/podman.log" "-f $ROOT/config/containers/Containerfile.wrapper" 'build uses the template-style wrapper Containerfile'
assert_contains "$STATE_DIR/podman.log" '--build-arg UBUNTU_VERSION=24.04' 'build forwards the wrapper ubuntu version arg'
assert_contains "$STATE_DIR/podman.log" '--build-arg NODE_LTS_VERSION=22' 'build forwards node lts build arg'
assert_contains "$STATE_DIR/podman.log" '--build-arg HERMES_CONTAINER_RUNTIME_HOME=/home/hermes' 'build forwards the configured runtime home'
assert_contains "$STATE_DIR/podman.log" '--build-arg HERMES_CONTAINER_WORKSPACE_DIR=/workspace/hermes-workspace' 'build forwards the configured workspace dir'

reset_state
env HERMES_SELECT_INDEX='2,2' HERMES_COMMITSTAMP_OVERRIDE='20260408-170100-lanepick' PATH="$PATH" STATE_DIR="$STATE_DIR" HERMES_BASE_ROOT="$HERMES_BASE_ROOT" HERMES_IMAGE_NAME="$HERMES_IMAGE_NAME" HERMES_ALLOW_DIRTY="$HERMES_ALLOW_DIRTY" HERMES_UBUNTU_LTS_VERSION="$HERMES_UBUNTU_LTS_VERSION" HERMES_NODE_LTS_VERSION="$HERMES_NODE_LTS_VERSION" HERMES_SKIP_UBUNTU_LTS_CHECK="$HERMES_SKIP_UBUNTU_LTS_CHECK" HERMES_SKIP_NODE_LTS_CHECK="$HERMES_SKIP_NODE_LTS_CHECK" HERMES_SKIP_PRODUCTION_GUARDS="$HERMES_SKIP_PRODUCTION_GUARDS" HERMES_RELEASE_OPTION_CACHE="$HERMES_RELEASE_OPTION_CACHE" "$ROOT/scripts/shared/hermes-build" > "$STATE_DIR/build-picker.out" 2>&1
assert_contains "$STATE_DIR/build-picker.out" 'Commit stamp:  20260408-170100-lanepick' 'build picker flow uses the selected lane and upstream values'

reset_state
PIN_WRAPPER_ROOT="$TMPDIR/pin-wrapper"
mkdir -p "$PIN_WRAPPER_ROOT"
cp -R "$ROOT/lib" "$PIN_WRAPPER_ROOT/"
cp -R "$ROOT/scripts" "$PIN_WRAPPER_ROOT/"
cp -R "$ROOT/config" "$PIN_WRAPPER_ROOT/"
cat >> "$PIN_WRAPPER_ROOT/lib/shell/common.sh" <<'EOF'
latest_ubuntu_lts_version() {
  printf '26.04\n'
}

latest_node_lts_version() {
  printf '25\n'
}
EOF
git init "$PIN_WRAPPER_ROOT" >/dev/null 2>&1
git -C "$PIN_WRAPPER_ROOT" config user.name test >/dev/null 2>&1
git -C "$PIN_WRAPPER_ROOT" config user.email test@example.com >/dev/null 2>&1
git -C "$PIN_WRAPPER_ROOT" branch -m main >/dev/null 2>&1 || true
git -C "$PIN_WRAPPER_ROOT" add .
git -C "$PIN_WRAPPER_ROOT" commit -m 'test wrapper' >/dev/null 2>&1
env -u HERMES_SKIP_UBUNTU_LTS_CHECK -u HERMES_SKIP_NODE_LTS_CHECK -u HERMES_COMMITSTAMP_OVERRIDE HERMES_SELECT_INDEX=2,2 HERMES_SKIP_PRODUCTION_GUARDS=1 HERMES_RELEASE_OPTION_CACHE=$'1.2.3\tv1.2.3' "$PIN_WRAPPER_ROOT/scripts/shared/hermes-build" test 1.2.3 > "$STATE_DIR/build-pin-update.out"
assert_contains "$STATE_DIR/build-pin-update.out" 'Ubuntu LTS:    26.04' 'build continues with the updated Ubuntu pin when the user selects update and continue'
assert_contains "$STATE_DIR/build-pin-update.out" 'Node LTS:      25' 'build continues with the updated Node pin when the user selects update and continue'
assert_contains "$STATE_DIR/build-pin-update.out" 'Commit stamp:' 'build reports a commit stamp after pin updates'
assert_contains "$STATE_DIR/build-pin-update.out" 'dirty' 'build stamps a dirty wrapper identity after mutating pinned config during the build'
assert_contains "$STATE_DIR/podman.log" '--build-arg UBUNTU_VERSION=26.04' 'build forwards the updated wrapper ubuntu version arg after mutating config'
assert_contains "$STATE_DIR/podman.log" '--build-arg NODE_LTS_VERSION=25' 'build forwards the updated Node pin after mutating config'
assert_contains "$PIN_WRAPPER_ROOT/config/shared/tool-versions.conf" 'HERMES_UBUNTU_LTS_VERSION="26.04"' 'build updates the Ubuntu pin in config when update and continue is selected'
assert_contains "$PIN_WRAPPER_ROOT/config/shared/tool-versions.conf" 'HERMES_NODE_LTS_VERSION="25"' 'build updates the Node pin in config when update and continue is selected'

reset_state
OFFLINE_PIN_ROOT="$TMPDIR/offline-pin-wrapper"
mkdir -p "$OFFLINE_PIN_ROOT"
cp -R "$ROOT/lib" "$OFFLINE_PIN_ROOT/"
cp -R "$ROOT/scripts" "$OFFLINE_PIN_ROOT/"
cp -R "$ROOT/config" "$OFFLINE_PIN_ROOT/"
cat >> "$OFFLINE_PIN_ROOT/lib/shell/common.sh" <<'EOF'
latest_ubuntu_lts_version() {
  printf 'ubuntu discovery unavailable\n' >&2
  return 1
}

latest_node_lts_version() {
  printf 'node discovery unavailable\n' >&2
  return 1
}
EOF
git init "$OFFLINE_PIN_ROOT" >/dev/null 2>&1
git -C "$OFFLINE_PIN_ROOT" config user.name test >/dev/null 2>&1
git -C "$OFFLINE_PIN_ROOT" config user.email test@example.com >/dev/null 2>&1
git -C "$OFFLINE_PIN_ROOT" branch -m main >/dev/null 2>&1 || true
git -C "$OFFLINE_PIN_ROOT" add .
git -C "$OFFLINE_PIN_ROOT" commit -m 'test wrapper' >/dev/null 2>&1
env -u HERMES_SKIP_UBUNTU_LTS_CHECK -u HERMES_SKIP_NODE_LTS_CHECK HERMES_SKIP_PRODUCTION_GUARDS=1 HERMES_RELEASE_OPTION_CACHE=$'1.2.3\tv1.2.3' "$OFFLINE_PIN_ROOT/scripts/shared/hermes-build" test 1.2.3 > "$STATE_DIR/build-pin-offline.out" 2>&1
assert_contains "$STATE_DIR/build-pin-offline.out" 'Warning: could not check for a newer Ubuntu LTS release; continuing with pinned version 24.04' 'build warns and continues when Ubuntu pin discovery is unavailable'
assert_contains "$STATE_DIR/build-pin-offline.out" 'Warning: could not check for a newer Node LTS release; continuing with pinned version 22' 'build warns and continues when Node pin discovery is unavailable'
assert_contains "$STATE_DIR/build-pin-offline.out" 'Ubuntu LTS:    24.04' 'build continues with the current Ubuntu pin when discovery is unavailable'
assert_contains "$STATE_DIR/build-pin-offline.out" 'Node LTS:      22' 'build continues with the current Node pin when discovery is unavailable'

reset_state
BROKEN_RELEASE_ROOT="$TMPDIR/broken-release-wrapper"
mkdir -p "$BROKEN_RELEASE_ROOT"
cp -R "$ROOT/lib" "$BROKEN_RELEASE_ROOT/"
cp -R "$ROOT/scripts" "$BROKEN_RELEASE_ROOT/"
cp -R "$ROOT/config" "$BROKEN_RELEASE_ROOT/"
cat >> "$BROKEN_RELEASE_ROOT/lib/shell/common.sh" <<'EOF'
list_upstream_release_options() {
  printf 'failed to list upstream Hermes releases: simulated failure\n' >&2
  return 1
}
EOF
git init "$BROKEN_RELEASE_ROOT" >/dev/null 2>&1
git -C "$BROKEN_RELEASE_ROOT" config user.name test >/dev/null 2>&1
git -C "$BROKEN_RELEASE_ROOT" config user.email test@example.com >/dev/null 2>&1
git -C "$BROKEN_RELEASE_ROOT" branch -m main >/dev/null 2>&1 || true
git -C "$BROKEN_RELEASE_ROOT" add .
git -C "$BROKEN_RELEASE_ROOT" commit -m 'test wrapper' >/dev/null 2>&1
if env -u HERMES_SKIP_UBUNTU_LTS_CHECK -u HERMES_SKIP_NODE_LTS_CHECK HERMES_SKIP_PRODUCTION_GUARDS=1 HERMES_RELEASE_OPTION_CACHE='' "$BROKEN_RELEASE_ROOT/scripts/shared/hermes-build" test > "$STATE_DIR/build-release-failure.out" 2>&1; then
  printf 'assertion failed: hermes-build should fail clearly when upstream release lookup fails\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/build-release-failure.out" 'failed to list upstream Hermes releases' 'build fails clearly when the upstream release lookup fails before prompting'

reset_state
MISSING_LABEL_IMAGE="mock-hermes-image:test-1.2.3-main-20260408-153210-ab12cd3"
touch "$STATE_DIR/image_exists_${MISSING_LABEL_IMAGE//[:\/]/_}"
printf '%s\n' "$MISSING_LABEL_IMAGE" >> "$STATE_DIR/images.list"
write_value "image_id_${MISSING_LABEL_IMAGE//[:\/]/_}" 'image-missing-labels'
if "$ROOT/scripts/shared/hermes-start" ezirius test 1.2.3 >/dev/null 2> "$STATE_DIR/start-metadata.err"; then
  printf 'assertion failed: hermes-start should fail when image metadata labels are missing\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/start-metadata.err" 'image metadata is missing required Hermes labels' 'start fails fast when image metadata labels are missing'

if "$ROOT/scripts/shared/hermes-start" ezirius production 9.9.9 >/dev/null 2> "$STATE_DIR/start-missing.err"; then
  printf 'assertion failed: hermes-start should fail when the requested image does not exist\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/start-missing.err" 'no matching project image exists' 'start fails clearly when image is missing'

reset_state
IMAGE_REF="mock-hermes-image:production-1.2.3-main-20260408-153210-ab12cd3"
add_image "$IMAGE_REF" production 1.2.3 main 20260408-153210-ab12cd3
OLDER_IMAGE_REF="mock-hermes-image:production-1.2.3-main-20260407-090000-deadbee"
add_image "$OLDER_IMAGE_REF" production 1.2.3 main 20260407-090000-deadbee
add_container "hermes-agent-ezirius-production-1.2.3-main" production 1.2.3 main 20260407-090000-deadbee false "$OLDER_IMAGE_REF" ezirius

TARGET_ROWS="$(source "$ROOT/lib/shell/common.sh"; workspace_image_targets ezirius | sort_targets)"
assert_contains <(printf '%s\n' "$TARGET_ROWS") $'mock-hermes-image:production-1.2.3-main-20260408-153210-ab12cd3\tproduction\t1.2.3\tmain\t20260408-153210-ab12cd3\timage only' 'newer image is not misreported as attached to an older container'
assert_contains <(printf '%s\n' "$TARGET_ROWS") $'mock-hermes-image:production-1.2.3-main-20260407-090000-deadbee\tproduction\t1.2.3\tmain\t20260407-090000-deadbee\tstopped' 'older image reports stopped when the matching container uses it'

MIXED_ROWS="$(source "$ROOT/lib/shell/common.sh"; workspace_target_rows ezirius | sort_targets)"
assert_contains <(printf '%s\n' "$MIXED_ROWS") $'container\thermes-agent-ezirius-production-1.2.3-main\tproduction\t1.2.3\tmain\t20260407-090000-deadbee\tstopped' 'mixed picker includes container rows with real stopped state'
assert_contains <(printf '%s\n' "$MIXED_ROWS") $'image\tmock-hermes-image:production-1.2.3-main-20260408-153210-ab12cd3\tproduction\t1.2.3\tmain\t20260408-153210-ab12cd3\timage only' 'mixed picker includes image-only rows'

export HERMES_SELECT_INDEX=1
"$ROOT/scripts/shared/hermes-start" ezirius > "$STATE_DIR/start.out"
assert_contains "$STATE_DIR/podman.log" 'run -d --name hermes-agent-ezirius-production-1.2.3-main' 'start creates workspace container from selected image'
assert_contains "$STATE_DIR/podman.log" '--restart unless-stopped' 'start applies the configured restart policy'
assert_contains "$STATE_DIR/podman.log" "-v $TMPDIR/workspaces/ezirius/hermes-home:/home/hermes" 'start mounts Hermes runtime state into the configured runtime home'
assert_contains "$STATE_DIR/podman.log" "-v $TMPDIR/workspaces/ezirius/hermes-workspace:/workspace/hermes-workspace" 'start mounts the project workspace into the configured container workspace path'
assert_not_contains "$STATE_DIR/podman.log" ' -p ' 'start does not publish ports by default'
assert_not_contains "$STATE_DIR/podman.log" '--publish' 'start does not use explicit publish flags by default'
assert_contains "$STATE_DIR/podman.log" "--label ${HERMES_LABEL_WORKSPACE}=ezirius" 'start labels containers with workspace identity'
assert_contains "$STATE_DIR/podman.log" "--label ${HERMES_LABEL_COMMITSTAMP}=20260408-153210-ab12cd3" 'start labels containers with commit stamp'
assert_contains "$STATE_DIR/podman.log" '-e HERMES_BUILD_FINGERPRINT=fp' 'start forwards image fingerprint into runtime env'

reset_state
add_image "$IMAGE_REF" production 1.2.3 main 20260408-153210-ab12cd3
add_container "hermes-agent-ezirius-production-1.2.3-main" production 1.2.3 main 20260408-153210-ab12cd3 false "$IMAGE_REF" ezirius
export HERMES_SELECT_INDEX=1
"$ROOT/scripts/shared/hermes-start" ezirius doctor > "$STATE_DIR/start-forward.out"
assert_contains "$STATE_DIR/podman.log" 'start hermes-agent-ezirius-production-1.2.3-main' 'start still starts a stopped selected container before opening'
assert_contains "$STATE_DIR/podman.log" 'exec -i --workdir /workspace/hermes-workspace hermes-agent-ezirius-production-1.2.3-main hermes doctor' 'start forwards Hermes args after startup'
assert_not_contains "$STATE_DIR/podman.log" 'run -d --name hermes-agent-ezirius-production-1.2.3-main' 'start does not create a duplicate container when forwarding after starting a stopped one'

reset_state
add_image "$IMAGE_REF" production 1.2.3 main 20260408-153210-ab12cd3
add_container "hermes-agent-ezirius-production-1.2.3-main" production 1.2.3 main 20260408-153210-ab12cd3 false "$IMAGE_REF" ezirius
rm -f "$STATE_DIR/image_exists_${IMAGE_REF//[:\/]/_}"
export HERMES_SELECT_INDEX=1
"$ROOT/scripts/shared/hermes-start" ezirius doctor > "$STATE_DIR/start-forward-missing-image.out"
assert_contains "$STATE_DIR/podman.log" 'start hermes-agent-ezirius-production-1.2.3-main' 'start reuses a selected stopped container even when the matching image tag is absent locally'
assert_not_contains "$STATE_DIR/podman.log" 'run -d --name hermes-agent-ezirius-production-1.2.3-main' 'start does not recreate a selected container when only the image tag is missing'
assert_contains "$STATE_DIR/podman.log" 'exec -i --workdir /workspace/hermes-workspace hermes-agent-ezirius-production-1.2.3-main hermes doctor' 'start still forwards Hermes args after reusing a selected container without a local image tag'

reset_state
IMAGE_EXPLICIT_OLD="mock-hermes-image:production-1.2.3-main-20260407-090000-deadbee"
IMAGE_EXPLICIT_NEW="mock-hermes-image:production-1.2.3-main-20260408-153210-ab12cd3"
add_image "$IMAGE_EXPLICIT_OLD" production 1.2.3 main 20260407-090000-deadbee
add_image "$IMAGE_EXPLICIT_NEW" production 1.2.3 main 20260408-153210-ab12cd3
"$ROOT/scripts/shared/hermes-start" ezirius production 1.2.3 > "$STATE_DIR/start-explicit.out"
assert_contains "$STATE_DIR/podman.log" 'run -d --name hermes-agent-ezirius-production-1.2.3-main' 'explicit start resolves and uses the newest matching image for the current wrapper context'

reset_state
add_container "hermes-agent-ezirius-production-1.2.3-main" production 1.2.3 main 20260408-153210-ab12cd3 false "$IMAGE_EXPLICIT_NEW" ezirius
"$ROOT/scripts/shared/hermes-start" ezirius production 1.2.3 doctor > "$STATE_DIR/start-explicit-missing-image.out"
assert_contains "$STATE_DIR/podman.log" 'start hermes-agent-ezirius-production-1.2.3-main' 'explicit start reuses an existing deterministic container when the matching image tag is absent locally'
assert_not_contains "$STATE_DIR/podman.log" 'run -d --name hermes-agent-ezirius-production-1.2.3-main' 'explicit start does not recreate the container when only the local image tag is missing'
assert_contains "$STATE_DIR/podman.log" 'exec -i --workdir /workspace/hermes-workspace hermes-agent-ezirius-production-1.2.3-main hermes doctor' 'explicit start still forwards Hermes args after reusing an existing container without a local image tag'

reset_state
add_image "$IMAGE_REF" production 1.2.3 main 20260408-153210-ab12cd3
add_container "hermes-agent-ezirius-production-1.2.3-main" production 1.2.3 main 20260408-153210-ab12cd3 false "$IMAGE_REF" ezirius
if "$ROOT/scripts/shared/hermes-open" ezirius doctor >/dev/null 2> "$STATE_DIR/open-stopped.err"; then
  printf 'assertion failed: hermes-open should reject stopped containers\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/open-stopped.err" 'container not running:' 'open rejects stopped selected containers clearly'

export HERMES_SELECT_INDEX=1
if "$ROOT/scripts/shared/hermes-shell" ezirius >/dev/null 2> "$STATE_DIR/shell-stopped.err"; then
  printf 'assertion failed: hermes-shell should reject stopped containers\n' >&2
  exit 1
fi
assert_contains "$STATE_DIR/shell-stopped.err" 'container not running:' 'shell rejects stopped selected containers clearly'

reset_state
add_image "$IMAGE_REF" production 1.2.3 main 20260408-153210-ab12cd3
add_container "hermes-agent-ezirius-production-1.2.3-main" production 1.2.3 main 20260408-153210-ab12cd3 false "$IMAGE_REF" ezirius
"$ROOT/scripts/shared/hermes-start" ezirius production 1.2.3 > "$STATE_DIR/start-existing.out"
assert_contains "$STATE_DIR/podman.log" 'start hermes-agent-ezirius-production-1.2.3-main' 'start reuses stopped matching container'
assert_not_contains "$STATE_DIR/podman.log" 'run -d --name hermes-agent-ezirius-production-1.2.3-main' 'start does not recreate matching stopped container'

reset_state
add_image "$IMAGE_REF" production 1.2.3 main 20260408-153210-ab12cd3
add_container "hermes-agent-ezirius-production-1.2.3-main" production 1.2.3 main 20260408-153210-ab12cd3 true "$IMAGE_REF" ezirius
PICKED_CONTAINER_ROW="$(source "$ROOT/lib/shell/common.sh"; HERMES_SELECT_INDEX=1 pick_workspace_target ezirius container)"
assert_contains <(printf '%s\n' "$PICKED_CONTAINER_ROW") $'container\thermes-agent-ezirius-production-1.2.3-main\tproduction\t1.2.3\tmain\t20260408-153210-ab12cd3\trunning' 'container picker rows preserve the container name and metadata fields'
"$ROOT/scripts/shared/hermes-start" ezirius production 1.2.3 > "$STATE_DIR/start-running.out"
assert_not_contains "$STATE_DIR/podman.log" 'run -d --name hermes-agent-ezirius-production-1.2.3-main' 'start does not recreate matching running container'
assert_not_contains "$STATE_DIR/podman.log" 'rm -f hermes-agent-ezirius-production-1.2.3-main' 'start does not remove matching running container'

reset_state
add_image "$IMAGE_REF" production 1.2.3 main 20260408-153210-ab12cd3
add_container "hermes-agent-ezirius-production-1.2.3-main" production 1.2.3 main 20260408-153210-ab12cd3 true "$IMAGE_REF" ezirius
"$ROOT/scripts/shared/hermes-start" ezirius production 1.2.3 doctor > "$STATE_DIR/start-running-forward.out"
assert_not_contains "$STATE_DIR/podman.log" 'rm -f hermes-agent-ezirius-production-1.2.3-main' 'start does not recreate a matching running container when forwarding args'
assert_not_contains "$STATE_DIR/podman.log" 'run -d --name hermes-agent-ezirius-production-1.2.3-main' 'start does not create a duplicate matching running container when forwarding args'
assert_contains "$STATE_DIR/podman.log" 'exec -i --workdir /workspace/hermes-workspace hermes-agent-ezirius-production-1.2.3-main hermes doctor' 'start forwards Hermes args against an already running matching container'

reset_state
add_image "$IMAGE_REF" production 1.2.3 main 20260408-153210-ab12cd3
LEGACY_IMAGE_REF="mock-hermes-image:production-1.2.3-main-20260407-010203-oldold1"
add_image "$LEGACY_IMAGE_REF" production 1.2.3 main 20260407-010203-oldold1
add_container "hermes-agent-ezirius-production-1.2.3-main" production 1.2.3 main 20260407-010203-oldold1 true "$LEGACY_IMAGE_REF" ezirius
"$ROOT/scripts/shared/hermes-start" ezirius production 1.2.3 > "$STATE_DIR/start-recreate.out"
assert_contains "$STATE_DIR/podman.log" 'rm -f hermes-agent-ezirius-production-1.2.3-main' 'start removes running container when image changed'
assert_contains "$STATE_DIR/podman.log" 'run -d --name hermes-agent-ezirius-production-1.2.3-main' 'start recreates container on updated image'

export HERMES_SELECT_INDEX=1
"$ROOT/scripts/shared/hermes-open" ezirius doctor > "$STATE_DIR/open.out"
assert_contains "$STATE_DIR/podman.log" 'exec -i --workdir /workspace/hermes-workspace hermes-agent-ezirius-production-1.2.3-main hermes doctor' 'open execs hermes inside selected container'

"$ROOT/scripts/shared/hermes-open" ezirius production 1.2.3 doctor > "$STATE_DIR/open-explicit.out"
assert_contains "$STATE_DIR/podman.log" 'exec -i --workdir /workspace/hermes-workspace hermes-agent-ezirius-production-1.2.3-main hermes doctor' 'open explicit mode resolves deterministic container name'

reset_state
add_image "$IMAGE_REF" production 1.2.3 main 20260408-153210-ab12cd3
HERMES_SELECT_INDEX=1 "$ROOT/scripts/shared/hermes-start" -- production 1.2.3 > "$STATE_DIR/start-picked-explicit.out"
assert_contains "$STATE_DIR/podman.log" 'run -d --name hermes-agent-ezirius-production-1.2.3-main' 'start can pick a workspace and still honour explicit lane and upstream selectors'

add_container "hermes-agent-ezirius-production-1.2.3-main" production 1.2.3 main 20260408-153210-ab12cd3 true "$IMAGE_REF" ezirius
: > "$STATE_DIR/podman.log"
HERMES_SELECT_INDEX=1 "$ROOT/scripts/shared/hermes-open" -- production 1.2.3 -- --help > "$STATE_DIR/open-picked-explicit.out"
assert_contains "$STATE_DIR/podman.log" 'exec -i --workdir /workspace/hermes-workspace hermes-agent-ezirius-production-1.2.3-main hermes --help' 'open can pick a workspace and still honour explicit lane and upstream selectors'

: > "$STATE_DIR/podman.log"
HERMES_SELECT_INDEX=1 "$ROOT/scripts/shared/hermes-shell" -- production 1.2.3 -- env > "$STATE_DIR/shell-picked-explicit.out"
assert_contains "$STATE_DIR/podman.log" 'exec -i --workdir /workspace/hermes-workspace hermes-agent-ezirius-production-1.2.3-main env' 'shell can pick a workspace and still honour explicit lane and upstream selectors'

export HERMES_SELECT_INDEX=1
"$ROOT/scripts/shared/hermes-bootstrap" ezirius --help > "$STATE_DIR/bootstrap.out"
assert_contains "$STATE_DIR/podman.log" 'exec -i --workdir /workspace/hermes-workspace hermes-agent-ezirius-production-1.2.3-main hermes --help' 'hermes-bootstrap selects target then opens hermes'

reset_state
add_image "$IMAGE_REF" production 1.2.3 main 20260408-153210-ab12cd3
add_container "hermes-agent-ezirius-production-1.2.3-main" production 1.2.3 main 20260408-153210-ab12cd3 true "$IMAGE_REF" ezirius
export HERMES_SELECT_INDEX=1
"$ROOT/scripts/shared/hermes-bootstrap" ezirius > "$STATE_DIR/bootstrap-running.out"
assert_contains "$STATE_DIR/podman.log" 'exec -i --workdir /workspace/hermes-workspace hermes-agent-ezirius-production-1.2.3-main hermes' 'hermes-bootstrap still opens Hermes after reusing an already running container'

reset_state
IMAGE_ONLY_REF="mock-hermes-image:test-main-improve-production-and-testing-20260409-080000-beef123"
add_image "$IMAGE_ONLY_REF" test main improve-production-and-testing 20260409-080000-beef123
export HERMES_SELECT_INDEX=1
"$ROOT/scripts/shared/hermes-bootstrap" ezirius doctor > "$STATE_DIR/bootstrap-image-only.out"
assert_contains "$STATE_DIR/podman.log" 'run -d --name hermes-agent-ezirius-test-main-improve-production-and-testing' 'hermes-bootstrap creates a workspace container from a selected image-only target'
assert_contains "$STATE_DIR/podman.log" 'exec -i --workdir /workspace/hermes-workspace hermes-agent-ezirius-test-main-improve-production-and-testing hermes doctor' 'hermes-bootstrap opens Hermes after creating a container from an image-only target'

export HERMES_SELECT_INDEX=1
"$ROOT/scripts/shared/hermes-shell" ezirius pwd > "$STATE_DIR/shell.out"
assert_contains "$STATE_DIR/podman.log" 'exec -i --workdir /workspace/hermes-workspace hermes-agent-ezirius-test-main-improve-production-and-testing pwd' 'shell runs explicit command in container'

export HERMES_SELECT_INDEX=1
"$ROOT/scripts/shared/hermes-shell" ezirius > "$STATE_DIR/shell-default.out"
assert_contains "$STATE_DIR/podman.log" 'exec -i --workdir /workspace/hermes-workspace hermes-agent-ezirius-test-main-improve-production-and-testing /bin/bash' 'shell defaults to /bin/bash when no command is provided'

export HERMES_SELECT_INDEX=1
"$ROOT/scripts/shared/hermes-logs" ezirius -f > "$STATE_DIR/logs.out"
assert_contains "$STATE_DIR/podman.log" 'logs hermes-agent-ezirius-test-main-improve-production-and-testing -f' 'logs forwards podman args'

export HERMES_SELECT_INDEX=1
"$ROOT/scripts/shared/hermes-status" ezirius > "$STATE_DIR/status.out"
assert_contains "$STATE_DIR/status.out" 'Container:   hermes-agent-ezirius-test-main-improve-production-and-testing' 'status reports container name'
assert_contains "$STATE_DIR/status.out" 'Status:' 'status reports container state'
assert_contains "$STATE_DIR/status.out" 'Image:       mock-hermes-image:test-main-improve-production-and-testing-20260409-080000-beef123' 'status reports backing image ref'
assert_not_contains "$STATE_DIR/podman.log" 'start hermes-agent-ezirius-test-main-improve-production-and-testing' 'status does not mutate runtime state by starting containers'
assert_not_contains "$STATE_DIR/podman.log" 'exec hermes-agent-ezirius-test-main-improve-production-and-testing' 'status does not mutate runtime state by execing into containers'

: > "$STATE_DIR/podman.log"
HERMES_SELECT_INDEX=1 "$ROOT/scripts/shared/hermes-shell" -- pwd > "$STATE_DIR/shell-picked-workspace.out"
assert_contains "$STATE_DIR/podman.log" 'exec -i --workdir /workspace/hermes-workspace hermes-agent-ezirius-test-main-improve-production-and-testing pwd' 'shell can pick a workspace when the workspace argument is omitted'

: > "$STATE_DIR/podman.log"
HERMES_SELECT_INDEX=1 "$ROOT/scripts/shared/hermes-logs" -- -f > "$STATE_DIR/logs-picked-workspace.out"
assert_contains "$STATE_DIR/podman.log" 'logs hermes-agent-ezirius-test-main-improve-production-and-testing -f' 'logs can pick a workspace when forwarded podman arguments begin with a dash'

: > "$STATE_DIR/podman.log"
HERMES_SELECT_INDEX=1 "$ROOT/scripts/shared/hermes-status" > "$STATE_DIR/status-picked-workspace.out"
assert_contains "$STATE_DIR/status-picked-workspace.out" 'Container:   hermes-agent-ezirius-test-main-improve-production-and-testing' 'status can pick a workspace when the workspace argument is omitted'

: > "$STATE_DIR/podman.log"
HERMES_SELECT_INDEX=1 "$ROOT/scripts/shared/hermes-stop" > "$STATE_DIR/stop-picked-workspace.out"
assert_contains "$STATE_DIR/podman.log" 'stop hermes-agent-ezirius-test-main-improve-production-and-testing' 'stop can pick a workspace when the workspace argument is omitted'

export HERMES_SELECT_INDEX=1
"$ROOT/scripts/shared/hermes-stop" ezirius > "$STATE_DIR/stop.out"
assert_contains "$STATE_DIR/podman.log" 'stop hermes-agent-ezirius-test-main-improve-production-and-testing' 'stop stops selected container'

reset_state
add_image "$IMAGE_REF" production 1.2.3 main 20260408-153210-ab12cd3
add_container "hermes-agent-ezirius-production-1.2.3-main" production 1.2.3 main 20260408-153210-ab12cd3 false "$IMAGE_REF" ezirius
export HERMES_SELECT_INDEX=1
"$ROOT/scripts/shared/hermes-stop" ezirius > "$STATE_DIR/stop-already.out"
assert_not_contains "$STATE_DIR/podman.log" 'stop hermes-agent-ezirius-production-1.2.3-main' 'stop does not call podman stop for an already stopped container'

SECOND_IMAGE_REF="mock-hermes-image:test-main-improve-production-and-testing-20260407-101500-deadbee"
add_image "$SECOND_IMAGE_REF" test main improve-production-and-testing 20260407-101500-deadbee
add_container "hermes-agent-nala-test-main-improve-production-and-testing" test main improve-production-and-testing 20260407-101500-deadbee false "$SECOND_IMAGE_REF" nala

export HERMES_SELECT_INDEX=3
"$ROOT/scripts/shared/hermes-remove" image > "$STATE_DIR/remove-image.out"
assert_contains "$STATE_DIR/podman.log" 'image rm -f mock-hermes-image:production-1.2.3-main-20260408-153210-ab12cd3' 'remove image removes selected image'

export HERMES_SELECT_INDEX=3
"$ROOT/scripts/shared/hermes-remove" container > "$STATE_DIR/remove-container.out"
assert_contains "$STATE_DIR/podman.log" 'rm -f hermes-agent-ezirius-production-1.2.3-main' 'remove container removes selected container'

reset_state
IMAGE_NEW_EZIRIUS="mock-hermes-image:production-1.2.3-main-20260408-153210-ab12cd3"
IMAGE_OLD_EZIRIUS="mock-hermes-image:production-1.2.3-main-20260407-101500-deadbee"
IMAGE_NEW_NALA="mock-hermes-image:test-main-improve-production-and-testing-20260409-080000-beef123"
add_image "$IMAGE_NEW_EZIRIUS" production 1.2.3 main 20260408-153210-ab12cd3
add_image "$IMAGE_OLD_EZIRIUS" production 1.2.3 main 20260407-101500-deadbee
add_image "$IMAGE_NEW_NALA" test main improve-production-and-testing 20260409-080000-beef123
add_container "hermes-agent-ezirius-production-1.2.3-main" production 1.2.3 main 20260408-153210-ab12cd3 true "$IMAGE_NEW_EZIRIUS" ezirius
add_container "hermes-agent-nala-test-main-improve-production-and-testing" test main improve-production-and-testing 20260409-080000-beef123 false "$IMAGE_NEW_NALA" nala
export HERMES_SELECT_INDEX=1
"$ROOT/scripts/shared/hermes-remove" image > "$STATE_DIR/remove-image-all-but-newest.out"
assert_contains "$STATE_DIR/podman.log" 'image rm -f mock-hermes-image:production-1.2.3-main-20260407-101500-deadbee' 'remove image all-but-newest removes superseded image'
assert_not_contains "$STATE_DIR/podman.log" 'image rm -f mock-hermes-image:production-1.2.3-main-20260408-153210-ab12cd3' 'remove image all-but-newest keeps newest associated workspace image'
assert_not_contains "$STATE_DIR/podman.log" 'image rm -f mock-hermes-image:test-main-improve-production-and-testing-20260409-080000-beef123' 'remove image all-but-newest keeps newest image for other workspace'

reset_state
IMAGE_ASSOCIATED="mock-hermes-image:production-1.2.3-main-20260408-153210-ab12cd3"
IMAGE_ONLY_OLD="mock-hermes-image:test-main-improve-production-and-testing-20260407-101500-deadbee"
IMAGE_ONLY_NEW="mock-hermes-image:test-main-improve-production-and-testing-20260409-080000-beef123"
add_image "$IMAGE_ASSOCIATED" production 1.2.3 main 20260408-153210-ab12cd3
add_image "$IMAGE_ONLY_OLD" test main improve-production-and-testing 20260407-101500-deadbee
add_image "$IMAGE_ONLY_NEW" test main improve-production-and-testing 20260409-080000-beef123
add_container "hermes-agent-ezirius-production-1.2.3-main" production 1.2.3 main 20260408-153210-ab12cd3 true "$IMAGE_ASSOCIATED" ezirius
export HERMES_SELECT_INDEX=1
"$ROOT/scripts/shared/hermes-remove" image > "$STATE_DIR/remove-image-mixed-unassigned.out"
assert_not_contains "$STATE_DIR/podman.log" 'image rm -f mock-hermes-image:production-1.2.3-main-20260408-153210-ab12cd3' 'remove image all-but-newest keeps the newest associated workspace image when image-only builds also exist'
assert_contains "$STATE_DIR/podman.log" 'image rm -f mock-hermes-image:test-main-improve-production-and-testing-20260407-101500-deadbee' 'remove image all-but-newest removes older image-only builds'
assert_not_contains "$STATE_DIR/podman.log" 'image rm -f mock-hermes-image:test-main-improve-production-and-testing-20260409-080000-beef123' 'remove image all-but-newest keeps the newest image-only build alongside associated workspace images'

reset_state
IMAGE_ASSOCIATED_OLD="mock-hermes-image:production-1.2.3-main-20260407-101500-deadbee"
IMAGE_ASSOCIATED_NEW="mock-hermes-image:production-1.2.3-main-20260410-101500-cafe123"
add_image "$IMAGE_ASSOCIATED_OLD" production 1.2.3 main 20260407-101500-deadbee
add_image "$IMAGE_ASSOCIATED_NEW" production 1.2.3 main 20260410-101500-cafe123
add_container "hermes-agent-ezirius-production-1.2.3-main" production 1.2.3 main 20260407-101500-deadbee true "$IMAGE_ASSOCIATED_OLD" ezirius
export HERMES_SELECT_INDEX=1
"$ROOT/scripts/shared/hermes-remove" image > "$STATE_DIR/remove-image-associated-family.out"
assert_contains "$STATE_DIR/podman.log" 'image rm -f mock-hermes-image:production-1.2.3-main-20260407-101500-deadbee' 'remove image all-but-newest removes an older workspace-associated image when a newer image-only build exists in the same family'
assert_not_contains "$STATE_DIR/podman.log" 'image rm -f mock-hermes-image:production-1.2.3-main-20260410-101500-cafe123' 'remove image all-but-newest keeps the newer image-only build for the inferred workspace family'

reset_state
IMAGE_ONLY_A="mock-hermes-image:test-main-main-20260407-101500-deadbee"
IMAGE_ONLY_B="mock-hermes-image:production-1.2.3-main-20260410-101500-cafe123"
add_image "$IMAGE_ONLY_A" test main main 20260407-101500-deadbee
add_image "$IMAGE_ONLY_B" production 1.2.3 main 20260410-101500-cafe123
export HERMES_SELECT_INDEX=1
"$ROOT/scripts/shared/hermes-remove" image > "$STATE_DIR/remove-image-unassigned-global.out"
assert_contains "$STATE_DIR/podman.log" 'image rm -f mock-hermes-image:test-main-main-20260407-101500-deadbee' 'remove image all-but-newest removes older unassigned images when there are no workspace associations at all'
assert_not_contains "$STATE_DIR/podman.log" 'image rm -f mock-hermes-image:production-1.2.3-main-20260410-101500-cafe123' 'remove image all-but-newest keeps only the single newest unassigned image when no workspace associations exist'

reset_state
IMAGE_PROD_OLD="mock-hermes-image:production-1.2.3-main-20260407-101500-deadbee"
IMAGE_TEST_NEW="mock-hermes-image:test-1.2.3-main-20260410-101500-cafe123"
add_image "$IMAGE_PROD_OLD" production 1.2.3 main 20260407-101500-deadbee
add_image "$IMAGE_TEST_NEW" test 1.2.3 main 20260410-101500-cafe123
add_container "hermes-agent-ezirius-production-1.2.3-main" production 1.2.3 main 20260407-101500-deadbee false "$IMAGE_PROD_OLD" ezirius
add_container "hermes-agent-ezirius-test-1.2.3-main" test 1.2.3 main 20260410-101500-cafe123 false "$IMAGE_TEST_NEW" ezirius
export HERMES_SELECT_INDEX=1
"$ROOT/scripts/shared/hermes-remove" container > "$STATE_DIR/remove-container-cross-lane.out"
assert_contains "$STATE_DIR/podman.log" 'rm -f hermes-agent-ezirius-production-1.2.3-main' 'remove container all-but-newest removes an older production container when a newer test container exists for the same workspace'
assert_not_contains "$STATE_DIR/podman.log" 'rm -f hermes-agent-ezirius-test-1.2.3-main' 'remove container all-but-newest keeps the newest container for the workspace regardless of lane'

reset_state
add_image "$IMAGE_PROD_OLD" production 1.2.3 main 20260407-101500-deadbee
add_image "$IMAGE_TEST_NEW" test 1.2.3 main 20260410-101500-cafe123
add_container "hermes-agent-ezirius-production-1.2.3-main" production 1.2.3 main 20260407-101500-deadbee false "$IMAGE_PROD_OLD" ezirius
add_container "hermes-agent-ezirius-test-1.2.3-main" test 1.2.3 main 20260410-101500-cafe123 false "$IMAGE_TEST_NEW" ezirius
export HERMES_SELECT_INDEX=1
"$ROOT/scripts/shared/hermes-remove" image > "$STATE_DIR/remove-image-cross-lane.out"
assert_contains "$STATE_DIR/podman.log" 'image rm -f mock-hermes-image:production-1.2.3-main-20260407-101500-deadbee' 'remove image all-but-newest removes the older image when a newer different-lane image exists for the same workspace'
assert_not_contains "$STATE_DIR/podman.log" 'image rm -f mock-hermes-image:test-1.2.3-main-20260410-101500-cafe123' 'remove image all-but-newest keeps the newest image for the workspace regardless of lane'

reset_state
add_container "hermes-agent-ezirius-production-1.2.3-main" production 1.2.3 main 20260408-153210-ab12cd3 true "$IMAGE_REF" ezirius
add_container "hermes-agent-ezirius-production-1.2.2-main" production 1.2.2 main 20260407-101500-deadbee false "$SECOND_IMAGE_REF" ezirius
add_container "hermes-agent-nala-test-main-improve-production-and-testing" test main improve-production-and-testing 20260409-080000-beef123 false "$SECOND_IMAGE_REF" nala
export HERMES_SELECT_INDEX=1
"$ROOT/scripts/shared/hermes-remove" container > "$STATE_DIR/remove-container-all-but-newest.out"
assert_contains "$STATE_DIR/podman.log" 'rm -f hermes-agent-ezirius-production-1.2.2-main' 'remove container all-but-newest removes older workspace container'
assert_not_contains "$STATE_DIR/podman.log" 'rm -f hermes-agent-ezirius-production-1.2.3-main' 'remove container all-but-newest keeps newest workspace container'
assert_not_contains "$STATE_DIR/podman.log" 'rm -f hermes-agent-nala-test-main-improve-production-and-testing' 'remove container all-but-newest keeps newest container for other workspace'

echo "Runtime checks passed"
