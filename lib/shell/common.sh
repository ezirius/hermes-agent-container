#!/usr/bin/env bash

if [[ -z "${ROOT:-}" ]]; then
  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fi

__env_HERMES_IMAGE_NAME="${HERMES_IMAGE_NAME-}"
__env_HERMES_PROJECT_PREFIX="${HERMES_PROJECT_PREFIX-}"
__env_HERMES_LABEL_NAMESPACE="${HERMES_LABEL_NAMESPACE-}"
__env_HERMES_LABEL_WORKSPACE="${HERMES_LABEL_WORKSPACE-}"
__env_HERMES_LABEL_LANE="${HERMES_LABEL_LANE-}"
__env_HERMES_LABEL_UPSTREAM="${HERMES_LABEL_UPSTREAM-}"
__env_HERMES_LABEL_WRAPPER="${HERMES_LABEL_WRAPPER-}"
__env_HERMES_LABEL_COMMITSTAMP="${HERMES_LABEL_COMMITSTAMP-}"
__env_HERMES_REPO_URL="${HERMES_REPO_URL-}"
__env_HERMES_GITHUB_API_BASE="${HERMES_GITHUB_API_BASE-}"
__env_HERMES_UBUNTU_LTS_VERSION="${HERMES_UBUNTU_LTS_VERSION-}"
__env_HERMES_NODE_LTS_VERSION="${HERMES_NODE_LTS_VERSION-}"
__env_HERMES_LANE_PRODUCTION="${HERMES_LANE_PRODUCTION-}"
__env_HERMES_LANE_TEST="${HERMES_LANE_TEST-}"
__env_HERMES_DEFAULT_UPSTREAM_SELECTOR="${HERMES_DEFAULT_UPSTREAM_SELECTOR-}"
__env_HERMES_UPSTREAM_MAIN_SELECTOR="${HERMES_UPSTREAM_MAIN_SELECTOR-}"
__env_HERMES_RELEASE_TAG_PREFIX="${HERMES_RELEASE_TAG_PREFIX-}"
__env_HERMES_BASE_ROOT="${HERMES_BASE_ROOT-}"
__env_HERMES_WORKSPACE_HOME_DIRNAME="${HERMES_WORKSPACE_HOME_DIRNAME-}"
__env_HERMES_WORKSPACE_DIRNAME="${HERMES_WORKSPACE_DIRNAME-}"
__env_HERMES_CONTAINER_RUNTIME_HOME="${HERMES_CONTAINER_RUNTIME_HOME-}"
__env_HERMES_CONTAINER_WORKSPACE_DIR="${HERMES_CONTAINER_WORKSPACE_DIR-}"
__env_HERMES_CONTAINER_RESTART_POLICY="${HERMES_CONTAINER_RESTART_POLICY-}"
__env_HERMES_PODMAN_TTY_WRAPPER="${HERMES_PODMAN_TTY_WRAPPER-}"

if [[ -n "${ROOT:-}" && -f "$ROOT/config/shared/hermes.conf" ]]; then
  # shellcheck disable=SC1090
  source "$ROOT/config/shared/hermes.conf"
fi

if [[ -n "${ROOT:-}" && -f "$ROOT/config/shared/tool-versions.conf" ]]; then
  # shellcheck disable=SC1090
  source "$ROOT/config/shared/tool-versions.conf"
fi

[[ -z "${__env_HERMES_IMAGE_NAME}" ]] || HERMES_IMAGE_NAME="$__env_HERMES_IMAGE_NAME"
[[ -z "${__env_HERMES_PROJECT_PREFIX}" ]] || HERMES_PROJECT_PREFIX="$__env_HERMES_PROJECT_PREFIX"
[[ -z "${__env_HERMES_LABEL_NAMESPACE}" ]] || HERMES_LABEL_NAMESPACE="$__env_HERMES_LABEL_NAMESPACE"
[[ -z "${__env_HERMES_LABEL_WORKSPACE}" ]] || HERMES_LABEL_WORKSPACE="$__env_HERMES_LABEL_WORKSPACE"
[[ -z "${__env_HERMES_LABEL_LANE}" ]] || HERMES_LABEL_LANE="$__env_HERMES_LABEL_LANE"
[[ -z "${__env_HERMES_LABEL_UPSTREAM}" ]] || HERMES_LABEL_UPSTREAM="$__env_HERMES_LABEL_UPSTREAM"
[[ -z "${__env_HERMES_LABEL_WRAPPER}" ]] || HERMES_LABEL_WRAPPER="$__env_HERMES_LABEL_WRAPPER"
[[ -z "${__env_HERMES_LABEL_COMMITSTAMP}" ]] || HERMES_LABEL_COMMITSTAMP="$__env_HERMES_LABEL_COMMITSTAMP"
[[ -z "${__env_HERMES_REPO_URL}" ]] || HERMES_REPO_URL="$__env_HERMES_REPO_URL"
[[ -z "${__env_HERMES_GITHUB_API_BASE}" ]] || HERMES_GITHUB_API_BASE="$__env_HERMES_GITHUB_API_BASE"
[[ -z "${__env_HERMES_UBUNTU_LTS_VERSION}" ]] || HERMES_UBUNTU_LTS_VERSION="$__env_HERMES_UBUNTU_LTS_VERSION"
[[ -z "${__env_HERMES_NODE_LTS_VERSION}" ]] || HERMES_NODE_LTS_VERSION="$__env_HERMES_NODE_LTS_VERSION"
[[ -z "${__env_HERMES_LANE_PRODUCTION}" ]] || HERMES_LANE_PRODUCTION="$__env_HERMES_LANE_PRODUCTION"
[[ -z "${__env_HERMES_LANE_TEST}" ]] || HERMES_LANE_TEST="$__env_HERMES_LANE_TEST"
[[ -z "${__env_HERMES_DEFAULT_UPSTREAM_SELECTOR}" ]] || HERMES_DEFAULT_UPSTREAM_SELECTOR="$__env_HERMES_DEFAULT_UPSTREAM_SELECTOR"
[[ -z "${__env_HERMES_UPSTREAM_MAIN_SELECTOR}" ]] || HERMES_UPSTREAM_MAIN_SELECTOR="$__env_HERMES_UPSTREAM_MAIN_SELECTOR"
[[ -z "${__env_HERMES_RELEASE_TAG_PREFIX}" ]] || HERMES_RELEASE_TAG_PREFIX="$__env_HERMES_RELEASE_TAG_PREFIX"
[[ -z "${__env_HERMES_BASE_ROOT}" ]] || HERMES_BASE_ROOT="$__env_HERMES_BASE_ROOT"
[[ -z "${__env_HERMES_WORKSPACE_HOME_DIRNAME}" ]] || HERMES_WORKSPACE_HOME_DIRNAME="$__env_HERMES_WORKSPACE_HOME_DIRNAME"
[[ -z "${__env_HERMES_WORKSPACE_DIRNAME}" ]] || HERMES_WORKSPACE_DIRNAME="$__env_HERMES_WORKSPACE_DIRNAME"
[[ -z "${__env_HERMES_CONTAINER_RUNTIME_HOME}" ]] || HERMES_CONTAINER_RUNTIME_HOME="$__env_HERMES_CONTAINER_RUNTIME_HOME"
[[ -z "${__env_HERMES_CONTAINER_WORKSPACE_DIR}" ]] || HERMES_CONTAINER_WORKSPACE_DIR="$__env_HERMES_CONTAINER_WORKSPACE_DIR"
[[ -z "${__env_HERMES_CONTAINER_RESTART_POLICY}" ]] || HERMES_CONTAINER_RESTART_POLICY="$__env_HERMES_CONTAINER_RESTART_POLICY"
[[ -z "${__env_HERMES_PODMAN_TTY_WRAPPER}" ]] || HERMES_PODMAN_TTY_WRAPPER="$__env_HERMES_PODMAN_TTY_WRAPPER"
unset __env_HERMES_IMAGE_NAME __env_HERMES_PROJECT_PREFIX __env_HERMES_LABEL_NAMESPACE __env_HERMES_LABEL_WORKSPACE __env_HERMES_LABEL_LANE __env_HERMES_LABEL_UPSTREAM __env_HERMES_LABEL_WRAPPER __env_HERMES_LABEL_COMMITSTAMP __env_HERMES_REPO_URL __env_HERMES_GITHUB_API_BASE __env_HERMES_UBUNTU_LTS_VERSION __env_HERMES_NODE_LTS_VERSION __env_HERMES_LANE_PRODUCTION __env_HERMES_LANE_TEST __env_HERMES_DEFAULT_UPSTREAM_SELECTOR __env_HERMES_UPSTREAM_MAIN_SELECTOR __env_HERMES_RELEASE_TAG_PREFIX __env_HERMES_BASE_ROOT __env_HERMES_WORKSPACE_HOME_DIRNAME __env_HERMES_WORKSPACE_DIRNAME __env_HERMES_CONTAINER_RUNTIME_HOME __env_HERMES_CONTAINER_WORKSPACE_DIR __env_HERMES_CONTAINER_RESTART_POLICY __env_HERMES_PODMAN_TTY_WRAPPER

fail() {
  echo "Error: $*" >&2
  exit 1
}

contains_line() {
  local haystack="$1"
  local needle="$2"
  local nl=$'\n'
  case "${nl}${haystack}${nl}" in
    *"${nl}${needle}${nl}"*) return 0 ;;
    *) return 1 ;;
  esac
}

usage_error() {
  echo "Usage: $1" >&2
  exit 1
}

show_help() {
  printf '%s\n' "$1"
  exit 0
}

[[ -n "${HERMES_IMAGE_NAME:-}" ]] || fail "missing HERMES_IMAGE_NAME in config/shared/hermes.conf"
[[ -n "${HERMES_PROJECT_PREFIX:-}" ]] || fail "missing HERMES_PROJECT_PREFIX in config/shared/hermes.conf"
[[ -n "${HERMES_LABEL_NAMESPACE:-}" ]] || fail "missing HERMES_LABEL_NAMESPACE in config/shared/hermes.conf"
[[ -n "${HERMES_LABEL_WORKSPACE:-}" ]] || fail "missing HERMES_LABEL_WORKSPACE in config/shared/hermes.conf"
[[ -n "${HERMES_LABEL_LANE:-}" ]] || fail "missing HERMES_LABEL_LANE in config/shared/hermes.conf"
[[ -n "${HERMES_LABEL_UPSTREAM:-}" ]] || fail "missing HERMES_LABEL_UPSTREAM in config/shared/hermes.conf"
[[ -n "${HERMES_LABEL_WRAPPER:-}" ]] || fail "missing HERMES_LABEL_WRAPPER in config/shared/hermes.conf"
[[ -n "${HERMES_LABEL_COMMITSTAMP:-}" ]] || fail "missing HERMES_LABEL_COMMITSTAMP in config/shared/hermes.conf"
[[ -n "${HERMES_REPO_URL:-}" ]] || fail "missing HERMES_REPO_URL in config/shared/hermes.conf"
[[ -n "${HERMES_GITHUB_API_BASE:-}" ]] || fail "missing HERMES_GITHUB_API_BASE in config/shared/hermes.conf"
[[ -n "${HERMES_UBUNTU_LTS_VERSION:-}" ]] || fail "missing HERMES_UBUNTU_LTS_VERSION in config/shared/tool-versions.conf"
[[ -n "${HERMES_NODE_LTS_VERSION:-}" ]] || fail "missing HERMES_NODE_LTS_VERSION in config/shared/tool-versions.conf"
[[ -n "${HERMES_LANE_PRODUCTION:-}" ]] || fail "missing HERMES_LANE_PRODUCTION in config/shared/hermes.conf"
[[ -n "${HERMES_LANE_TEST:-}" ]] || fail "missing HERMES_LANE_TEST in config/shared/hermes.conf"
[[ -n "${HERMES_DEFAULT_UPSTREAM_SELECTOR:-}" ]] || fail "missing HERMES_DEFAULT_UPSTREAM_SELECTOR in config/shared/hermes.conf"
[[ -n "${HERMES_UPSTREAM_MAIN_SELECTOR:-}" ]] || fail "missing HERMES_UPSTREAM_MAIN_SELECTOR in config/shared/hermes.conf"
[[ -n "${HERMES_RELEASE_TAG_PREFIX:-}" ]] || fail "missing HERMES_RELEASE_TAG_PREFIX in config/shared/hermes.conf"
[[ -n "${HERMES_BASE_ROOT:-}" ]] || fail "missing HERMES_BASE_ROOT in config/shared/hermes.conf"
[[ -n "${HERMES_WORKSPACE_HOME_DIRNAME:-}" ]] || fail "missing HERMES_WORKSPACE_HOME_DIRNAME in config/shared/hermes.conf"
[[ -n "${HERMES_WORKSPACE_DIRNAME:-}" ]] || fail "missing HERMES_WORKSPACE_DIRNAME in config/shared/hermes.conf"
[[ -n "${HERMES_CONTAINER_RUNTIME_HOME:-}" ]] || fail "missing HERMES_CONTAINER_RUNTIME_HOME in config/shared/hermes.conf"
[[ -n "${HERMES_CONTAINER_WORKSPACE_DIR:-}" ]] || fail "missing HERMES_CONTAINER_WORKSPACE_DIR in config/shared/hermes.conf"
[[ -n "${HERMES_CONTAINER_RESTART_POLICY:-}" ]] || fail "missing HERMES_CONTAINER_RESTART_POLICY in config/shared/hermes.conf"
case "${HERMES_PODMAN_TTY_WRAPPER:-}" in
  auto|none|script) ;;
  *) fail "unsupported HERMES_PODMAN_TTY_WRAPPER value in config/shared/hermes.conf: ${HERMES_PODMAN_TTY_WRAPPER:-}" ;;
esac

HERMES_REF="${HERMES_REF:-$HERMES_DEFAULT_UPSTREAM_SELECTOR}"

update_config_assignment() {
  local config_path="$1"
  local key="$2"
  local value="$3"

  require_python3
  python3 - "$config_path" "$key" "$value" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
key = sys.argv[2]
value = sys.argv[3]
text = path.read_text(encoding='utf-8')
old = None
for line in text.splitlines():
    if line.startswith(f'{key}='):
        old = line
        break
if old is None:
    raise SystemExit(f'missing {key} in {path}')
path.write_text(text.replace(old, f'{key}="{value}"', 1), encoding='utf-8')
PY
}

tool_versions_config_path() {
  [[ -n "${ROOT:-}" ]] || fail "ROOT must be set before calling tool_versions_config_path"
  printf '%s' "$ROOT/config/shared/tool-versions.conf"
}

hermes_upstream_ref_label_key() {
  printf '%s.upstream_ref' "$HERMES_LABEL_NAMESPACE"
}

hermes_build_fingerprint_label_key() {
  printf '%s.build_fingerprint' "$HERMES_LABEL_NAMESPACE"
}

container_restart_policy() {
  printf '%s' "$HERMES_CONTAINER_RESTART_POLICY"
}

require_podman() {
  command -v podman >/dev/null 2>&1 || fail "podman is required"
}

require_python3() {
  command -v python3 >/dev/null 2>&1 || fail "python3 is required"
}

lane_usage_text() {
  printf '<%s|%s>' "$HERMES_LANE_PRODUCTION" "$HERMES_LANE_TEST"
}

is_lane() {
  local lane="$1"
  [[ "$lane" == "$HERMES_LANE_PRODUCTION" || "$lane" == "$HERMES_LANE_TEST" ]]
}

validate_lane() {
  local lane="$1"
  is_lane "$lane" || fail "lane must be one of $(lane_usage_text)"
}

upstream_selector_usage_text() {
  printf "'%s', '%s', or an exact stable release tag" "$HERMES_UPSTREAM_MAIN_SELECTOR" "$HERMES_DEFAULT_UPSTREAM_SELECTOR"
}

validate_upstream_selector() {
  local selector="$1"
  [[ -n "$selector" ]] || fail "upstream selector must not be empty"
  [[ "$selector" == "$HERMES_UPSTREAM_MAIN_SELECTOR" || "$selector" == "$HERMES_DEFAULT_UPSTREAM_SELECTOR" || "$selector" =~ ^${HERMES_RELEASE_TAG_PREFIX}?[0-9]+\.[0-9]+\.[0-9]+$ ]] || fail "upstream selector must be $(upstream_selector_usage_text)"
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
  local normalized
  normalized="$(normalize_image_ref "$image_ref")"

  value="$(podman image inspect -f "{{ index .Labels \"$key\" }}" "$image_ref" 2>/dev/null || true)"
  if [[ -z "$value" || "$value" == "<no value>" ]]; then
    value="$(podman image inspect -f "{{ index .Labels \"$key\" }}" "$normalized" 2>/dev/null || true)"
  fi
  if [[ -z "$value" || "$value" == "<no value>" ]]; then
    value="$(podman image inspect -f "{{ index .Labels \"$key\" }}" "localhost/$normalized" 2>/dev/null || true)"
  fi
  if [[ "$value" == "<no value>" ]]; then
    value=""
  fi
  printf '%s' "$value"
}

normalize_image_ref() {
  local ref="$1"
  ref="${ref%%@*}"
  case "$ref" in
    localhost/*)
      printf '%s' "${ref#localhost/}"
      ;;
    *)
      printf '%s' "$ref"
      ;;
  esac
}

local_build_fingerprint() {
  [[ -n "${ROOT:-}" ]] || fail "ROOT must be set before calling local_build_fingerprint"
  require_python3

  python3 - "$ROOT" <<'PY'
import hashlib
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
tracked_dirs = [root / "config/shared", root / "config/containers", root / "config/patches"]
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

wrapper_build_commitstamp() {
  local workdir="${1:-$(current_wrapper_workdir)}"
  local fingerprint="${2:-$(local_build_fingerprint)}"
  local head_stamp

  if [[ -n "${HERMES_COMMITSTAMP_OVERRIDE:-}" ]]; then
    printf '%s' "$HERMES_COMMITSTAMP_OVERRIDE"
    return 0
  fi

  if ! git_has_meaningful_worktree_changes git -C "$workdir"; then
    git_commit_stamp "$workdir"
    return 0
  fi

  head_stamp="$(git -C "$workdir" show -s --format=%cd --date=format:%Y%m%d-%H%M%S HEAD 2>/dev/null || true)"
  [[ -n "$head_stamp" ]] || fail "could not derive wrapper build timestamp from $workdir"
  printf '%s-dirty%s' "$head_stamp" "${fingerprint:0:8}"
}

current_image_build_fingerprint() {
  local image_ref="${1:-$HERMES_IMAGE}"
  image_label "$(hermes_build_fingerprint_label_key)" "$image_ref"
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

workspace_base_root() {
  normalize_absolute_path "$(normalize_path "$HERMES_BASE_ROOT")"
}

workspace_names_from_base_root() {
  local base_root candidate workspace_name
  local -a workspace_names=()

  base_root="$(workspace_base_root)"
  [[ -d "$base_root" ]] || return 0

  shopt -s nullglob
  for candidate in "$base_root"/*; do
    [[ -d "$candidate" ]] || continue
    workspace_name="${candidate##*/}"
    if [[ "$workspace_name" =~ ^[A-Za-z0-9._-]+$ ]]; then
      workspace_names+=("$workspace_name")
    fi
  done
  shopt -u nullglob

  [[ ${#workspace_names[@]} -gt 0 ]] || return 0
  printf '%s\n' "${workspace_names[@]}" | sort
}

select_workspace_name() {
  local workspace_names workspace_name
  local -a options=()

  workspace_names="$(workspace_names_from_base_root)"
  [[ -n "$workspace_names" ]] || fail "no workspaces found under $(workspace_base_root)"

  while IFS= read -r workspace_name; do
    [[ -n "$workspace_name" ]] || continue
    options+=("$workspace_name")
  done <<<"$workspace_names"

  printf '%s' "$(prompt_select_option "Select a workspace from $(workspace_base_root)" "${options[@]}")"
}

resolve_workspace_argument() {
  local workspace_name="${1-}"
  if [[ -n "$workspace_name" && "$workspace_name" != "--" ]]; then
    require_workspace_name "$workspace_name"
    printf '%s' "$workspace_name"
    return 0
  fi

  select_workspace_name
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

  if [[ "$parent_base" == "worktrees" || "$parent_base" == ".worktrees" ]]; then
    candidate="$(dirname "$parent_dir")"
    if git -C "$candidate" rev-parse --show-toplevel >/dev/null 2>&1; then
      normalize_absolute_path "$candidate"
      return 0
    fi

    candidate="${candidate%-wrapper}"
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
  local branch_name

  if [[ -n "${HERMES_WRAPPER_CONTEXT_OVERRIDE:-}" ]]; then
    printf '%s' "$HERMES_WRAPPER_CONTEXT_OVERRIDE"
    return 0
  fi

  if git_is_primary_worktree "$workdir"; then
    branch_name="$(git_branch_name "$workdir" 2>/dev/null || true)"
    if [[ -n "$branch_name" ]]; then
      printf '%s' "$branch_name"
      return 0
    fi
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
  HERMES_HOME_DIR="$WORKSPACE_ROOT/$HERMES_WORKSPACE_HOME_DIRNAME"
  HERMES_ENV_FILE="$HERMES_HOME_DIR/.env"
  HERMES_CONFIG_FILE="$HERMES_HOME_DIR/config.yaml"
  HERMES_WORKSPACE_DIR="$WORKSPACE_ROOT/$HERMES_WORKSPACE_DIRNAME"
}

resolve_build_target() {
  local workspace="${1:?workspace required}"
  local lane="${2:?lane required}"
  local ref="${3:?ref required}"
  local wrapper_context="${4:-}"
  local commitstamp="${5:-}"

  validate_lane "$lane"

  validate_upstream_selector "$ref"

  local version_tag
  version_tag="$(resolve_hermes_ref "$ref")"
  [[ -n "$wrapper_context" ]] || wrapper_context="$(current_wrapper_context)"
  [[ -n "$commitstamp" ]] || commitstamp="$(git_commit_stamp)"

  local workspace_base_root
  workspace_base_root="$(normalize_path "$HERMES_BASE_ROOT")"
  WORKSPACE_NAME="$workspace"
  WORKSPACE_INPUT="$workspace"
  WORKSPACE_ROOT="$(normalize_absolute_path "$workspace_base_root/$workspace")"
  HERMES_HOME_DIR="$WORKSPACE_ROOT/$HERMES_WORKSPACE_HOME_DIRNAME"
  HERMES_ENV_FILE="$HERMES_HOME_DIR/.env"
  HERMES_CONFIG_FILE="$HERMES_HOME_DIR/config.yaml"
  HERMES_WORKSPACE_DIR="$WORKSPACE_ROOT/$HERMES_WORKSPACE_DIRNAME"

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
    "$HERMES_WORKSPACE_DIR"
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

  if [[ -d "$WORKSPACE_ROOT/workspace" ]]; then
    move_path_contents "$WORKSPACE_ROOT/workspace" "$HERMES_WORKSPACE_DIR"
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

  validate_upstream_selector "$requested_ref"

  if [[ "$requested_ref" == "$HERMES_UPSTREAM_MAIN_SELECTOR" ]]; then
    printf '%s\t%s\n' "$HERMES_UPSTREAM_MAIN_SELECTOR" "$HERMES_UPSTREAM_MAIN_SELECTOR"
    return 0
  fi

  cached="$(release_option_cache)"
  if [[ "$requested_ref" == "$HERMES_DEFAULT_UPSTREAM_SELECTOR" ]]; then
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

  case "$requested_ref" in
    ${HERMES_RELEASE_TAG_PREFIX}[0-9]*.[0-9]*.[0-9]*)
      printf '%s\t%s\n' "${requested_ref#${HERMES_RELEASE_TAG_PREFIX}}" "$requested_ref"
      return 0
      ;;
    [0-9]*.[0-9]*.[0-9]*)
      printf '%s\t%s%s\n' "$requested_ref" "$HERMES_RELEASE_TAG_PREFIX" "$requested_ref"
      return 0
      ;;
  esac

  fail "failed to resolve upstream selector: $requested_ref"
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
  IFS=$' \t' read -r behind ahead <<< "$counts"
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
  HERMES_REPO_SLUG="$repo_slug" HERMES_GITHUB_API_BASE="$HERMES_GITHUB_API_BASE" HERMES_RELEASE_TAG_PREFIX="$HERMES_RELEASE_TAG_PREFIX" python3 - <<'PY'
import json, os, re, urllib.error, urllib.request
base = os.environ.get("HERMES_GITHUB_API_BASE", "https://api.github.com").rstrip("/")
repo_slug = os.environ["HERMES_REPO_SLUG"].strip("/")
prefix = os.environ.get("HERMES_RELEASE_TAG_PREFIX", "v")
url = f"{base}/repos/{repo_slug}/releases?per_page=100"
headers = {"Accept": "application/vnd.github+json", "User-Agent": "hermes-agent-container/1.0"}
req = urllib.request.Request(url, headers=headers)
try:
    with urllib.request.urlopen(req, timeout=20) as response:
        releases = json.load(response)
except urllib.error.HTTPError as exc:
    raise SystemExit(f"failed to list upstream Hermes releases: HTTP {exc.code}")
except urllib.error.URLError as exc:
    raise SystemExit(f"failed to list upstream Hermes releases: {exc.reason}")
except Exception as exc:
    raise SystemExit(f"failed to list upstream Hermes releases: {exc}")
stable_releases = []
for release in releases:
    if release.get("draft") or release.get("prerelease"):
        continue
    tag = (release.get("tag_name") or "").strip()
    if not tag:
        continue
    display = tag[len(prefix):] if prefix and tag.startswith(prefix) else tag
    if not re.fullmatch(r"\d+\.\d+\.\d+", display):
        continue
    stable_releases.append((tuple(int(part) for part in display.split('.')), tag))
for _, tag in sorted(stable_releases, reverse=True):
    print(tag)
PY
}

list_upstream_release_options() {
  local repo_slug
  require_python3
  repo_slug="$(github_repo_slug "$HERMES_REPO_URL")"
  HERMES_REPO_SLUG="$repo_slug" HERMES_GITHUB_API_BASE="$HERMES_GITHUB_API_BASE" HERMES_RELEASE_TAG_PREFIX="$HERMES_RELEASE_TAG_PREFIX" python3 - <<'PY'
import json, os, re, urllib.error, urllib.request
base = os.environ.get("HERMES_GITHUB_API_BASE", "https://api.github.com").rstrip("/")
repo_slug = os.environ["HERMES_REPO_SLUG"].strip("/")
prefix = os.environ.get("HERMES_RELEASE_TAG_PREFIX", "v")
url = f"{base}/repos/{repo_slug}/releases?per_page=100"
headers = {"Accept": "application/vnd.github+json", "User-Agent": "hermes-agent-container/1.0"}
req = urllib.request.Request(url, headers=headers)
try:
    with urllib.request.urlopen(req, timeout=20) as response:
        releases = json.load(response)
except urllib.error.HTTPError as exc:
    raise SystemExit(f"failed to list upstream Hermes releases: HTTP {exc.code}")
except urllib.error.URLError as exc:
    raise SystemExit(f"failed to list upstream Hermes releases: {exc.reason}")
except Exception as exc:
    raise SystemExit(f"failed to list upstream Hermes releases: {exc}")

stable_releases = []
for release in releases:
    if release.get("draft") or release.get("prerelease"):
        continue
    tag = (release.get("tag_name") or "").strip()
    if not tag:
        continue
    if prefix and tag.startswith(prefix):
        display = tag[len(prefix):]
    else:
        display = tag
    if not re.fullmatch(r"\d+\.\d+\.\d+", display):
        continue
    name = (release.get("name") or "").strip()
    match = re.search(r"v?(\d+\.\d+\.\d+)", name)
    if match:
        display = match.group(1)
    stable_releases.append((tuple(int(part) for part in display.split('.')), display, tag))
for _, display, tag in sorted(stable_releases, reverse=True):
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
  local seen_refs=""
  local normalized
  podman images --format '{{.Repository}}:{{.Tag}}' 2>/dev/null | while IFS= read -r ref; do
    [[ "$ref" == "$HERMES_IMAGE_NAME:"* || "$ref" == "localhost/$HERMES_IMAGE_NAME:"* ]] || continue
    normalized="$(normalize_image_ref "$ref")"
    contains_line "$seen_refs" "$normalized" && continue
    if [[ -z "$seen_refs" ]]; then
      seen_refs="$normalized"
    else
      seen_refs+=$'\n'"$normalized"
    fi
    printf '%s\n' "$normalized"
  done
}

project_container_names() {
  local name
  podman ps -a --format '{{.Names}}' 2>/dev/null | while IFS= read -r name; do
    [[ "$name" == "$HERMES_PROJECT_PREFIX-"* ]] || continue
    printf '%s\n' "$name"
  done
}

image_metadata() {
  local image_ref="$1"
  local lane upstream wrapper commitstamp
  local normalized tag

  normalized="$(normalize_image_ref "$image_ref")"
  tag="${normalized#*:}"
  if [[ "$tag" =~ ^(${HERMES_LANE_PRODUCTION}|${HERMES_LANE_TEST})-(${HERMES_UPSTREAM_MAIN_SELECTOR}|[0-9]+\.[0-9]+\.[0-9]+)-(.+)-([0-9]{8}-[0-9]{6}-[A-Za-z0-9]+)$ ]]; then
    lane="${BASH_REMATCH[1]}"
    upstream="${BASH_REMATCH[2]}"
    wrapper="${BASH_REMATCH[3]}"
    commitstamp="${BASH_REMATCH[4]}"
  else
    lane="$(image_label "$HERMES_LABEL_LANE" "$image_ref")"
    upstream="$(image_label "$HERMES_LABEL_UPSTREAM" "$image_ref")"
    wrapper="$(image_label "$HERMES_LABEL_WRAPPER" "$image_ref")"
    commitstamp="$(image_label "$HERMES_LABEL_COMMITSTAMP" "$image_ref")"
  fi

  if ! is_lane "$lane"; then
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

  raw="$(podman inspect -f "{{index .Config.Labels \"$HERMES_LABEL_LANE\"}}|{{index .Config.Labels \"$HERMES_LABEL_UPSTREAM\"}}|{{index .Config.Labels \"$HERMES_LABEL_WRAPPER\"}}|{{index .Config.Labels \"$HERMES_LABEL_COMMITSTAMP\"}}|{{.State.Running}}" "$container_name" 2>/dev/null || true)"
  lane="${raw%%|*}"
  raw="${raw#*|}"
  upstream="${raw%%|*}"
  raw="${raw#*|}"
  wrapper="${raw%%|*}"
  raw="${raw#*|}"
  commitstamp="${raw%%|*}"
  status="${raw##*|}"

  if [[ -z "$lane" || -z "$upstream" || -z "$wrapper" ]]; then
    parsed="$(python3 - "$HERMES_PROJECT_PREFIX" "$HERMES_LANE_PRODUCTION" "$HERMES_LANE_TEST" "$container_name" <<'PY'
import sys
prefix = sys.argv[1]
lanes = sys.argv[2:4]
name = sys.argv[4]
base = f"{prefix}-"
if not name.startswith(base):
    raise SystemExit(1)
rest = name[len(base):]
for lane in lanes:
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
  if ! is_lane "$lane"; then
    return 1
  fi
  [[ -n "$upstream" ]] || return 1
  [[ -n "$wrapper" ]] || return 1
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$container_name" "$lane" "$upstream" "$wrapper" "$commitstamp" "$status"
}

container_workspace() {
  local container_name="$1"
  local workspace

  workspace="$(podman inspect -f "{{index .Config.Labels \"$HERMES_LABEL_WORKSPACE\"}}" "$container_name" 2>/dev/null || true)"
  if [[ -n "$workspace" ]]; then
    printf '%s' "$workspace"
    return 0
  fi

  python3 - "$HERMES_PROJECT_PREFIX" "$HERMES_LANE_PRODUCTION" "$HERMES_LANE_TEST" "$container_name" <<'PY'
import sys
prefix = sys.argv[1]
lanes = sys.argv[2:4]
name = sys.argv[4]
base = f"{prefix}-"
if not name.startswith(base):
    raise SystemExit(1)
rest = name[len(base):]
for lane in lanes:
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
    if [[ "$(image_id "$ref" 2>/dev/null || true)" == "$target_id" || "$(image_id "localhost/$ref" 2>/dev/null || true)" == "$target_id" ]]; then
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
  HERMES_LANE_PRODUCTION="$HERMES_LANE_PRODUCTION" python3 -c 'import os, sys; prod=os.environ["HERMES_LANE_PRODUCTION"]; rows=[line.rstrip("\n").split("\t") for line in sys.stdin if line.strip()]; lane_index=lambda row: 2 if len(row) >= 7 else 1; commit_index=lambda row: 5 if len(row) >= 7 else 4; rows=sorted(rows, key=lambda row: (0 if row[lane_index(row)] == prod else 1, "".join(chr(255 - ord(c)) for c in (row[commit_index(row)] if len(row) > commit_index(row) else "")))); [print("\t".join(row)) for row in rows]'
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

workspace_target_rows() {
  local workspace="$1"
  local seen_image_refs=""
  local row metadata image_ref lane upstream wrapper commitstamp

  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    IFS=$'\t' read -r value lane upstream wrapper commitstamp status <<< "$row"
    image_ref="$(container_image_id "$value" 2>/dev/null || true)"
    image_ref="$(image_ref_for_id "$image_ref" 2>/dev/null || true)"
    [[ -n "$image_ref" ]] && seen_image_refs+="$(normalize_image_ref "$image_ref")"$'\n'
    printf 'container\t%s\t%s\t%s\t%s\t%s\t%s\n' "$value" "$lane" "$upstream" "$wrapper" "$commitstamp" "$status"
  done < <(workspace_container_targets "$workspace")

  while IFS= read -r image_ref; do
    [[ -n "$image_ref" ]] || continue
    metadata="$(image_metadata "$image_ref" 2>/dev/null || true)"
    [[ -n "$metadata" ]] || continue
    IFS=$'\t' read -r _ lane upstream wrapper commitstamp <<< "$metadata"
    contains_line "$seen_image_refs" "$(normalize_image_ref "$image_ref")" && continue
    printf 'image\t%s\t%s\t%s\t%s\t%s\timage only\n' "$image_ref" "$lane" "$upstream" "$wrapper" "$commitstamp"
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
  local row display kind value

  if [[ "$mode" == "target" ]]; then
    while IFS= read -r row; do
      [[ -n "$row" ]] || continue
      rows+=("$row")
    done < <(workspace_target_rows "$workspace" | sort_targets)
  else
    while IFS= read -r row; do
      [[ -n "$row" ]] || continue
      rows+=($'container\t'"$row")
    done < <(workspace_container_targets "$workspace" | sort_targets)
  fi

  [[ ${#rows[@]} -gt 0 ]] || fail "no matching project ${mode}s exist for workspace: $workspace"

  local options=()
  local display_rows=()
  local prompt
  for row in "${rows[@]}"; do
    IFS=$'\t' read -r kind value lane upstream wrapper commitstamp status <<< "$row"
    display_rows+=("$lane"$'\t'"$upstream"$'\t'"$wrapper"$'\t'"$commitstamp"$'\t'"$status")
  done
  while IFS= read -r row; do options+=("$row"); done < <(format_target_table "${display_rows[@]}")
  prompt="Select ${mode} for workspace '$workspace'"
  prompt+=$'\n'"${options[0]}"$'\n'"${options[1]}"
  display="$(prompt_select_option "$prompt" "${options[@]:2}")"
  for i in "${!rows[@]}"; do
    if [[ "${options[i+2]}" == "$display" ]]; then
      printf '%s' "${rows[i]}"
      return 0
    fi
  done
  fail "failed to resolve selected ${mode}"
}

latest_matching_image_target() {
  local lane="$1"
  local upstream="$2"
  local wrapper="$3"
  local row

  while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    IFS=$'\t' read -r image_ref row_lane row_upstream row_wrapper commitstamp <<< "$row"
    if [[ "$row_lane" == "$lane" && "$row_upstream" == "$upstream" && "$row_wrapper" == "$wrapper" ]]; then
      printf '%s\n' "$row"
      return 0
    fi
  done < <(workspace_image_targets placeholder | sort_targets)

  return 1
}

resolve_start_target() {
  local workspace="$1"
  local lane="$2"
  local upstream="$3"
  local wrapper_context="${4:-}"
  local commitstamp="${5:-}"
  local resolved_upstream
  local matching_row
  local existing_container_name
  local existing_metadata

  [[ -n "$wrapper_context" ]] || wrapper_context="$(current_wrapper_context)"
  resolved_upstream="$(resolve_hermes_ref "$upstream")"

  if [[ -z "$commitstamp" ]]; then
    matching_row="$(latest_matching_image_target "$lane" "$resolved_upstream" "$wrapper_context" 2>/dev/null || true)"
    if [[ -n "$matching_row" ]]; then
      IFS=$'\t' read -r _ _ _ _ commitstamp _ <<< "$matching_row"
    else
      existing_container_name="$HERMES_PROJECT_PREFIX-$workspace-$lane-$resolved_upstream-$wrapper_context"
      if container_exists "$existing_container_name"; then
        existing_metadata="$(container_metadata "$existing_container_name" 2>/dev/null || true)"
      else
        existing_metadata=""
      fi
      [[ -n "$existing_metadata" ]] || fail "no matching project image exists for ${lane}/${resolved_upstream}/${wrapper_context}; run hermes-build first"
      IFS=$'\t' read -r _ _ _ _ commitstamp _ <<< "$existing_metadata"
    fi
  fi

  resolve_build_target "$workspace" "$lane" "$resolved_upstream" "$wrapper_context" "$commitstamp"
}

status_summary() {
  local container_name="$1"
  local metadata image_ref image_identity workspace
  metadata="$(container_metadata "$container_name" 2>/dev/null || true)"
  [[ -n "$metadata" ]] || fail "could not inspect container metadata: $container_name"

  local lane upstream wrapper commitstamp status
  IFS=$'\t' read -r _ lane upstream wrapper commitstamp status <<< "$metadata"
  image_identity="$(container_image_id "$container_name" 2>/dev/null || true)"
  image_ref="$(image_ref_for_id "$image_identity" 2>/dev/null || true)"
  workspace="$(container_workspace "$container_name" 2>/dev/null || true)"

  printf 'Container:   %s\n' "$container_name"
  printf 'Workspace:   %s\n' "$workspace"
  printf 'Lane:        %s\n' "$lane"
  printf 'Upstream:    %s\n' "$(display_upstream_ref "$upstream")"
  printf 'Wrapper:     %s\n' "$wrapper"
  printf 'Commit:      %s\n' "$commitstamp"
  printf 'Status:      %s\n' "$status"
  printf 'Image:       %s\n' "${image_ref:-unknown}"
}

pick_remove_target() {
  local mode="$1"
  local rows=()
  local row value lane upstream wrapper commitstamp status
  local options=()
  local display_rows=()
  local prompt
  local used_by

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

  for row in "${rows[@]}"; do
    IFS=$'\t' read -r value lane upstream wrapper commitstamp status <<< "$row"
    if [[ "$mode" == "container" ]]; then
      display_rows+=("$(container_workspace "$value")"$'\t'"$lane"$'\t'"$upstream"$'\t'"$wrapper"$'\t'"$commitstamp"$'\t'"$status")
    else
      used_by=""
      IMAGE_ID="$(image_id "$value" 2>/dev/null || true)"
      while IFS= read -r NAME; do
        [[ -n "$NAME" ]] || continue
        if [[ "$(container_image_id "$NAME" 2>/dev/null || true)" == "$IMAGE_ID" ]]; then
          WORKSPACE="$(container_workspace "$NAME")"
          contains_line "$used_by" "$WORKSPACE" || used_by+="$WORKSPACE"$'\n'
        fi
      done < <(project_container_names)
      if [[ -n "$used_by" ]]; then
        used_by="$(printf '%s' "$used_by" | sed '/^$/d' | paste -sd ',' -)"
      else
        used_by="unassigned"
      fi
      display_rows+=("$used_by"$'\t'"$lane"$'\t'"$upstream"$'\t'"$wrapper"$'\t'"$commitstamp"$'\t'"$status")
    fi
  done

  if [[ "$mode" == "container" ]]; then
    while IFS= read -r row; do options+=("$row"); done < <(format_target_table_with_leading_column workspace "${display_rows[@]}")
  else
    while IFS= read -r row; do options+=("$row"); done < <(format_target_table_with_leading_column "used by" "${display_rows[@]}")
  fi

  local selected
  prompt="Select ${mode} removal target"
  prompt+=$'\n'"${options[0]}"$'\n'"${options[1]}"
  selected="$(prompt_select_option "$prompt" "All, but newest" "All" "${options[@]:2}")"
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

resolve_latest_pinned_version_or_current() {
  local label="$1"
  local current_value="$2"
  local resolver="$3"
  local latest_value
  local err_file

  err_file="$(mktemp)"
  if latest_value="$($resolver 2>"$err_file")"; then
    rm -f "$err_file"
    printf '%s' "$latest_value"
    return 0
  fi

printf 'Warning: could not check for a newer %s release; continuing with pinned version %s\n' "$label" "$current_value" >&2
  if [[ -s "$err_file" ]]; then
    while IFS= read -r line; do
      [[ -n "$line" ]] || continue
      printf 'Warning: %s\n' "$line" >&2
    done < "$err_file"
  fi
  rm -f "$err_file"
  printf '%s' "$current_value"
}
format_target_table() {
  local rows=("$@") row lane_w=10 upstream_w=12 wrapper_w=34 commit_w=24 status_w=10
  local lane upstream wrapper commitstamp status formatted=()
  for row in "${rows[@]}"; do
    [[ -n "$row" ]] || continue
    IFS=$'\t' read -r lane upstream wrapper commitstamp status <<< "$row"
    (( ${#lane} > lane_w )) && lane_w=${#lane}
    (( ${#upstream} > upstream_w )) && upstream_w=${#upstream}
    (( ${#wrapper} > wrapper_w )) && wrapper_w=${#wrapper}
    (( ${#commitstamp} > commit_w )) && commit_w=${#commitstamp}
    (( ${#status} > status_w )) && status_w=${#status}
  done
  printf -v row "%-${lane_w}s  %-${upstream_w}s  %-${wrapper_w}s  %-${commit_w}s  %-${status_w}s" lane upstream wrapper commit status
  formatted+=("$row")
  printf -v row "%-${lane_w}s  %-${upstream_w}s  %-${wrapper_w}s  %-${commit_w}s  %-${status_w}s" "$(printf '%*s' "$lane_w" '' | tr ' ' '-')" "$(printf '%*s' "$upstream_w" '' | tr ' ' '-')" "$(printf '%*s' "$wrapper_w" '' | tr ' ' '-')" "$(printf '%*s' "$commit_w" '' | tr ' ' '-')" "$(printf '%*s' "$status_w" '' | tr ' ' '-')"
  formatted+=("$row")
  for row in "${rows[@]}"; do
    [[ -n "$row" ]] || continue
    IFS=$'\t' read -r lane upstream wrapper commitstamp status <<< "$row"
    printf -v row "%-${lane_w}s  %-${upstream_w}s  %-${wrapper_w}s  %-${commit_w}s  %-${status_w}s" "$lane" "$upstream" "$wrapper" "$commitstamp" "$status"
    formatted+=("$row")
  done
  printf '%s\n' "${formatted[@]}"
}

format_target_table_with_leading_column() {
  local header="$1"; shift
  local rows=("$@") row lead_w=${#header} lane_w=10 upstream_w=12 wrapper_w=34 commit_w=24 status_w=10
  local lead lane upstream wrapper commitstamp status formatted=()
  for row in "${rows[@]}"; do
    [[ -n "$row" ]] || continue
    IFS=$'\t' read -r lead lane upstream wrapper commitstamp status <<< "$row"
    (( ${#lead} > lead_w )) && lead_w=${#lead}
    (( ${#lane} > lane_w )) && lane_w=${#lane}
    (( ${#upstream} > upstream_w )) && upstream_w=${#upstream}
    (( ${#wrapper} > wrapper_w )) && wrapper_w=${#wrapper}
    (( ${#commitstamp} > commit_w )) && commit_w=${#commitstamp}
    (( ${#status} > status_w )) && status_w=${#status}
  done
  printf -v row "%-${lead_w}s  %-${lane_w}s  %-${upstream_w}s  %-${wrapper_w}s  %-${commit_w}s  %-${status_w}s" "$header" lane upstream wrapper commit status
  formatted+=("$row")
  printf -v row "%-${lead_w}s  %-${lane_w}s  %-${upstream_w}s  %-${wrapper_w}s  %-${commit_w}s  %-${status_w}s" "$(printf '%*s' "$lead_w" '' | tr ' ' '-')" "$(printf '%*s' "$lane_w" '' | tr ' ' '-')" "$(printf '%*s' "$upstream_w" '' | tr ' ' '-')" "$(printf '%*s' "$wrapper_w" '' | tr ' ' '-')" "$(printf '%*s' "$commit_w" '' | tr ' ' '-')" "$(printf '%*s' "$status_w" '' | tr ' ' '-')"
  formatted+=("$row")
  for row in "${rows[@]}"; do
    [[ -n "$row" ]] || continue
    IFS=$'\t' read -r lead lane upstream wrapper commitstamp status <<< "$row"
    printf -v row "%-${lead_w}s  %-${lane_w}s  %-${upstream_w}s  %-${wrapper_w}s  %-${commit_w}s  %-${status_w}s" "$lead" "$lane" "$upstream" "$wrapper" "$commitstamp" "$status"
    formatted+=("$row")
  done
  printf '%s\n' "${formatted[@]}"
}
