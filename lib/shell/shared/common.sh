#!/usr/bin/env bash

set -euo pipefail

# This file holds the shared shell helpers used by the wrapper scripts.
# It loads the saved repo config once and gives the scripts small helper tools to reuse.

# This finds the repo root when a script did not pass it in first.
if [[ -z "${ROOT:-}" ]]; then
  ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
fi

# This loads the saved repo settings so the helpers all read the same values.
# shellcheck disable=SC1090
source "$ROOT/config/agent/shared/hermes-agent-settings-shared.conf"

declare -a HERMES_AGENT_WORKSPACE_NAMES=()
declare -a HERMES_AGENT_WORKSPACE_OFFSETS=()

# This checks that a workspace name only uses safe characters.
hermes_validate_workspace_name() {
  local name="$1"

  if [[ ! "$name" =~ ^[A-Za-z0-9._-]+$ || "$name" == '.' || "$name" == '..' ]]; then
    printf "Workspace name %s may only contain letters, numbers, dots, underscores, and hyphens, and must not be '.' or '..'.\n" "$name" >&2
    exit 1
  fi
}

# This escapes special regex symbols so names are matched safely.
hermes_regex_escape() {
  local value="$1"
  printf '%s\n' "$value" | sed 's/[][(){}.^$*+?|\\]/\\&/g'
}

# This builds the regex used to find Hermes images with the saved version.
hermes_image_name_regex() {
  local escaped_basename escaped_version

  escaped_basename="$(hermes_regex_escape "$HERMES_AGENT_IMAGE_BASENAME")"
  escaped_version="$(hermes_regex_escape "$HERMES_AGENT_VERSION")"
  printf '^%s-%s-[0-9]{8}-[0-9]{6}-[0-9a-f]{12}$\n' "$escaped_basename" "$escaped_version"
}

# This builds the regex used to find containers for one workspace across image versions.
hermes_container_filter_regex() {
  local workspace="$1"
  local escaped_basename escaped_workspace

  escaped_basename="$(hermes_regex_escape "$HERMES_AGENT_IMAGE_BASENAME")"
  escaped_workspace="$(hermes_regex_escape "$workspace")"
  printf '^%s-([0-9][0-9.]*-[0-9]{8}-[0-9]{6}-[0-9a-f]{12}-%s(-gateway|-dashboard)?|%s-(gateway|dashboard)-[0-9][0-9.]*-[0-9]{8}-[0-9]{6}-[0-9a-f]{12})$\n' "$escaped_basename" "$escaped_workspace" "$escaped_workspace"
}

# This builds the regex used to find running single-runtime containers for one workspace.
hermes_runtime_container_filter_regex() {
  local workspace="$1"
  local escaped_basename escaped_workspace

  escaped_basename="$(hermes_regex_escape "$HERMES_AGENT_IMAGE_BASENAME")"
  escaped_workspace="$(hermes_regex_escape "$workspace")"
  printf '^%s-[0-9][0-9.]*-[0-9]{8}-[0-9]{6}-[0-9a-f]{12}-%s$\n' "$escaped_basename" "$escaped_workspace"
}

# This builds the canonical Hermes container or pod name for one image and workspace.
hermes_container_name() {
  local image_name="$1"
  local workspace="$2"

  printf '%s-%s\n' "$image_name" "$workspace"
}

# This matches one exact container name and nothing else.
hermes_container_name_regex() {
  local container_name="$1"
  printf '^%s$\n' "$(hermes_regex_escape "$container_name")"
}

# This keeps the small wrapper scripts easy to use by rejecting extra args.
hermes_require_no_args() {
  if [[ $# -ne 0 ]]; then
    printf 'This script takes no arguments.\n' >&2
    exit 1
  fi
}

# This tells us whether the current stdin is a real interactive terminal.
hermes_use_interactive_tty() {
  # This override makes it possible to test the interactive path without a real terminal.
  if [[ "${HERMES_AGENT_FORCE_EXEC_TTY:-}" == "1" ]]; then
    return 0
  fi

  [[ -t 0 ]]
}

# This decides whether Podman needs to be wrapped with `script` for cleaner TTY behavior.
hermes_should_wrap_podman_tty_with_script() {
  local mode="${HERMES_AGENT_PODMAN_TTY_WRAPPER:-auto}"

  case "$mode" in
    none)
      return 1
      ;;
    script)
      command -v script >/dev/null 2>&1 || {
        printf 'HERMES_AGENT_PODMAN_TTY_WRAPPER=script requires script to be installed.\n' >&2
        return 2
      }
      return 0
      ;;
    auto)
      [[ "${OSTYPE:-}" == darwin* ]] && command -v script >/dev/null 2>&1
      return $?
      ;;
    *)
      printf 'Unsupported HERMES_AGENT_PODMAN_TTY_WRAPPER: %s\n' "$mode" >&2
      return 2
      ;;
  esac
}

# This prints a warning in a consistent format for non-blocking automation and terminals.
hermes_warn() {
  printf 'warning: %s\n' "$1" >&2
}

# This pauses only when a person can see stderr and answer on stdin.
hermes_pause_for_interactive_warning() {
  local _pressed_key

  if [[ -t 0 && -t 2 ]]; then
    printf 'Press any key to continue...' >&2
    IFS= read -r -n 1 -s _pressed_key
    printf '\n' >&2
  fi
}

# This fetches the latest upstream Hermes Agent release without failing callers.
hermes_latest_upstream_version() {
  local release_json tag_regex

  if ! release_json="$(curl -fsSL --connect-timeout 2 --max-time 5 'https://api.github.com/repos/NousResearch/hermes-agent/releases/latest' 2>/dev/null)"; then
    printf '\n'
    return 0
  fi

  tag_regex='"tag_name"[[:space:]]*:[[:space:]]*"v([0-9]+\.[0-9]+\.[0-9]+)"'
  if [[ "$release_json" =~ $tag_regex ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi

  printf '\n'
}

# This compares simple numeric upstream versions like 2026.4.16 against a pinned version.
hermes_version_is_newer_than() {
  local candidate_version="$1"
  local pinned_version="${2#v}"
  local candidate_major candidate_minor candidate_patch pinned_major pinned_minor pinned_patch

  IFS=. read -r candidate_major candidate_minor candidate_patch <<< "$candidate_version"
  IFS=. read -r pinned_major pinned_minor pinned_patch <<< "$pinned_version"

  (( candidate_major > pinned_major )) && return 0
  (( candidate_major < pinned_major )) && return 1
  (( candidate_minor > pinned_minor )) && return 0
  (( candidate_minor < pinned_minor )) && return 1
  (( candidate_patch > pinned_patch ))
}

# This warns when the pinned Hermes Agent release is not the latest upstream release.
hermes_warn_if_pinned_version_is_stale() {
  local latest_version

  latest_version="$(hermes_latest_upstream_version)"
  [[ -n "$latest_version" ]] || return 0
  hermes_version_is_newer_than "$latest_version" "$HERMES_AGENT_RELEASE_TAG" || return 0

  hermes_warn "newer Hermes Agent version available (${latest_version}); continuing with pinned release ${HERMES_AGENT_RELEASE_TAG}"
  hermes_pause_for_interactive_warning
}

# This runs interactive Podman commands in a way that still works from pipes and macOS hosts.
hermes_exec_podman_interactive_command() {
  local subcommand="$1"
  shift
  local wrap_status

  if hermes_use_interactive_tty; then
    if hermes_should_wrap_podman_tty_with_script; then
      wrap_status=0
    else
      wrap_status=$?
    fi

    if [[ "$wrap_status" == "0" ]]; then
      local command=(podman "$subcommand" -it "$@")
      if [[ "${OSTYPE:-}" == darwin* ]]; then
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
    elif [[ "$wrap_status" == "2" ]]; then
      return 2
    fi

    exec podman "$subcommand" -it "$@"
  fi

  exec podman "$subcommand" -i "$@"
}

# This runs an interactive Podman command and then returns to the caller.
hermes_run_podman_interactive_command() {
  local subcommand="$1"
  shift
  local wrap_status

  if hermes_use_interactive_tty; then
    if hermes_should_wrap_podman_tty_with_script; then
      wrap_status=0
    else
      wrap_status=$?
    fi

    if [[ "$wrap_status" == "0" ]]; then
      local command=(podman "$subcommand" -it "$@")
      if [[ "${OSTYPE:-}" == darwin* ]]; then
        script -q /dev/null "${command[@]}"
        return $?
      fi

      local quoted=()
      local arg
      local command_string
      for arg in "${command[@]}"; do
        printf -v arg '%q' "$arg"
        quoted+=("$arg")
      done
      command_string="${quoted[*]}"
      script -q -e -c "$command_string" /dev/null
      return $?
    elif [[ "$wrap_status" == "2" ]]; then
      return 2
    fi

    podman "$subcommand" -it "$@"
    return $?
  fi

  podman "$subcommand" -i "$@"
}

# This treats host junk files like .DS_Store as harmless so they do not block a build.
hermes_is_ignorable_host_untracked_path() {
  local path="$1"

  case "$path" in
    .DS_Store|*/.DS_Store|.AppleDouble|*/.AppleDouble|.LSOverride|*/.LSOverride|Icon$'\r'|*/Icon$'\r'|._*|*/._*|.Spotlight-V100|.Spotlight-V100/*|*/.Spotlight-V100|*/.Spotlight-V100/*|.Trashes|.Trashes/*|*/.Trashes|*/.Trashes/*|.fseventsd|.fseventsd/*|*/.fseventsd|*/.fseventsd/*)
      return 0
      ;;
  esac

  return 1
}

# This checks whether an untracked-file list contains anything meaningful.
hermes_has_meaningful_untracked_files() {
  local path

  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    if ! hermes_is_ignorable_host_untracked_path "$path"; then
      return 0
    fi
  done

  return 1
}

# This checks for real git changes while ignoring stat noise and harmless host junk.
hermes_git_has_meaningful_worktree_changes() {
  local numstat_output
  local summary_output
  local line
  local additions
  local deletions
  local untracked_output

  git -C "$1" update-index -q --refresh >/dev/null 2>&1 || true

  numstat_output="$(git -C "$1" diff --numstat 2>/dev/null || true)"
  while IFS=$'\t' read -r additions deletions _; do
    [[ -n "$additions" ]] || continue
    if [[ "$additions" != "0" || "$deletions" != "0" ]]; then
      return 0
    fi
  done <<< "$numstat_output"

  summary_output="$(git -C "$1" diff --summary 2>/dev/null || true)"
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    return 0
  done <<< "$summary_output"

  numstat_output="$(git -C "$1" diff --cached --numstat 2>/dev/null || true)"
  while IFS=$'\t' read -r additions deletions _; do
    [[ -n "$additions" ]] || continue
    if [[ "$additions" != "0" || "$deletions" != "0" ]]; then
      return 0
    fi
  done <<< "$numstat_output"

  summary_output="$(git -C "$1" diff --cached --summary 2>/dev/null || true)"
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    return 0
  done <<< "$summary_output"

  untracked_output="$(git -C "$1" ls-files --others --exclude-standard 2>/dev/null || true)"
  if hermes_has_meaningful_untracked_files <<< "$untracked_output"; then
    return 0
  fi

  return 1
}

# This makes sure we only build from a saved, tidy checkout.
# This rewrites managed worktree gitdir files to relative paths so host and container namespaces can share them.
hermes_repair_relative_worktree_gitdir() {
  return 0
}

# This makes sure we only build from a saved, tidy checkout.
# This returns the current branch name so build policy can distinguish main from worktree branches.
hermes_git_current_branch() {
  local checkout_root="$1"
  git -C "$checkout_root" symbolic-ref --quiet --short HEAD
}

# This checks whether the current branch has an upstream configured.
hermes_git_branch_has_upstream() {
  local checkout_root="$1"
  git -C "$checkout_root" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' >/dev/null 2>&1
}

# This resolves the configured upstream ref for the current branch.
hermes_git_upstream_ref() {
  local checkout_root="$1"
  git -C "$checkout_root" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}'
}

# This prints the ahead and behind counts against the configured upstream.
hermes_git_branch_ahead_behind() {
  local checkout_root="$1"
  git -C "$checkout_root" rev-list --left-right --count HEAD...@{upstream}
}

# This warns when cached origin HEAD is stale without changing build policy decisions.
hermes_warn_if_origin_head_is_not_main() {
  local checkout_root="$1"
  local remote_head

  remote_head="$(git -C "$checkout_root" symbolic-ref 'refs/remotes/origin/HEAD' 2>/dev/null || true)"
  [[ -n "$remote_head" ]] || return 0
  if [[ "$remote_head" != 'refs/remotes/origin/main' ]]; then
    printf 'warning: local origin/HEAD points to %s, expected refs/remotes/origin/main; ignoring cached remote HEAD for build policy.\n' "$remote_head" >&2
  fi
}

# This enforces the build checkout policy for main and local worktree branches.
hermes_require_build_ready_branch() {
  local checkout_root="$1"
  local current_branch counts ahead behind upstream_ref

  if ! current_branch="$(hermes_git_current_branch "$checkout_root" 2>/dev/null)" || [[ -z "$current_branch" ]]; then
    printf 'Build requires a named branch; detached HEAD is not supported.\n' >&2
    exit 1
  fi

  if [[ "$current_branch" != 'main' ]]; then
    if hermes_git_branch_has_upstream "$checkout_root"; then
      printf 'Build only allows remote-tracking builds from main. Use a clean committed local worktree branch or main tracking origin/main.\n' >&2
      exit 1
    fi
    return 0
  fi

  upstream_ref="$(hermes_git_upstream_ref "$checkout_root" 2>/dev/null || true)"
  if [[ "$upstream_ref" != 'origin/main' ]]; then
    printf 'Build requires main to track origin/main.\n' >&2
    exit 1
  fi

  counts="$(hermes_git_branch_ahead_behind "$checkout_root")"
  ahead="$(printf '%s\n' "$counts" | awk '{print $1}')"
  behind="$(printf '%s\n' "$counts" | awk '{print $2}')"

  if [[ "$ahead" != '0' || "$behind" != '0' ]]; then
    printf 'Build requires main to be pushed and in sync with origin/main.\n' >&2
    exit 1
  fi

  hermes_warn_if_origin_head_is_not_main "$checkout_root"
}

# This makes sure we only build from a saved, tidy checkout.
# If the checkout is messy, the build stops so the image matches real committed code.
hermes_require_clean_committed_checkout() {
  local checkout_root="${1:-$ROOT}"
  local git_error_output=""
  local git_error_path=""
  local parent_dirname=""
  local worktree_name=""
  local expected_container_gitdir=""

  hermes_repair_relative_worktree_gitdir "$checkout_root"

  git_error_path="$(mktemp)"
  if ! git -C "$checkout_root" rev-parse --show-toplevel >/dev/null 2>"$git_error_path"; then
    git_error_output="$(<"$git_error_path")"
    rm -f "$git_error_path"

    parent_dirname="$(basename "$(dirname "$checkout_root")")"
    worktree_name="$(basename "$checkout_root")"
    expected_container_gitdir="/workspace/project/.git/worktrees/$worktree_name"

    if [[ ( "$parent_dirname" == '.worktrees' || "$parent_dirname" == 'worktrees' ) && "$git_error_output" == *"$expected_container_gitdir"* ]]; then
      printf 'This checkout is not a usable git worktree in this environment.\n' >&2
      printf 'Recreate or relink this worktree using relative gitdir paths before building.\n' >&2
      exit 1
    fi

    printf 'Build requires the current checkout to be a valid git repository.\n' >&2
    exit 1
  fi
  rm -f "$git_error_path"

  if ! git -C "$checkout_root" rev-parse --verify HEAD >/dev/null 2>&1; then
    printf 'Build requires the current checkout to have at least one commit.\n' >&2
    exit 1
  fi

  if hermes_git_has_meaningful_worktree_changes "$checkout_root"; then
    printf 'Build requires a clean checkout with all changes committed.\n' >&2
    exit 1
  fi

  hermes_require_build_ready_branch "$checkout_root"
}

# This reads the saved workspace list and splits it into names and offsets.
hermes_load_workspaces() {
  local entry name offset

  HERMES_AGENT_WORKSPACE_NAMES=()
  HERMES_AGENT_WORKSPACE_OFFSETS=()

  for entry in $HERMES_AGENT_WORKSPACES; do
    name="${entry%%:*}"
    offset="${entry#*:}"

    if [[ -z "$name" || -z "$offset" || "$name" == "$offset" ]]; then
      printf 'Each HERMES_AGENT_WORKSPACES entry must look like name:offset.\n' >&2
      exit 1
    fi

    hermes_validate_workspace_name "$name"

    if [[ ! "$offset" =~ ^[0-9]+$ ]]; then
      printf 'Workspace offset for %s must be numeric.\n' "$name" >&2
      exit 1
    fi

    HERMES_AGENT_WORKSPACE_NAMES+=("$name")
    HERMES_AGENT_WORKSPACE_OFFSETS+=("$offset")
  done

  if [[ ${#HERMES_AGENT_WORKSPACE_NAMES[@]} -eq 0 ]]; then
    printf 'Please configure at least one workspace in HERMES_AGENT_WORKSPACES.\n' >&2
    exit 1
  fi
}

# This prints a small menu and returns the workspace the person picked.
hermes_pick_workspace() {
  local selection index

  while true; do
    # This sends the menu to stderr so command substitution only keeps the answer.
    printf 'Pick a workspace:\n' >&2
    for index in "${!HERMES_AGENT_WORKSPACE_NAMES[@]}"; do
      printf '%d) %s\n' "$((index + 1))" "${HERMES_AGENT_WORKSPACE_NAMES[$index]}" >&2
    done
    printf 'Selection: ' >&2

    if ! read -r selection; then
      printf 'Selection aborted.\n' >&2
      exit 1
    fi

    if [[ "$selection" == 'q' ]]; then
      printf 'Selection cancelled.\n' >&2
      exit 1
    fi

    if [[ "$selection" =~ ^[0-9]+$ ]] && (( selection >= 1 && selection <= ${#HERMES_AGENT_WORKSPACE_NAMES[@]} )); then
      printf '%s\n' "${HERMES_AGENT_WORKSPACE_NAMES[$((selection - 1))]}"
      return 0
    fi

    for index in "${!HERMES_AGENT_WORKSPACE_NAMES[@]}"; do
      if [[ "$selection" == "${HERMES_AGENT_WORKSPACE_NAMES[$index]}" ]]; then
        printf '%s\n' "$selection"
        return 0
      fi
    done

    printf 'Please pick one of the configured workspaces.\n' >&2
  done
}

# This looks up the saved port offset for one workspace.
hermes_workspace_offset() {
  local workspace="$1"
  local index

  # This lets helper-only callers resolve workspace ports without preloading first.
  if [[ ${#HERMES_AGENT_WORKSPACE_NAMES[@]} -eq 0 ]]; then
    hermes_load_workspaces
  fi

  for index in "${!HERMES_AGENT_WORKSPACE_NAMES[@]}"; do
    if [[ "$workspace" == "${HERMES_AGENT_WORKSPACE_NAMES[$index]}" ]]; then
      printf '%s\n' "${HERMES_AGENT_WORKSPACE_OFFSETS[$index]}"
      return 0
    fi
  done

  printf 'Workspace %s is not configured.\n' "$workspace" >&2
  exit 1
}

# This returns the host dashboard port for one configured workspace.
hermes_workspace_published_port() {
  local workspace="$1"
  local port_offset published_port

  if [[ ! "$HERMES_AGENT_DASHBOARD_PORT" =~ ^[0-9]+$ ]] || (( HERMES_AGENT_DASHBOARD_PORT < 1 || HERMES_AGENT_DASHBOARD_PORT > 65535 )); then
    printf 'HERMES_AGENT_DASHBOARD_PORT must be a numeric port from 1 to 65535.\n' >&2
    exit 1
  fi

  port_offset="$(hermes_workspace_offset "$workspace")"
  published_port="$((HERMES_AGENT_DASHBOARD_PORT + port_offset))"
  if (( published_port < 1 || published_port > 65535 )); then
    printf 'Published dashboard port for %s must be from 1 to 65535.\n' "$workspace" >&2
    exit 1
  fi

  printf '%s\n' "$published_port"
}

# This returns the host dashboard URL for one configured workspace.
hermes_workspace_published_url() {
  local workspace="$1"
  local published_port

  published_port="$(hermes_workspace_published_port "$workspace")"
  printf 'http://127.0.0.1:%s\n' "$published_port"
}

# This expands a leading home shortcut in configured host paths.
hermes_expand_home_path() {
  local path="$1"

  case "$path" in
    '~')
      printf '%s\n' "$HOME"
      ;;
    '~/'*)
      printf '%s/%s\n' "$HOME" "${path#~/}"
      ;;
    *)
      printf '%s\n' "$path"
      ;;
  esac
}

# This rejects broad host base paths before the wrapper creates or repairs mounts.
hermes_validate_safe_host_base_path() {
  local base_path home_path

  base_path="$(hermes_expand_home_path "$HERMES_AGENT_BASE_PATH")"
  home_path="$HOME"

  while [[ "$base_path" != '/' && "$base_path" == */ ]]; do
    base_path="${base_path%/}"
  done

  while [[ "$home_path" != '/' && "$home_path" == */ ]]; do
    home_path="${home_path%/}"
  done

  case "$base_path" in
    '..'|../*|*/..|*/../*)
      printf 'HERMES_AGENT_BASE_PATH must not contain parent-directory components.\n' >&2
      exit 1
      ;;
  esac

  if [[ -z "$base_path" || "$base_path" == '/' ]]; then
    printf 'HERMES_AGENT_BASE_PATH must point to a managed subdirectory, not /.\n' >&2
    exit 1
  fi

  if [[ "$base_path" == "$home_path" ]]; then
    printf 'HERMES_AGENT_BASE_PATH must point to a managed subdirectory, not the home directory itself.\n' >&2
    exit 1
  fi
}

# This checks that a configured host dirname stays inside the managed workspace path.
hermes_validate_safe_host_dirname() {
  local variable_name="$1"
  local dirname_value="$2"

  if [[ -z "$dirname_value" || "$dirname_value" == '.' || "$dirname_value" == '..' || "$dirname_value" == */* ]]; then
    printf '%s must be a single safe directory name.\n' "$variable_name" >&2
    exit 1
  fi
}

# This checks both host dirname settings before path creation or mounts.
hermes_validate_safe_host_dirnames() {
  hermes_validate_safe_host_dirname 'HERMES_AGENT_HOST_HOME_DIRNAME' "$HERMES_AGENT_HOST_HOME_DIRNAME"
  hermes_validate_safe_host_dirname 'HERMES_AGENT_HOST_WORKSPACE_DIRNAME' "$HERMES_AGENT_HOST_WORKSPACE_DIRNAME"
}

# This rejects symlinked managed paths before root ownership repair can recurse through them.
hermes_reject_symlinked_managed_path() {
  local path="$1"
  local parent

  if [[ -L "$path" ]]; then
    printf 'Managed host path must not be a symlink: %s\n' "$path" >&2
    exit 1
  fi

  parent="${path%/*}"
  while [[ -n "$parent" && "$parent" != '/' ]]; do
    if [[ -L "$parent" ]]; then
      printf 'Managed host path parent must not be a symlink: %s\n' "$parent" >&2
      exit 1
    fi

    [[ "$parent" == */* ]] || break
    parent="${parent%/*}"
  done
}

# This returns the host-side Hermes state path for one workspace.
hermes_host_home_dir() {
  local workspace="$1"
  local base_path

  base_path="$(hermes_expand_home_path "$HERMES_AGENT_BASE_PATH")"
  printf '%s/%s/%s\n' "$base_path" "$workspace" "$HERMES_AGENT_HOST_HOME_DIRNAME"
}

# This returns the host-side mounted project path for one workspace.
hermes_host_workspace_dir() {
  local workspace="$1"
  local base_path

  base_path="$(hermes_expand_home_path "$HERMES_AGENT_BASE_PATH")"
  printf '%s/%s/%s\n' "$base_path" "$workspace" "$HERMES_AGENT_HOST_WORKSPACE_DIRNAME"
}

# This finds the newest local image that matches the saved Hermes naming rules.
hermes_latest_image() {
  local image_name normalized
  local image_regex

  # This keeps the matching rule in one place so image discovery stays predictable.
  image_regex="$(hermes_image_name_regex)"

  while IFS= read -r image_name; do
    [[ -n "$image_name" ]] || continue
    normalized="$(hermes_normalize_image_ref "$image_name")"
    if [[ "$normalized" =~ $image_regex ]]; then
      printf '%s\n' "$normalized"
      return 0
    fi
  done < <(podman images --sort created --format '{{.Repository}}' 2>/dev/null || true)

  printf '\n'
}

# This removes a localhost prefix so local image names compare the same way.
hermes_normalize_image_ref() {
  local image_ref="$1"
  printf '%s\n' "${image_ref#localhost/}"
}

# This finds the newest running container for one workspace.
hermes_running_container() {
  local workspace="$1"
  local container_name

  while IFS= read -r container_name; do
    [[ -n "$container_name" ]] || continue
    if hermes_container_workspace_matches "$container_name" "$workspace"; then
      printf '%s\n' "$container_name"
      return 0
    fi
  done < <(podman ps --sort created --format '{{.Names}}' --filter "name=$(hermes_runtime_container_filter_regex "$workspace")" 2>/dev/null || true)

  printf '\n'
}

# This lists all containers for one workspace, even stopped ones.
hermes_workspace_containers() {
  local workspace="$1"
  local prefix
  local container_name

  prefix="$(hermes_container_filter_regex "$workspace")"
  while IFS= read -r container_name; do
    [[ -n "$container_name" ]] || continue
    if hermes_container_workspace_matches "$container_name" "$workspace"; then
      printf '%s\n' "$container_name"
    fi
  done < <(podman ps -aq --format '{{.Names}}' --filter "name=${prefix}" 2>/dev/null || true)
}

# This lists all pods for one workspace, even when their containers are gone.
hermes_workspace_pods() {
  local workspace="$1"
  local prefix
  local pod_name

  prefix="$(hermes_container_filter_regex "$workspace")"
  while IFS= read -r pod_name; do
    [[ -n "$pod_name" ]] || continue
    if ! hermes_name_matches_other_configured_workspace "$pod_name" "$workspace"; then
      printf '%s\n' "$pod_name"
    fi
  done < <(podman pod ps -aq --format '{{.Name}}' --filter "name=${prefix}" 2>/dev/null || true)
}

# This checks whether a runtime-like name belongs to a configured workspace other than the requested one.
hermes_name_matches_other_configured_workspace() {
  local candidate_name="$1"
  local requested_workspace="$2"
  local workspace regex

  if [[ ${#HERMES_AGENT_WORKSPACE_NAMES[@]} -eq 0 ]]; then
    hermes_load_workspaces
  fi

  for workspace in "${HERMES_AGENT_WORKSPACE_NAMES[@]}"; do
    [[ "$workspace" != "$requested_workspace" ]] || continue
    regex="$(hermes_runtime_container_filter_regex "$workspace")"
    if [[ "$candidate_name" =~ $regex ]]; then
      return 0
    fi
  done

  return 1
}

# This checks whether a container mounts the selected workspace at the fixed workspace path.
hermes_container_workspace_matches() {
  local container_name="$1"
  local workspace="$2"
  local mounts expected

  expected="$(hermes_host_workspace_dir "$workspace"):$HERMES_AGENT_CONTAINER_WORKSPACE"
  mounts="$(podman inspect --format '{{range .Mounts}}{{println .Source ":" .Destination}}{{end}}' "$container_name" 2>/dev/null || true)"
  printf '%s\n' "$mounts" | sed 's/[[:space:]]*:[[:space:]]*/:/g' | grep -Fqx -- "$expected"
}

# This checks whether one exact container is running right now.
hermes_container_is_running() {
  local container_name="$1"
  local running_container

  running_container="$(podman ps --format '{{.Names}}' --filter "name=$(hermes_container_name_regex "$container_name")" | head -n 1)"
  [[ "$running_container" == "$container_name" ]]
}

# This waits a few times because a container may need a moment to show up as running.
hermes_wait_for_running_container() {
  local container_name="$1"
  local attempt

  for attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    if hermes_container_is_running "$container_name"; then
      return 0
    fi
    sleep 1
  done

  return 1
}

# This confirms a running container stays up across the short pre-attach window.
hermes_wait_for_stable_running_container() {
  local container_name="$1"
  local attempt

  for attempt in 1 2; do
    if ! hermes_container_is_running "$container_name"; then
      return 1
    fi
    sleep 1
  done

  hermes_container_is_running "$container_name"
}

# This gathers a short state summary without failing the wrapper when diagnostics break.
hermes_container_image_summary() {
  local container_name="$1"
  local summary

  if summary="$(podman inspect --format 'image={{.ImageName}}' "$container_name" 2>/dev/null)"; then
    if [[ -n "$summary" ]]; then
      printf '%s\n' "$summary"
      return 0
    fi
  fi

  printf 'unavailable\n'
}

# This gathers a short state summary without failing the wrapper when diagnostics break.
hermes_container_state_summary() {
  local container_name="$1"
  local summary

  if summary="$(podman inspect --format 'status={{.State.Status}} running={{.State.Running}} exit_code={{.State.ExitCode}}' "$container_name" 2>/dev/null)"; then
    if [[ -n "$summary" ]]; then
      printf '%s\n' "$summary"
      return 0
    fi
  fi

  printf 'unavailable\n'
}

# This reads recent container logs without failing the wrapper when Podman cannot provide them.
hermes_container_recent_logs() {
  local container_name="$1"
  local logs

  if logs="$(podman logs --tail 20 "$container_name" 2>/dev/null)"; then
    if [[ -n "$logs" ]]; then
      printf '%s\n' "$logs"
      return 0
    fi

    printf '(no recent logs)\n'
    return 0
  fi

  return 1
}

# This prints a compact diagnostic block for startup failures.
hermes_print_container_startup_diagnostics() {
  local container_name="$1"

  printf 'Container image: %s\n' "$(hermes_container_image_summary "$container_name")" >&2
  printf 'Container state: %s\n' "$(hermes_container_state_summary "$container_name")" >&2

  local recent_logs
  if ! recent_logs="$(hermes_container_recent_logs "$container_name")"; then
    printf 'Recent container logs: unavailable\n' >&2
    return 0
  fi

  printf 'Recent container logs:\n' >&2
  printf '%s\n' "$recent_logs" >&2
}

# This checks whether the current host shell is running on macOS.
hermes_host_is_macos() {
  [[ "$(uname -s)" == 'Darwin' ]]
}

# This checks whether the current host shell is running on Linux.
hermes_host_is_linux() {
  [[ "$(uname -s)" == 'Linux' ]]
}

# This waits briefly for the published dashboard URL to answer before opening a browser.
hermes_wait_for_published_url() {
  local url="$1"
  local attempt

  for attempt in 1 2 3 4 5; do
    if curl -fsS --connect-timeout 1 --max-time 1 "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  return 1
}

# This opens the published dashboard URL without delaying the attach flow.
hermes_open_published_url_detached() {
  local dashboard_url="$1"

  if hermes_host_is_macos; then
    nohup open "$dashboard_url" >/dev/null 2>&1 < /dev/null &
    return 0
  fi

  if hermes_host_is_linux; then
    nohup bash -c '
      if xdg-open "$1" >/dev/null 2>&1; then
        exit 0
      fi
      gio open "$1" >/dev/null 2>&1 || true
    ' _ "$dashboard_url" >/dev/null 2>&1 < /dev/null &
  fi
}

# This resolves the uid that should own mounted workspace paths on the host.
hermes_host_uid() {
  local uid

  uid="$(id -u)"
  if [[ "$uid" == '0' ]]; then
    printf '%s\n' "${SUDO_UID:-0}"
    return 0
  fi
  printf '%s\n' "$uid"
}

# This resolves the gid that should own mounted workspace paths on the host.
hermes_host_gid() {
  local gid

  gid="$(id -g)"
  if [[ "$gid" == '0' ]]; then
    printf '%s\n' "${SUDO_GID:-0}"
    return 0
  fi
  printf '%s\n' "$gid"
}
