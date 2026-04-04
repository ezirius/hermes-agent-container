#!/usr/bin/env bash

HERMES_IMAGE_NAME="${HERMES_IMAGE_NAME:-hermes-agent-local}"
HERMES_PROJECT_PREFIX="${HERMES_PROJECT_PREFIX:-hermes-agent}"
HERMES_REPO_URL="${HERMES_REPO_URL:-https://github.com/NousResearch/hermes-agent.git}"
HERMES_REF="${HERMES_REF:-latest-release}"
HERMES_GITHUB_API_BASE="${HERMES_GITHUB_API_BASE:-https://api.github.com}"
HERMES_BASE_ROOT="${HERMES_BASE_ROOT:-$HOME/Documents/Ezirius/.applications-data/.hermes-agent}"

fail() {
  echo "Error: $*" >&2
  exit 1
}

usage_error() {
  echo "Usage: $1" >&2
  exit 1
}

show_help() {
  printf '%s\n' "$1"
  exit 0
}

require_podman() {
  command -v podman >/dev/null 2>&1 || fail "podman is required"
}

require_python3() {
  command -v python3 >/dev/null 2>&1 || fail "python3 is required"
}

use_interactive_tty() {
  if [[ ${HERMES_FORCE_EXEC_TTY:-} == "1" ]]; then
    return 0
  fi

  [[ -t 0 ]]
}

should_wrap_podman_tty_with_script() {
  local mode="${HERMES_PODMAN_TTY_WRAPPER:-auto}"

  case "$mode" in
    none)
      return 1
      ;;
    script)
      command -v script >/dev/null 2>&1 || fail "HERMES_PODMAN_TTY_WRAPPER=script requires 'script' to be installed"
      return 0
      ;;
    auto)
      [[ ${OSTYPE-} == darwin* ]] && command -v script >/dev/null 2>&1
      return $?
      ;;
    *)
      fail "unsupported HERMES_PODMAN_TTY_WRAPPER value: $mode"
      ;;
  esac
}

exec_podman_interactive_command() {
  local subcommand="$1"
  shift

  if use_interactive_tty; then
    if should_wrap_podman_tty_with_script; then
      local command=(podman "$subcommand" -it "$@")
      if [[ ${OSTYPE-} == darwin* ]]; then
        exec script -q /dev/null "${command[@]}"
      fi

      local quoted=()
      local arg
      local command_string
      for arg in "${command[@]}"; do
        printf -v arg '%q' "$arg"
        quoted+=("$arg")
      done
      command_string="${quoted[*]}"
      exec script -q -e -c "$command_string" /dev/null
    fi
    exec podman "$subcommand" -it "$@"
  fi

  exec podman "$subcommand" -i "$@"
}

image_exists() {
  podman image exists "$HERMES_IMAGE_NAME"
}

image_label() {
  local key="$1"
  local value

  value="$(podman image inspect -f "{{ index .Labels \"$key\" }}" "$HERMES_IMAGE_NAME" 2>/dev/null || true)"
  if [[ "$value" == "<no value>" ]]; then
    value=""
  fi
  printf '%s' "$value"
}

local_build_fingerprint() {
  [[ -n "${ROOT:-}" ]] || fail "ROOT must be set before calling local_build_fingerprint"
  require_python3

  python3 - "$ROOT" <<'PY'
import hashlib
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
tracked_dirs = [root / "config/containers", root / "config/patches"]
paths = []
for tracked_dir in tracked_dirs:
    if not tracked_dir.exists():
        continue
    paths.extend(
        sorted(
            path
            for path in tracked_dir.rglob("*")
            if path.is_file()
            and "__pycache__" not in path.parts
            and path.suffix != ".pyc"
            and path.name != ".DS_Store"
        )
    )

if not paths:
    raise SystemExit("no local image recipe files found for fingerprinting")


digest = hashlib.sha256()
for path in paths:
    relative = path.relative_to(root).as_posix()
    digest.update(relative.encode("utf-8"))
    digest.update(b"\0")
    digest.update(path.read_bytes())
    digest.update(b"\0")

print(digest.hexdigest())
PY
}

current_image_build_fingerprint() {
  image_label hermes.wrapper_fingerprint
}

normalize_path() {
  local value="$1"
  case "$value" in
    "~")
      printf '%s' "${HOME:?HOME is required}"
      ;;
    "~/"*)
      printf '%s' "${HOME:?HOME is required}/${value#~/}"
      ;;
    "~"*)
      fail "unsupported path form: $value (use an absolute path or ~/...)"
      ;;
    *)
      printf '%s' "$value"
      ;;
  esac
}

normalize_absolute_path() {
  require_python3
  python3 - "$1" <<'PY'
import os, sys
print(os.path.abspath(sys.argv[1]))
PY
}

require_workspace_name() {
  local name="$1"
  [[ -n "$name" ]] || fail "workspace name must not be empty"
  [[ "$name" != */* ]] || fail "workspace name must not contain path separators"
  [[ "$name" != "." ]] || fail "workspace name must not be '.'"
  [[ "$name" != ".." ]] || fail "workspace name must not be '..'"
  [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || fail "workspace name may only contain letters, numbers, dots, underscores, and hyphens"
}

resolve_workspace() {
  local input="${1:?workspace required}"
  local workspace_base_root

  require_workspace_name "$input"
  WORKSPACE_NAME="$input"
  WORKSPACE_INPUT="$input"
  workspace_base_root="$(normalize_path "$HERMES_BASE_ROOT")"
  WORKSPACE_ROOT="$(normalize_absolute_path "$workspace_base_root/$WORKSPACE_NAME")"
  HERMES_HOME_DIR="$WORKSPACE_ROOT/hermes-home"
  HERMES_ENV_FILE="$HERMES_HOME_DIR/.env"
  HERMES_CONFIG_FILE="$HERMES_HOME_DIR/config.yaml"
  HERMES_WORKSPACE_DIR="$WORKSPACE_ROOT/workspace"
  HERMES_CONTAINER_NAME="${HERMES_PROJECT_PREFIX}-${WORKSPACE_NAME}"
}

ensure_workspace_dirs() {
  mkdir -p \
    "$WORKSPACE_ROOT" \
    "$HERMES_HOME_DIR" \
    "$HERMES_HOME_DIR/cron" \
    "$HERMES_HOME_DIR/sessions" \
    "$HERMES_HOME_DIR/logs" \
    "$HERMES_HOME_DIR/memories" \
    "$HERMES_HOME_DIR/skills" \
    "$HERMES_HOME_DIR/pairing" \
    "$HERMES_HOME_DIR/hooks" \
    "$HERMES_HOME_DIR/cache/images" \
    "$HERMES_HOME_DIR/cache/audio" \
    "$HERMES_HOME_DIR/platforms/whatsapp/session" \
    "$WORKSPACE_ROOT/workspace"
}

move_path_contents() {
  local source="$1"
  local target="$2"

  [[ -e "$source" ]] || return 0

  if [[ -d "$source" ]]; then
    mkdir -p "$target"
    local entries=()
    local entry
    local destination
    shopt -s dotglob nullglob
    entries=("$source"/*)
    shopt -u dotglob nullglob

    if [[ ${#entries[@]} -eq 0 ]]; then
      rmdir "$source" 2>/dev/null || true
      return 0
    fi

    for entry in "${entries[@]}"; do
      destination="$target/$(basename "$entry")"
      [[ ! -e "$destination" ]] || fail "migration target already exists: $destination"
      mv "$entry" "$target/"
    done
    rmdir "$source" || fail "failed to remove migrated legacy directory: $source"
  else
    [[ ! -e "$target" ]] || fail "migration target already exists: $target"
    mkdir -p "$(dirname "$target")"
    mv "$source" "$target"
  fi
}

migrate_legacy_workspace_layout() {
  local path
  local target

  for path in \
    ".hermes_history" \
    ".update_check" \
    "auth.json" \
    "auth.lock" \
    "config.yaml" \
    "state.db" \
    "state.db-shm" \
    "state.db-wal" \
    "bin" \
    "cron" \
    "logs" \
    "memories" \
    "pairing" \
    "sandboxes" \
    "sessions" \
    "skills" \
    "hooks"
  do
    if [[ ! -e "$WORKSPACE_ROOT/$path" ]]; then
      continue
    fi

    target="$HERMES_HOME_DIR/$path"
    move_path_contents "$WORKSPACE_ROOT/$path" "$target"
  done

  move_path_contents "$WORKSPACE_ROOT/image_cache" "$HERMES_HOME_DIR/cache/images"
  move_path_contents "$WORKSPACE_ROOT/audio_cache" "$HERMES_HOME_DIR/cache/audio"
  move_path_contents "$WORKSPACE_ROOT/whatsapp/session" "$HERMES_HOME_DIR/platforms/whatsapp/session"
  [[ -d "$WORKSPACE_ROOT/whatsapp" ]] && rmdir "$WORKSPACE_ROOT/whatsapp" 2>/dev/null || true

  move_path_contents "$HERMES_HOME_DIR/image_cache" "$HERMES_HOME_DIR/cache/images"
  move_path_contents "$HERMES_HOME_DIR/audio_cache" "$HERMES_HOME_DIR/cache/audio"
  move_path_contents "$HERMES_HOME_DIR/whatsapp/session" "$HERMES_HOME_DIR/platforms/whatsapp/session"
  [[ -d "$HERMES_HOME_DIR/whatsapp" ]] && rmdir "$HERMES_HOME_DIR/whatsapp" 2>/dev/null || true

  if [[ -f "$WORKSPACE_ROOT/.env" && ! -e "$HERMES_ENV_FILE" ]]; then
    mv "$WORKSPACE_ROOT/.env" "$HERMES_ENV_FILE"
  fi
}

container_exists() {
  podman container exists "$HERMES_CONTAINER_NAME"
}

container_running() {
  [[ "$(podman inspect -f '{{.State.Running}}' "$HERMES_CONTAINER_NAME" 2>/dev/null)" == "true" ]]
}

container_image_id() {
  podman inspect -f '{{.Image}}' "$HERMES_CONTAINER_NAME" 2>/dev/null
}

image_id() {
  podman image inspect -f '{{.Id}}' "$HERMES_IMAGE_NAME" 2>/dev/null
}

github_repo_slug() {
  local repo_url="$1"
  require_python3

  python3 - "$repo_url" <<'PY'
import re
import sys
from urllib.parse import urlparse

repo_url = sys.argv[1].strip()
path = None

scp_like = re.match(r'^[^@]+@[^:]+:(.+)$', repo_url)
if scp_like:
    path = scp_like.group(1)
else:
    parsed = urlparse(repo_url)
    if parsed.scheme and parsed.path:
        path = parsed.path.lstrip('/')

if not path:
    raise SystemExit('could not derive owner/repo from HERMES_REPO_URL: ' + repo_url)

path = path.rstrip('/')
if path.endswith('.git'):
    path = path[:-4]
parts = [part for part in path.split('/') if part]
if len(parts) != 2:
    raise SystemExit('could not derive owner/repo from HERMES_REPO_URL: ' + repo_url)
print('/'.join(parts))
PY
}

resolve_hermes_ref() {
  local requested_ref="${HERMES_REF:-latest-release}"
  local repo_slug

  if [[ "$requested_ref" != "latest-release" ]]; then
    printf '%s' "$requested_ref"
    return 0
  fi

  require_python3
  repo_slug="$(github_repo_slug "$HERMES_REPO_URL")"

  HERMES_REPO_SLUG="$repo_slug" python3 - <<'PY'
import json, os, sys, urllib.error, urllib.request
base = os.environ.get("HERMES_GITHUB_API_BASE", "https://api.github.com").rstrip("/")
repo_slug = os.environ["HERMES_REPO_SLUG"].strip("/")
latest_url = f"{base}/repos/{repo_slug}/releases/latest"
headers = {"Accept": "application/vnd.github+json", "User-Agent": "hermes-agent-container/1.0"}
def fetch_json(url):
    req = urllib.request.Request(url, headers=headers)
    with urllib.request.urlopen(req, timeout=20) as response:
        return json.load(response)
try:
    latest = fetch_json(latest_url)
except urllib.error.HTTPError as exc:
    if exc.code == 404:
        raise SystemExit("Latest upstream Hermes release not found")
    raise SystemExit(f"failed to resolve latest upstream Hermes release: HTTP {exc.code}")
except urllib.error.URLError as exc:
    raise SystemExit(f"failed to resolve latest upstream Hermes release: {exc.reason}")
tag_name = latest.get("tag_name", "")
if not tag_name:
    raise SystemExit("Latest upstream Hermes release did not include a tag name")
print(tag_name)
PY
}
