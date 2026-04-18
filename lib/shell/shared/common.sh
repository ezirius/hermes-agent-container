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

  if [[ ! "$name" =~ ^[A-Za-z0-9._-]+$ ]]; then
    printf 'Workspace name %s may only contain letters, numbers, dots, underscores, and hyphens.\n' "$name" >&2
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
  printf '^%s-%s-[0-9]{8}-[0-9]{6}-[0-9]{3}$\n' "$escaped_basename" "$escaped_version"
}

# This builds the regex used to find containers for one workspace.
hermes_container_filter_regex() {
  local workspace="$1"
  local escaped_basename escaped_workspace escaped_version

  escaped_basename="$(hermes_regex_escape "$HERMES_AGENT_IMAGE_BASENAME")"
  escaped_workspace="$(hermes_regex_escape "$workspace")"
  escaped_version="$(hermes_regex_escape "$HERMES_AGENT_VERSION")"
  printf '^%s-%s-%s-\n' "$escaped_basename" "$escaped_workspace" "$escaped_version"
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
# If the checkout is messy, the build stops so the image matches real committed code.
hermes_require_clean_committed_checkout() {
  local checkout_root="${1:-$ROOT}"

  if ! git -C "$checkout_root" rev-parse --verify HEAD >/dev/null 2>&1; then
    printf 'Build requires the current checkout to have at least one commit.\n' >&2
    exit 1
  fi

  if hermes_git_has_meaningful_worktree_changes "$checkout_root"; then
    printf 'Build requires a clean checkout with all changes committed.\n' >&2
    exit 1
  fi
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

  # This sends the menu to stderr so command substitution only keeps the answer.
  printf 'Pick a workspace:\n' >&2
  for index in "${!HERMES_AGENT_WORKSPACE_NAMES[@]}"; do
    printf '%d) %s\n' "$((index + 1))" "${HERMES_AGENT_WORKSPACE_NAMES[$index]}" >&2
  done
  printf 'Selection: ' >&2

  read -r selection

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
  exit 1
}

# This looks up the saved port offset for one workspace.
hermes_workspace_offset() {
  local workspace="$1"
  local index

  for index in "${!HERMES_AGENT_WORKSPACE_NAMES[@]}"; do
    if [[ "$workspace" == "${HERMES_AGENT_WORKSPACE_NAMES[$index]}" ]]; then
      printf '%s\n' "${HERMES_AGENT_WORKSPACE_OFFSETS[$index]}"
      return 0
    fi
  done

  printf 'Workspace %s is not configured.\n' "$workspace" >&2
  exit 1
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

# This builds a simple prefix for container names from one workspace.
hermes_container_prefix() {
  local workspace="$1"
  printf '%s-%s-\n' "$HERMES_AGENT_IMAGE_BASENAME" "$workspace"
}

# This finds the newest running container for one workspace.
hermes_running_container() {
  local workspace="$1"
  local prefix

  prefix="$(hermes_container_filter_regex "$workspace")"
  podman ps --format '{{.Names}}' --filter "name=${prefix}" | sort -r | head -n 1
}

# This lists all containers for one workspace, even stopped ones.
hermes_workspace_containers() {
  local workspace="$1"
  local prefix

  prefix="$(hermes_container_filter_regex "$workspace")"
  podman ps -aq --format '{{.Names}}' --filter "name=${prefix}" 2>/dev/null || true
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

# This checks whether the container setup files have been written yet.
hermes_container_setup_is_complete() {
  local container_name="$1"

  podman exec "$container_name" bash -lc 'test -s "$HERMES_HOME/config.toml" && test -s "$HERMES_HOME/.env"' >/dev/null 2>&1
}

# This checks the official gateway state and dashboard probe after setup is complete.
hermes_container_services_are_healthy() {
  local container_name="$1"

  podman exec "$container_name" bash -lc 'python -c '"'"'import json, os, sys; path=os.path.join(os.environ["HERMES_HOME"], "gateway_state.json"); data=json.load(open(path, encoding="utf-8")); sys.exit(0 if data.get("gateway_state") == "running" else 1)'"'"' && curl -fsS "http://127.0.0.1:${HERMES_AGENT_DASHBOARD_PORT}/" >/dev/null' >/dev/null 2>&1
}

# This checks the setup files, official gateway state, and dashboard probe inside one running container.
hermes_container_is_ready() {
  local container_name="$1"

  hermes_container_setup_is_complete "$container_name" && hermes_container_services_are_healthy "$container_name"
}

# This waits until the running container finishes setup and both local services answer healthy.
hermes_wait_for_healthy_container() {
  local container_name="$1"
  local attempt

  for attempt in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    if hermes_container_is_running "$container_name" && hermes_container_is_ready "$container_name"; then
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

# This chooses which host command should open the dashboard URL.
hermes_resolve_open_command() {
  local configured="${HERMES_AGENT_OPEN_COMMAND:-auto}"

  case "$configured" in
    auto)
      if [[ "${OSTYPE:-}" == darwin* ]] && command -v open >/dev/null 2>&1; then
        printf 'open\n'
        return 0
      fi
      if command -v xdg-open >/dev/null 2>&1; then
        printf 'xdg-open\n'
        return 0
      fi
      if command -v open >/dev/null 2>&1; then
        printf 'open\n'
        return 0
      fi
      return 1
      ;;
    open|xdg-open)
      if ! command -v "$configured" >/dev/null 2>&1; then
        printf 'Configured opener is not available: %s\n' "$configured" >&2
        return 2
      fi
      printf '%s\n' "$configured"
      ;;
    *)
      printf 'Unsupported HERMES_AGENT_OPEN_COMMAND: %s\n' "$configured" >&2
      return 2
      ;;
  esac
}

# This opens the dashboard URL on the host when a working opener exists.
hermes_open_dashboard() {
  local dashboard_url="$1"
  local opener
  local status

  if opener="$(hermes_resolve_open_command)"; then
    "$opener" "$dashboard_url" >/dev/null 2>&1 || true
  else
    status=$?
    if [[ "$status" == "1" ]]; then
      return 0
    fi
    return "$status"
  fi
}
