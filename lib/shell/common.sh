#!/usr/bin/env bash

__env_HERMES_IMAGE_NAME="${HERMES_IMAGE_NAME-}"
__env_HERMES_PROJECT_PREFIX="${HERMES_PROJECT_PREFIX-}"
__env_HERMES_REPO_URL="${HERMES_REPO_URL-}"
__env_HERMES_GITHUB_API_BASE="${HERMES_GITHUB_API_BASE-}"
__env_HERMES_UBUNTU_LTS_VERSION="${HERMES_UBUNTU_LTS_VERSION-}"
__env_HERMES_NODE_LTS_VERSION="${HERMES_NODE_LTS_VERSION-}"
__env_HERMES_BASE_ROOT="${HERMES_BASE_ROOT-}"

if [[ -n "${ROOT:-}" && -f "$ROOT/config/shared/hermes.conf" ]]; then
  # shellcheck disable=SC1090
  source "$ROOT/config/shared/hermes.conf"
fi

[[ -z "${__env_HERMES_IMAGE_NAME}" ]] || HERMES_IMAGE_NAME="$__env_HERMES_IMAGE_NAME"
[[ -z "${__env_HERMES_PROJECT_PREFIX}" ]] || HERMES_PROJECT_PREFIX="$__env_HERMES_PROJECT_PREFIX"
[[ -z "${__env_HERMES_REPO_URL}" ]] || HERMES_REPO_URL="$__env_HERMES_REPO_URL"
[[ -z "${__env_HERMES_GITHUB_API_BASE}" ]] || HERMES_GITHUB_API_BASE="$__env_HERMES_GITHUB_API_BASE"
[[ -z "${__env_HERMES_UBUNTU_LTS_VERSION}" ]] || HERMES_UBUNTU_LTS_VERSION="$__env_HERMES_UBUNTU_LTS_VERSION"
[[ -z "${__env_HERMES_NODE_LTS_VERSION}" ]] || HERMES_NODE_LTS_VERSION="$__env_HERMES_NODE_LTS_VERSION"
[[ -z "${__env_HERMES_BASE_ROOT}" ]] || HERMES_BASE_ROOT="$__env_HERMES_BASE_ROOT"
unset __env_HERMES_IMAGE_NAME __env_HERMES_PROJECT_PREFIX __env_HERMES_REPO_URL __env_HERMES_GITHUB_API_BASE __env_HERMES_UBUNTU_LTS_VERSION __env_HERMES_NODE_LTS_VERSION __env_HERMES_BASE_ROOT

HERMES_IMAGE_NAME="${HERMES_IMAGE_NAME:-hermes-agent-local}"
HERMES_PROJECT_PREFIX="${HERMES_PROJECT_PREFIX:-hermes-agent}"
HERMES_REPO_URL="${HERMES_REPO_URL:-https://github.com/NousResearch/hermes-agent.git}"
HERMES_REF="${HERMES_REF:-latest}"
HERMES_GITHUB_API_BASE="${HERMES_GITHUB_API_BASE:-https://api.github.com}"
HERMES_UBUNTU_LTS_VERSION="${HERMES_UBUNTU_LTS_VERSION:-24.04}"
HERMES_NODE_LTS_VERSION="${HERMES_NODE_LTS_VERSION:-24}"
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
  local image_ref="${1:-$HERMES_IMAGE_NAME}"
  podman image exists "$image_ref"
}

image_label() {
  local key="$1"
  local image_ref="${2:-$HERMES_IMAGE_NAME}"
  local value

  value="$(podman image inspect -f "{{ index .Labels \"$key\" }}" "$image_ref" 2>/dev/null || true)"
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
  local image_ref="${1:-$HERMES_IMAGE}"
  image_label hermes.wrapper_fingerprint "$image_ref"
}

normalize_path() {
  local value="$1"
  case "$value" in
    "~")
      printf '%s' "${HOME:?HOME is required}"
      ;;
    "~/"*)
      printf '%s' "${HOME:?HOME is required}/${value#\~/}"
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

is_ignorable_host_untracked_path() {
  local path="$1"

  case "$path" in
    .DS_Store|*/.DS_Store|.AppleDouble|*/.AppleDouble|.LSOverride|*/.LSOverride|Icon$'\r'|*/Icon$'\r'|._*|*/._*|.Spotlight-V100|.Spotlight-V100/*|*/.Spotlight-V100|*/.Spotlight-V100/*|.Trashes|.Trashes/*|*/.Trashes|*/.Trashes/*|.fseventsd|.fseventsd/*|*/.fseventsd|*/.fseventsd/*)
      return 0
      ;;
  esac

  return 1
}

has_meaningful_untracked_files() {
  local path

  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    if ! is_ignorable_host_untracked_path "$path"; then
      return 0
    fi
  done

  return 1
}

git_has_meaningful_worktree_changes() {
  local git_prefix=("$@")
  local diff_args
  local numstat_output
  local summary_output
  local line
  local additions
  local deletions
  local untracked_output

  # Refresh the index first so host-side stat noise does not show up as a
  # false-positive dirty worktree when file content is unchanged.
  "${git_prefix[@]}" update-index -q --refresh >/dev/null 2>&1 || true

  for diff_args in "" "--cached"; do
    if [[ -n "$diff_args" ]]; then
      numstat_output="$("${git_prefix[@]}" diff "$diff_args" --numstat 2>/dev/null || true)"
    else
      numstat_output="$("${git_prefix[@]}" diff --numstat 2>/dev/null || true)"
    fi
    while IFS=$'\t' read -r additions deletions _; do
      [[ -n "$additions" ]] || continue
      if [[ "$additions" != "0" || "$deletions" != "0" ]]; then
        return 0
      fi
    done <<< "$numstat_output"

    if [[ -n "$diff_args" ]]; then
      summary_output="$("${git_prefix[@]}" diff "$diff_args" --summary 2>/dev/null || true)"
    else
      summary_output="$("${git_prefix[@]}" diff --summary 2>/dev/null || true)"
    fi

    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      if [[ "$line" != ' mode change '* ]]; then
        return 0
      fi
    done <<< "$summary_output"
  done

  untracked_output="$("${git_prefix[@]}" ls-files --others --exclude-standard 2>/dev/null || true)"
  if has_meaningful_untracked_files <<<"$untracked_output"; then
    return 0
  fi

  return 1
}

current_wrapper_workdir() {
  if [[ -n "${ROOT:-}" ]]; then
    printf '%s' "$ROOT"
    return 0
  fi
  pwd
}

git_is_primary_worktree() {
  local workdir="${1:-$(current_wrapper_workdir)}"
  local git_dir
  local common_dir

  git_dir="$(git -C "$workdir" rev-parse --git-dir 2>/dev/null)" || return 1
  common_dir="$(git -C "$workdir" rev-parse --git-common-dir 2>/dev/null)" || return 1
  git_dir="$(normalize_absolute_path "$workdir/$git_dir")"
  common_dir="$(normalize_absolute_path "$workdir/$common_dir")"
  [[ "$git_dir" == "$common_dir" ]]
}

fallback_repo_root() {
  local workdir="${1:-$(current_wrapper_workdir)}"
  local parent_dir
  local parent_base
  local repo_base
  local candidate

  parent_dir="$(dirname "$workdir")"
  parent_base="$(basename "$parent_dir")"
  if [[ "$parent_base" == *-worktrees ]]; then
    repo_base="${parent_base%-worktrees}"
    candidate="$parent_dir/../$repo_base"
    if git -C "$candidate" rev-parse --show-toplevel >/dev/null 2>&1; then
      normalize_absolute_path "$candidate"
      return 0
    fi
  fi

  return 1
}

fallback_ref_for_workdir() {
  local workdir="${1:-$(current_wrapper_workdir)}"
  local repo_root
  local context

  repo_root="$(fallback_repo_root "$workdir")" || return 1
  context="$(basename "$workdir")"

  if [[ "$context" == "main" ]]; then
    printf '%s' HEAD
    return 0
  fi

  if git -C "$repo_root" rev-parse --verify "refs/heads/$context" >/dev/null 2>&1; then
    printf '%s' "refs/heads/$context"
    return 0
  fi

  return 1
}

current_wrapper_context() {
  local workdir="${1:-$(current_wrapper_workdir)}"
  local basename_context

  if [[ -n "${HERMES_WRAPPER_CONTEXT_OVERRIDE:-}" ]]; then
    printf '%s' "$HERMES_WRAPPER_CONTEXT_OVERRIDE"
    return 0
  fi

  if git_is_primary_worktree "$workdir"; then
    printf '%s' "main"
    return 0
  fi

  basename_context="$(basename "$workdir")"
  [[ -n "$basename_context" ]] || fail "could not derive worktree context from $workdir"
  printf '%s' "$basename_context"
}

git_commit_stamp() {
  local workdir="${1:-$(current_wrapper_workdir)}"
  local timestamp
  local short_hash
  local fallback_repo
  local fallback_ref

  if [[ -n "${HERMES_COMMITSTAMP_OVERRIDE:-}" ]]; then
    printf '%s' "$HERMES_COMMITSTAMP_OVERRIDE"
    return 0
  fi

  timestamp="$(git -C "$workdir" show -s --format=%cd --date=format:%Y%m%d-%H%M%S HEAD 2>/dev/null || true)"
  short_hash="$(git -C "$workdir" rev-parse --short=7 HEAD 2>/dev/null || true)"
  if [[ -z "$timestamp" || -z "$short_hash" ]]; then
    fallback_repo="$(fallback_repo_root "$workdir" 2>/dev/null || true)"
    fallback_ref="$(fallback_ref_for_workdir "$workdir" 2>/dev/null || true)"
    if [[ -n "$fallback_repo" && -n "$fallback_ref" ]]; then
      timestamp="$(git -C "$fallback_repo" show -s --format=%cd --date=format:%Y%m%d-%H%M%S "$fallback_ref" 2>/dev/null || true)"
      short_hash="$(git -C "$fallback_repo" rev-parse --short=7 "$fallback_ref" 2>/dev/null || true)"
    fi
  fi
  [[ -n "$timestamp" && -n "$short_hash" ]] || fail "could not derive wrapper commit identity from $workdir"
  printf '%s-%s' "$timestamp" "$short_hash"
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
}

resolve_build_target() {
  local workspace="${1:?workspace required}"
  local lane="${2:?lane required}"
  local ref="${3:?ref required}"
  local wrapper_context="${4:-}"
  local commitstamp="${5:-}"

  if [[ "$lane" != "production" && "$lane" != "test" ]]; then
    fail "lane must be 'production' or 'test', got: $lane"
  fi

  if [[ "$ref" == "latest" || "$ref" == "main" ]]; then
    : # valid
  elif [[ "$ref" =~ ^[v]?[0-9]+[.][0-9]+[.][0-9]+ ]]; then
    : # semver-style version
  elif [[ "$ref" =~ ^[a-zA-Z0-9._-]+$ ]]; then
    : # generic tag-like ref
  else
    fail "ref must be 'latest', 'main', or a version string (e.g. 0.7.0, v0.21.0), got: $ref"
  fi

  local version_tag
  version_tag="$(resolve_hermes_ref "$ref")"
  [[ -n "$wrapper_context" ]] || wrapper_context="$(current_wrapper_context)"
  [[ -n "$commitstamp" ]] || commitstamp="$(git_commit_stamp)"

  local workspace_base_root
  workspace_base_root="$(normalize_path "$HERMES_BASE_ROOT")"
  WORKSPACE_NAME="$workspace"
  WORKSPACE_INPUT="$workspace"
  WORKSPACE_ROOT="$(normalize_absolute_path "$workspace_base_root/$workspace")"
  HERMES_HOME_DIR="$WORKSPACE_ROOT/hermes-home"
  HERMES_ENV_FILE="$HERMES_HOME_DIR/.env"
  HERMES_CONFIG_FILE="$HERMES_HOME_DIR/config.yaml"
  HERMES_WORKSPACE_DIR="$WORKSPACE_ROOT/workspace"

  HERMES_UPSTREAM_REF="$version_tag"
  HERMES_WRAPPER_CONTEXT="$wrapper_context"
  HERMES_COMMITSTAMP="$commitstamp"
  HERMES_CONTAINER_NAME="${HERMES_PROJECT_PREFIX}-${workspace}-${lane}-${version_tag}-${wrapper_context}"
  HERMES_IMAGE_TAG="${lane}-${version_tag}-${wrapper_context}-${commitstamp}"
  HERMES_IMAGE="${HERMES_IMAGE_NAME}:${HERMES_IMAGE_TAG}"
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
  local container_name="${1:-$HERMES_CONTAINER_NAME}"
  podman container exists "$container_name"
}

container_running() {
  local container_name="${1:-$HERMES_CONTAINER_NAME}"
  [[ "$(podman inspect -f '{{.State.Running}}' "$container_name" 2>/dev/null)" == "true" ]]
}

container_image_id() {
  local container_name="${1:-$HERMES_CONTAINER_NAME}"
  podman inspect -f '{{.Image}}' "$container_name" 2>/dev/null
}

image_id() {
  local image_ref="${1:-$HERMES_IMAGE}"
  podman image inspect -f '{{.Id}}' "$image_ref" 2>/dev/null
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

resolve_hermes_selection() {
  local requested_ref="${1:-${HERMES_REF:-latest}}"
  local cached label value

  if [[ "$requested_ref" == "main" ]]; then
    printf 'main\tmain\n'
    return 0
  fi

  cached="$(release_option_cache)"
  if [[ "$requested_ref" == "latest" ]]; then
    while IFS=$'\t' read -r label value; do
      [[ -n "$label" && -n "$value" ]] || continue
      printf '%s\t%s\n' "$label" "$value"
      return 0
    done <<EOF
$cached
EOF
    fail "Latest upstream Hermes release not found"
  fi

  while IFS=$'\t' read -r label value; do
    [[ -n "$label" && -n "$value" ]] || continue
    if [[ "$requested_ref" == "$label" || "$requested_ref" == "$value" ]]; then
      printf '%s\t%s\n' "$label" "$value"
      return 0
    fi
  done <<EOF
$cached
EOF

  printf '%s\t%s\n' "$requested_ref" "$requested_ref"
}

resolve_hermes_ref() {
  local selection
  selection="$(resolve_hermes_selection "$@")"
  printf '%s' "${selection%%$'\t'*}"
}

require_clean_git() {
  if [[ -n "${HERMES_ALLOW_DIRTY:-}" ]]; then
    return 0
  fi

  local workdir="${1:-$ROOT}"
  local fallback_repo
  local fallback_ref
  local fallback_git_dir
  [[ -n "$workdir" ]] || fail "ROOT must be set before calling require_clean_git"

  if git -C "$workdir" rev-parse --git-dir >/dev/null 2>&1; then
    if git_has_meaningful_worktree_changes git -C "$workdir"; then
      fail "uncommitted changes detected in $workdir; commit or stash before building"
    fi
    return 0
  fi

  fallback_repo="$(fallback_repo_root "$workdir" 2>/dev/null || true)"
  fallback_ref="$(fallback_ref_for_workdir "$workdir" 2>/dev/null || true)"
  if [[ -n "$fallback_repo" && -n "$fallback_ref" ]]; then
    fallback_git_dir="$(git -C "$fallback_repo" rev-parse --git-dir 2>/dev/null || true)"
    [[ -n "$fallback_git_dir" ]] || fail "could not determine git metadata for fallback repo: $fallback_repo"
    if ! fallback_git_dir="$(normalize_absolute_path "$fallback_repo/$fallback_git_dir")"; then
      fail "could not normalize fallback git metadata path for $fallback_repo"
    fi

    if git_has_meaningful_worktree_changes git --git-dir="$fallback_git_dir" --work-tree="$workdir"; then
      fail "uncommitted changes detected in $workdir; commit or stash before building"
    fi

    if [[ "$(current_wrapper_context "$workdir")" == "main" ]] && git_has_meaningful_worktree_changes git -C "$fallback_repo"; then
      fail "uncommitted changes detected in $fallback_repo; commit or stash before building"
    fi
    return 0
  fi

  fail "could not determine git cleanliness for $workdir; ensure this is a valid git checkout/worktree before building"
}

require_canonical_main_checkout() {
  local workdir="${1:-$(current_wrapper_workdir)}"
  local branch

  git_is_primary_worktree "$workdir" || fail "production builds must run from the canonical main checkout, not a linked worktree"
  branch="$(git_branch_name "$workdir")"
  [[ "$branch" == "main" ]] || fail "production builds must run from branch 'main', got: $branch"
}

require_main_pushed() {
  local workdir="${1:-$(current_wrapper_workdir)}"
  local upstream
  local counts
  local ahead
  local behind

  upstream="$(git -C "$workdir" rev-parse --abbrev-ref --symbolic-full-name @{u} 2>/dev/null || true)"
  [[ -n "$upstream" ]] || fail "production builds require main to track an upstream branch"
  git -C "$workdir" fetch --quiet "${upstream%%/*}" >/dev/null 2>&1 || fail "failed to fetch upstream state for production build validation"
  counts="$(git -C "$workdir" rev-list --left-right --count "$upstream...HEAD")"
  behind="${counts%% *}"
  ahead="${counts##* }"
  [[ "$ahead" == "0" ]] || fail "production builds require main to have no unpushed commits"
  [[ "$behind" == "0" ]] || fail "production builds require main to be in sync with its upstream branch"
}

git_short_hash() {
  local workdir="${1:-$ROOT}"
  git -C "$workdir" rev-parse --short=7 HEAD
}

git_branch_name() {
  local workdir="${1:-$ROOT}"
  git -C "$workdir" symbolic-ref --short HEAD 2>/dev/null || git -C "$workdir" rev-parse --short HEAD
}

build_tags_for_lane() {
  local lane="$1"
  local resolved_ref="$2"
  local wrapper_context="$3"
  local commitstamp="$4"

  printf '%s\n' "${lane}-${resolved_ref}-${wrapper_context}-${commitstamp}"
}

list_upstream_release_tags() {
  local repo_slug
  require_python3
  repo_slug="$(github_repo_slug "$HERMES_REPO_URL")"
  HERMES_REPO_SLUG="$repo_slug" python3 - <<'PY'
import json, os, urllib.error, urllib.request
base = os.environ.get("HERMES_GITHUB_API_BASE", "https://api.github.com").rstrip("/")
repo_slug = os.environ["HERMES_REPO_SLUG"].strip("/")
url = f"{base}/repos/{repo_slug}/releases"
headers = {"Accept": "application/vnd.github+json", "User-Agent": "hermes-agent-container/1.0"}
req = urllib.request.Request(url, headers=headers)
try:
    with urllib.request.urlopen(req, timeout=20) as response:
        releases = json.load(response)
except urllib.error.HTTPError as exc:
    raise SystemExit(f"failed to list upstream Hermes releases: HTTP {exc.code}")
except urllib.error.URLError as exc:
    raise SystemExit(f"failed to list upstream Hermes releases: {exc.reason}")
for release in releases:
    tag = release.get("tag_name")
    if tag:
        print(tag)
PY
}

list_upstream_release_options() {
  local repo_slug
  require_python3
  repo_slug="$(github_repo_slug "$HERMES_REPO_URL")"
  HERMES_REPO_SLUG="$repo_slug" python3 - <<'PY'
import json, os, re, urllib.error, urllib.request
base = os.environ.get("HERMES_GITHUB_API_BASE", "https://api.github.com").rstrip("/")
repo_slug = os.environ["HERMES_REPO_SLUG"].strip("/")
url = f"{base}/repos/{repo_slug}/releases"
headers = {"Accept": "application/vnd.github+json", "User-Agent": "hermes-agent-container/1.0"}
req = urllib.request.Request(url, headers=headers)
try:
    with urllib.request.urlopen(req, timeout=20) as response:
        releases = json.load(response)
except urllib.error.HTTPError as exc:
    raise SystemExit(f"failed to list upstream Hermes releases: HTTP {exc.code}")
except urllib.error.URLError as exc:
    raise SystemExit(f"failed to list upstream Hermes releases: {exc.reason}")

for release in releases:
    tag = (release.get("tag_name") or "").strip()
    if not tag:
        continue
    name = (release.get("name") or "").strip()
    display = tag
    match = re.search(r"v?(\d+\.\d+\.\d+)", name)
    if match:
        display = match.group(1)
    elif name:
        display = name
    print(f"{display}\t{tag}")
PY
}

release_option_cache() {
  if [[ -z "${HERMES_RELEASE_OPTION_CACHE:-}" ]]; then
    HERMES_RELEASE_OPTION_CACHE="$(list_upstream_release_options 2>/dev/null || true)"
  fi
  printf '%s' "$HERMES_RELEASE_OPTION_CACHE"
}

display_upstream_ref() {
  local ref="$1"
  local cached line label value

  [[ "$ref" == "main" ]] && {
    printf '%s' "main"
    return 0
  }

  cached="$(release_option_cache)"
  while IFS=$'\t' read -r label value; do
    [[ -n "$label" && -n "$value" ]] || continue
    if [[ "$value" == "$ref" ]]; then
      printf '%s' "$label"
      return 0
    fi
  done <<EOF
$cached
EOF

  printf '%s' "$ref"
}

prompt_select_option() {
  local prompt="$1"
  shift
  local options=("$@")
  local index=1
  local selected
  local selection_source="${HERMES_SELECT_INDEX:-}"

  [[ ${#options[@]} -gt 0 ]] || fail "no options available for selection"

  if [[ -n "$selection_source" ]]; then
    selected="${selection_source%%,*}"
    if [[ "$selection_source" == *,* ]]; then
      HERMES_SELECT_INDEX="${selection_source#*,}"
    else
      unset HERMES_SELECT_INDEX
    fi
    [[ "$selected" =~ ^[0-9]+$ ]] || fail "HERMES_SELECT_INDEX must be numeric"
    (( selected >= 1 && selected <= ${#options[@]} )) || fail "HERMES_SELECT_INDEX out of range"
    printf '%s' "${options[selected-1]}"
    return 0
  fi

  printf '%s\n' "$prompt" >&2
  for option in "${options[@]}"; do
    printf '  %d. %s\n' "$index" "$option" >&2
    index=$((index + 1))
  done

  while true; do
    printf 'Select an option [1-%d]: ' "${#options[@]}" >&2
    read -r index
    [[ "$index" =~ ^[0-9]+$ ]] || continue
    if (( index >= 1 && index <= ${#options[@]} )); then
      printf '%s' "${options[index-1]}"
      return 0
    fi
  done
}

project_image_refs() {
  podman images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | grep -E "^(localhost/)?${HERMES_IMAGE_NAME}:" || true
}

project_container_names() {
  podman ps -a --format '{{.Names}}' 2>/dev/null | grep -E "^${HERMES_PROJECT_PREFIX}-" || true
}

image_metadata() {
  local image_ref="$1"
  local lane upstream wrapper commitstamp
  local tag remainder

  lane="$(image_label hermes.lane "$image_ref")"
  upstream="$(image_label hermes.ref "$image_ref")"
  wrapper="$(image_label hermes.wrapper_context "$image_ref")"
  commitstamp="$(image_label hermes.commitstamp "$image_ref")"

  if [[ -z "$lane" || -z "$upstream" || -z "$wrapper" || -z "$commitstamp" ]]; then
    tag="${image_ref##*:}"
    lane="${tag%%-*}"
    remainder="${tag#*-}"
    upstream="${remainder%%-*}"
    remainder="${remainder#*-}"
    commitstamp="$(printf '%s' "$remainder" | awk -F- '{ if (NF >= 4) print $(NF-2) "-" $(NF-1) "-" $NF; }')"
    wrapper="$remainder"
    if [[ -n "$commitstamp" ]]; then
      wrapper="${wrapper%-${commitstamp}}"
    fi
  fi

  if [[ "$lane" != "production" && "$lane" != "test" ]]; then
    return 1
  fi

  [[ -n "$upstream" ]] || return 1
  [[ -n "$wrapper" ]] || return 1
  [[ "$commitstamp" =~ ^[0-9]{8}-[0-9]{6}-[A-Za-z0-9]+$ ]] || return 1

  printf '%s\t%s\t%s\t%s\t%s\n' "$image_ref" "$lane" "$upstream" "$wrapper" "$commitstamp"
}

container_metadata() {
  local container_name="$1"
  local raw
  local lane upstream wrapper commitstamp status
  local parsed

  raw="$(podman inspect -f '{{index .Config.Labels "hermes.lane"}}|{{index .Config.Labels "hermes.ref"}}|{{index .Config.Labels "hermes.wrapper_context"}}|{{index .Config.Labels "hermes.commitstamp"}}|{{.State.Running}}' "$container_name" 2>/dev/null || true)"
  lane="${raw%%|*}"
  raw="${raw#*|}"
  upstream="${raw%%|*}"
  raw="${raw#*|}"
  wrapper="${raw%%|*}"
  raw="${raw#*|}"
  commitstamp="${raw%%|*}"
  status="${raw##*|}"

  if [[ -z "$lane" || -z "$upstream" || -z "$wrapper" ]]; then
    parsed="$(python3 - "$HERMES_PROJECT_PREFIX" "$container_name" <<'PY'
import sys
prefix = sys.argv[1]
name = sys.argv[2]
base = f"{prefix}-"
if not name.startswith(base):
    raise SystemExit(1)
rest = name[len(base):]
for lane in ("production", "test"):
    marker = f"-{lane}-"
    idx = rest.find(marker)
    if idx == -1:
        continue
    workspace = rest[:idx]
    tail = rest[idx + len(marker):]
    if not workspace or '-' not in tail:
        continue
    upstream, wrapper = tail.split('-', 1)
    if upstream and wrapper:
        print("\t".join((workspace, lane, upstream, wrapper)))
        raise SystemExit(0)
raise SystemExit(1)
PY
    2>/dev/null || true)"
    if [[ -n "$parsed" ]]; then
      IFS=$'\t' read -r _ lane upstream wrapper <<< "$parsed"
    fi
  fi

  [[ "$status" == "true" ]] && status="running" || status="stopped"
  if [[ "$lane" != "production" && "$lane" != "test" ]]; then
    return 1
  fi
  [[ -n "$upstream" ]] || return 1
  [[ -n "$wrapper" ]] || return 1
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$container_name" "$lane" "$upstream" "$wrapper" "$commitstamp" "$status"
}

container_workspace() {
  local container_name="$1"
  local workspace

  workspace="$(podman inspect -f '{{index .Config.Labels "hermes.workspace"}}' "$container_name" 2>/dev/null || true)"
  if [[ -n "$workspace" ]]; then
    printf '%s' "$workspace"
    return 0
  fi

  python3 - "$HERMES_PROJECT_PREFIX" "$container_name" <<'PY'
import sys
prefix = sys.argv[1]
name = sys.argv[2]
base = f"{prefix}-"
if not name.startswith(base):
    raise SystemExit(1)
rest = name[len(base):]
for lane in ("production", "test"):
    marker = f"-{lane}-"
    idx = rest.find(marker)
    if idx != -1:
        workspace = rest[:idx]
        if workspace:
            print(workspace)
            raise SystemExit(0)
raise SystemExit(1)
PY
}

image_ref_for_id() {
  local target_id="$1"
  local ref
  while IFS= read -r ref; do
    [[ -n "$ref" ]] || continue
    if [[ "$(image_id "$ref" 2>/dev/null || true)" == "$target_id" ]]; then
      printf '%s' "$ref"
      return 0
    fi
  done < <(project_image_refs)
  return 1
}

image_usage_status() {
  local image_ref="$1"
  local target_id
  local name

  target_id="$(image_id "$image_ref" 2>/dev/null || true)"
  [[ -n "$target_id" ]] || {
    printf '%s' 'unused'
    return 0
  }

  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    if [[ "$(container_image_id "$name" 2>/dev/null || true)" == "$target_id" ]]; then
      printf '%s' 'in use'
      return 0
    fi
  done < <(project_container_names)

  printf '%s' 'unused'
}

sort_targets() {
  require_python3
  python3 -c 'import sys; rows=[line.rstrip("\n").split("\t") for line in sys.stdin if line.strip()]; rows=sorted(rows, key=lambda row: (0 if row[1] == "production" else 1, "".join(chr(255 - ord(c)) for c in (row[4] if len(row) > 4 else "")))); [print("\t".join(row)) for row in rows]'
}

format_target_option() {
  local lane="$1"
  local upstream="$2"
  local wrapper="$3"
  local commitstamp="$4"
  local status="$5"

  printf '%-10s %-12s %-34s %-24s %s' "$lane" "$(display_upstream_ref "$upstream")" "$wrapper" "$commitstamp" "$status"
}

workspace_image_targets() {
  local workspace="$1"
  local image_ref metadata container_name status
  local image_identity
  local container_identity
  while IFS= read -r image_ref; do
    [[ -n "$image_ref" ]] || continue
    metadata="$(image_metadata "$image_ref" 2>/dev/null || true)"
    [[ -n "$metadata" ]] || continue
    IFS=$'\t' read -r _ lane upstream wrapper commitstamp <<< "$metadata"
    container_name="${HERMES_PROJECT_PREFIX}-${workspace}-${lane}-${upstream}-${wrapper}"
    image_identity="$(image_id "$image_ref" 2>/dev/null || true)"
    if podman container exists "$container_name" 2>/dev/null; then
      container_identity="$(container_image_id "$container_name" 2>/dev/null || true)"
      if [[ -n "$image_identity" && "$container_identity" == "$image_identity" && "$(podman inspect -f '{{.State.Running}}' "$container_name" 2>/dev/null)" == "true" ]]; then
        status="running"
      elif [[ -n "$image_identity" && "$container_identity" == "$image_identity" ]]; then
        status="stopped"
      else
        status="image only"
      fi
    else
      status="image only"
    fi
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$image_ref" "$lane" "$upstream" "$wrapper" "$commitstamp" "$status"
  done < <(project_image_refs)
}

workspace_container_targets() {
  local workspace="$1"
  local prefix="${HERMES_PROJECT_PREFIX}-${workspace}-"
  local name metadata
  while IFS= read -r name; do
    [[ "$name" == "$prefix"* ]] || continue
    metadata="$(container_metadata "$name" 2>/dev/null || true)"
    [[ -n "$metadata" ]] || continue
    printf '%s\n' "$metadata"
  done < <(project_container_names)
}

remove_candidates() {
  local mode="$1"
  if [[ "$mode" == "image" ]]; then
    while IFS= read -r ref; do
      [[ -n "$ref" ]] || continue
      metadata="$(image_metadata "$ref" 2>/dev/null || true)"
      [[ -n "$metadata" ]] || continue
      IFS=$'\t' read -r _ lane upstream wrapper commitstamp <<< "$metadata"
      printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$ref" "$lane" "$upstream" "$wrapper" "$commitstamp" "$(image_usage_status "$ref")"
    done < <(project_image_refs)
  else
    project_container_names | while read -r name; do
      [[ -n "$name" ]] || continue
      container_metadata "$name" 2>/dev/null || true
    done
  fi
}

pick_workspace_target() {
  local workspace="$1"
  local mode="$2"
  local rows=()
  local row display value

  if [[ "$mode" == "target" ]]; then
    while IFS= read -r row; do
      [[ -n "$row" ]] || continue
      rows+=("$row")
    done < <(workspace_image_targets "$workspace" | sort_targets)
  else
    while IFS= read -r row; do
      [[ -n "$row" ]] || continue
      rows+=("$row")
    done < <(workspace_container_targets "$workspace" | sort_targets)
  fi

  [[ ${#rows[@]} -gt 0 ]] || fail "no matching project ${mode}s exist for workspace: $workspace"

  local options=()
  for row in "${rows[@]}"; do
    IFS=$'\t' read -r value lane upstream wrapper commitstamp status <<< "$row"
    options+=("$(format_target_option "$lane" "$upstream" "$wrapper" "$commitstamp" "$status")")
  done

  display="$(prompt_select_option "Select ${mode} for workspace '$workspace'" "${options[@]}")"
  for i in "${!options[@]}"; do
    if [[ "${options[i]}" == "$display" ]]; then
      printf '%s' "${rows[i]}"
      return 0
    fi
  done
  fail "failed to resolve selected ${mode}"
}

pick_remove_target() {
  local mode="$1"
  local rows=()
  local row value lane upstream wrapper commitstamp status

  if [[ "$mode" == "image" ]]; then
    while IFS= read -r row; do
      [[ -n "$row" ]] || continue
      rows+=("$row")
    done < <(remove_candidates image | sort_targets)
  else
    while IFS= read -r row; do
      [[ -n "$row" ]] || continue
      rows+=("$row")
    done < <(remove_candidates container | sort_targets)
  fi

  [[ ${#rows[@]} -gt 0 ]] || fail "no project ${mode}s exist"

  local options=("All, but newest" "All")
  for row in "${rows[@]}"; do
    IFS=$'\t' read -r value lane upstream wrapper commitstamp status <<< "$row"
    options+=("$(format_target_option "$lane" "$upstream" "$wrapper" "$commitstamp" "$status")")
  done

  local selected
  selected="$(prompt_select_option "Select ${mode} removal target" "${options[@]}")"
  if [[ "$selected" == "All, but newest" || "$selected" == "All" ]]; then
    printf '%s' "$selected"
    return 0
  fi
  for i in "${!rows[@]}"; do
    if [[ "${options[i+2]}" == "$selected" ]]; then
      printf '%s' "${rows[i]}"
      return 0
    fi
  done
  fail "failed to resolve selected ${mode} removal target"
}

latest_ubuntu_lts_version() {
  require_python3
  python3 - <<'PY'
import re, urllib.request
url = "https://changelogs.ubuntu.com/meta-release-lts"
with urllib.request.urlopen(url, timeout=20) as response:
    text = response.read().decode("utf-8", "replace")
versions = []
for line in text.splitlines():
    if line.startswith("Version:"):
        match = re.search(r"([0-9]+\.[0-9]+)", line)
        if match:
            versions.append(match.group(1))
if not versions:
    raise SystemExit("could not determine latest Ubuntu LTS version")
print(versions[-1])
PY
}

latest_node_lts_version() {
  require_python3
  python3 - <<'PY'
import json, urllib.request
url = "https://nodejs.org/dist/index.json"
with urllib.request.urlopen(url, timeout=20) as response:
    releases = json.load(response)
lts_versions = []
for release in releases:
    lts = release.get("lts")
    version = release.get("version", "")
    if not lts or not version.startswith("v"):
        continue
    major = version[1:].split(".", 1)[0]
    if major.isdigit():
        lts_versions.append(int(major))
if not lts_versions:
    raise SystemExit("could not determine latest Node LTS version")
print(str(max(lts_versions)))
PY
}
