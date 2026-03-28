#!/usr/bin/env bash

HERMES_IMAGE_NAME="${HERMES_IMAGE_NAME:-hermes-agent-local}"
HERMES_PROJECT_PREFIX="${HERMES_PROJECT_PREFIX:-hermes-agent}"
HERMES_REPO_URL="${HERMES_REPO_URL:-https://github.com/NousResearch/hermes-agent.git}"
HERMES_REF="${HERMES_REF:-latest-release}"
HERMES_GITHUB_API_BASE="${HERMES_GITHUB_API_BASE:-https://api.github.com}"
HERMES_BASE_ROOT="${HERMES_BASE_ROOT:-~/Documents/Ezirius/.applications-data/.hermes-agent}"

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
  require_python3

  python3 - "$ROOT" <<'PY'
import hashlib
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
paths = [root / "config/containers/Dockerfile"]
patches_dir = root / "config/patches"
if patches_dir.exists():
    paths.extend(sorted(path for path in patches_dir.rglob("*") if path.is_file()))

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
  if [[ "$value" == ~* ]]; then
    printf '%s' "${value/#\~/$HOME}"
  else
    printf '%s' "$value"
  fi
}

normalize_absolute_path() {
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
    "$HERMES_HOME_DIR/image_cache" \
    "$HERMES_HOME_DIR/audio_cache" \
    "$WORKSPACE_ROOT/workspace" \
    "$HERMES_HOME_DIR/whatsapp/session"
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
    "hooks" \
    "image_cache" \
    "audio_cache" \
    "whatsapp"
  do
    if [[ ! -e "$WORKSPACE_ROOT/$path" ]]; then
      continue
    fi

    target="$HERMES_HOME_DIR/$path"

    if [[ -d "$WORKSPACE_ROOT/$path" ]]; then
      mkdir -p "$target"
      shopt -s dotglob nullglob
      if [[ -d "$WORKSPACE_ROOT/$path" ]]; then
        mv "$WORKSPACE_ROOT/$path"/* "$target"/ 2>/dev/null || true
        rmdir "$WORKSPACE_ROOT/$path" 2>/dev/null || true
      fi
      shopt -u dotglob nullglob
    elif [[ ! -e "$target" ]]; then
      mv "$WORKSPACE_ROOT/$path" "$target"
    fi
  done

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

  case "$repo_url" in
    https://github.com/*)
      repo_url="${repo_url#https://github.com/}"
      ;;
    http://github.com/*)
      repo_url="${repo_url#http://github.com/}"
      ;;
    git@github.com:*)
      repo_url="${repo_url#git@github.com:}"
      ;;
    *)
      fail "HERMES_REF=latest-release requires a GitHub repo URL; set HERMES_REF explicitly for non-GitHub sources"
      ;;
  esac

  repo_url="${repo_url%.git}"
  [[ "$repo_url" = */* ]] || fail "could not derive owner/repo from HERMES_REPO_URL: $1"
  printf '%s' "$repo_url"
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
