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
      exists) log_call "image exists $*"; [[ "$(read_value image_exists)" == "1" ]] ;;
      inspect) log_call "image inspect $*"; format="$2"; case "$format" in
        '{{ index .Labels "hermes.repo_url" }}') printf '%s\n' "$(read_value image_label_hermes_repo_url)" ;;
        '{{ index .Labels "hermes.ref" }}') printf '%s\n' "$(read_value image_label_hermes_ref)" ;;
        '{{.Id}}') printf '%s\n' "$(read_value image_id)" ;;
        *) exit 1 ;;
      esac ;;
      rm) log_call "image rm $*"; rm -f "$STATE_DIR/image_exists" "$STATE_DIR/image_label_hermes_repo_url" "$STATE_DIR/image_label_hermes_ref" "$STATE_DIR/image_id" ;;
      *) exit 1 ;;
    esac ;;
  build)
    log_call "build $*"
    write_value image_exists 1
    write_value image_id image-a
    while [[ $# -gt 0 ]]; do
      case "$1" in
        --label)
          case "$2" in
            hermes.repo_url=*) write_value image_label_hermes_repo_url "${2#hermes.repo_url=}" ;;
            hermes.ref=*) write_value image_label_hermes_ref "${2#hermes.ref=}" ;;
          esac
          shift 2 ;;
        *) shift ;;
      esac
    done ;;
  container)
    action="${1:?}"; shift || true
    case "$action" in
      exists) log_call "container exists $*"; [[ "$(read_value container_exists)" == "1" ]] ;;
      *) exit 1 ;;
    esac ;;
  inspect)
    log_call "inspect $*"
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

export PATH="$MOCK_BIN:$PATH"
export STATE_DIR
export HERMES_BASE_ROOT="$TMPDIR/workspaces"
export HERMES_IMAGE_NAME="mock-hermes-image"
export HERMES_REPO_URL="https://github.com/NousResearch/hermes-agent.git"
export HERMES_REF="v1.2.3"

reset_state
write_file "$STATE_DIR/image_exists" "1"
"$ROOT/scripts/shared/hermes-build" > "$STATE_DIR/build-skip.out"
assert_contains "$STATE_DIR/build-skip.out" 'Hermes image already exists: mock-hermes-image' 'build reports existing image'
assert_not_contains "$STATE_DIR/podman.log" 'build ' 'build skip path does not build'

reset_state
"$ROOT/scripts/shared/hermes-build" > "$STATE_DIR/build-run.out"
assert_contains "$STATE_DIR/build-run.out" 'Building Hermes image' 'build reports image build'
assert_contains "$STATE_DIR/podman.log" 'build --pull=always' 'build invokes podman build'

reset_state
write_file "$STATE_DIR/image_exists" "1"
write_file "$STATE_DIR/image_label_hermes_repo_url" 'https://github.com/NousResearch/hermes-agent.git'
write_file "$STATE_DIR/image_label_hermes_ref" 'v1.2.3'
"$ROOT/scripts/shared/hermes-upgrade" > "$STATE_DIR/upgrade-skip.out"
assert_contains "$STATE_DIR/upgrade-skip.out" 'No upgrade needed' 'upgrade skips when source matches'

reset_state
write_file "$STATE_DIR/image_exists" "1"
write_file "$STATE_DIR/image_label_hermes_repo_url" 'https://github.com/NousResearch/hermes-agent.git'
write_file "$STATE_DIR/image_label_hermes_ref" 'v1.2.2'
"$ROOT/scripts/shared/hermes-upgrade" > "$STATE_DIR/upgrade-run.out"
assert_contains "$STATE_DIR/upgrade-run.out" 'Upgrading Hermes image: mock-hermes-image' 'upgrade rebuilds when ref differs'
assert_contains "$STATE_DIR/podman.log" 'image rm -f mock-hermes-image' 'upgrade removes image before rebuild'

reset_state
write_file "$STATE_DIR/image_exists" "1"
write_file "$STATE_DIR/image_id" 'image-a'
write_file "$STATE_DIR/image_label_hermes_repo_url" 'https://github.com/NousResearch/hermes-agent.git'
write_file "$STATE_DIR/image_label_hermes_ref" 'v1.2.3'
mkdir -p "$HERMES_BASE_ROOT/ezirius"
touch "$HERMES_BASE_ROOT/ezirius/.env"
"$ROOT/scripts/shared/bootstrap" ezirius --help > "$STATE_DIR/bootstrap.out"
assert_contains "$STATE_DIR/bootstrap.out" 'No upgrade needed' 'bootstrap checks upgrade before start'
assert_contains "$STATE_DIR/podman.log" 'run -d --name hermes-agent-ezirius' 'bootstrap starts container'
assert_contains "$STATE_DIR/podman.log" "$HERMES_BASE_ROOT/ezirius/workspace:/workspace" 'bootstrap mounts persistent workspace directory'
assert_contains "$STATE_DIR/podman.log" 'exec -i -w /workspace hermes-agent-ezirius hermes --help' 'bootstrap opens Hermes inside container'

echo "Runtime behaviour checks passed"
