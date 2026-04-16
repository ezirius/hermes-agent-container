#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
source "$ROOT/lib/shell/common.sh"

if [[ "${HERMES_ENABLE_SMOKE_BUILDS:-0}" != "1" ]]; then
  echo "Smoke build checks skipped (set HERMES_ENABLE_SMOKE_BUILDS=1 to enable)"
  exit 0
fi

command -v podman >/dev/null 2>&1 || {
  printf 'podman is required for smoke build checks\n' >&2
  exit 1
}

assert_eq() {
  local expected="$1" actual="$2" message="$3"
  [[ "$expected" == "$actual" ]] || {
    printf 'assertion failed: %s\nexpected: %s\nactual:   %s\n' "$message" "$expected" "$actual" >&2
    exit 1
  }
}

IMAGE_NAME="${HERMES_SMOKE_IMAGE_NAME:-hermes-agent-smoke-$RANDOM-$$}"
LANE="${HERMES_SMOKE_LANE:-test}"
UPSTREAM="${HERMES_SMOKE_UPSTREAM:-main}"

cleanup() {
  podman image rm -f "${IMAGE_NAME}" >/dev/null 2>&1 || true
  podman images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | while IFS= read -r ref; do
    [[ "$ref" == "$IMAGE_NAME:"* || "$ref" == "localhost/$IMAGE_NAME:"* ]] || continue
    podman image rm -f "$ref" >/dev/null 2>&1 || true
  done
  [[ -z "${SMOKE_MOUNT_DIR:-}" ]] || rm -rf "$SMOKE_MOUNT_DIR"
}
trap cleanup EXIT

HERMES_IMAGE_NAME="$IMAGE_NAME" "$ROOT/scripts/shared/hermes-build" "$LANE" "$UPSTREAM"

BUILT_REF="$(podman images --format '{{.Repository}}:{{.Tag}}' | grep -E "^(localhost/)?${IMAGE_NAME}:" | head -n 1)"
[[ -n "$BUILT_REF" ]] || {
  printf 'smoke build did not produce an image for %s\n' "$IMAGE_NAME" >&2
  exit 1
}

ENTRYPOINT="$(podman image inspect -f '{{json .Config.Entrypoint}}' "$BUILT_REF")"
USER_NAME="$(podman image inspect -f '{{.Config.User}}' "$BUILT_REF")"
WORKDIR="$(podman image inspect -f '{{.Config.WorkingDir}}' "$BUILT_REF")"
CMD_JSON="$(podman image inspect -f '{{json .Config.Cmd}}' "$BUILT_REF")"
LABEL_LANE="$(podman image inspect -f "{{ index .Config.Labels \"$HERMES_LABEL_LANE\" }}" "$BUILT_REF")"
LABEL_REF="$(podman image inspect -f "{{ index .Config.Labels \"$HERMES_LABEL_UPSTREAM\" }}" "$BUILT_REF")"
EXPOSED_PORTS_STATE="$(podman image inspect -f '{{if .Config.ExposedPorts}}set{{else}}unset{{end}}' "$BUILT_REF")"

assert_eq '["/usr/bin/tini","--","/usr/local/bin/hermes-entrypoint.sh"]' "$ENTRYPOINT" 'image entrypoint is set to tini plus the wrapper entrypoint'
assert_eq 'hermes' "$USER_NAME" 'image finishes as the hermes user'
assert_eq '["sleep","infinity"]' "$CMD_JSON" 'image keeps the idle sleep command for the wrapper container lifecycle'
assert_eq "$HERMES_CONTAINER_WORKSPACE_DIR" "$WORKDIR" 'image workdir is the configured Hermes workspace path'
assert_eq "$LANE" "$LABEL_LANE" 'image label preserves the build lane'
assert_eq 'unset' "$EXPOSED_PORTS_STATE" 'image does not expose ports by default'

if [[ "$UPSTREAM" == "main" ]]; then
  assert_eq 'main' "$LABEL_REF" 'image label preserves the main upstream selector'
fi

podman run --rm "$BUILT_REF" --help >/dev/null
podman run --rm --entrypoint /bin/sh "$BUILT_REF" -lc "test \"\$HOME\" = \"$HERMES_CONTAINER_RUNTIME_HOME\" && test \"\$PWD\" = \"$HERMES_CONTAINER_WORKSPACE_DIR\" && test \"\$HERMES_HOME\" = \"$HERMES_CONTAINER_RUNTIME_HOME\" && test -x /usr/local/bin/hermes-entrypoint.sh"
SMOKE_MOUNT_DIR="$(mktemp -d)"
mkdir -p "$SMOKE_MOUNT_DIR/hermes-home" "$SMOKE_MOUNT_DIR/hermes-workspace"
podman run --rm \
  -v "$SMOKE_MOUNT_DIR/hermes-home:$HERMES_CONTAINER_RUNTIME_HOME" \
  -v "$SMOKE_MOUNT_DIR/hermes-workspace:$HERMES_CONTAINER_WORKSPACE_DIR" \
  --entrypoint /bin/sh "$BUILT_REF" -lc "touch $HERMES_CONTAINER_RUNTIME_HOME/.write-check $HERMES_CONTAINER_WORKSPACE_DIR/.write-check"
test -f "$SMOKE_MOUNT_DIR/hermes-home/.write-check"
test -f "$SMOKE_MOUNT_DIR/hermes-workspace/.write-check"

echo "Smoke build checks passed"
