# Hermes Agent Container Implementation Plan

## Goal

Move the Hermes container wrapper from the older mutable-image lifecycle to a cleaner Podman-first multi-workspace model with immutable image tags, deterministic container names, and interactive target selection.

The wrapper should:

- run Hermes inside a persistent Ubuntu LTS container
- support both canonical main-checkout and worktree-based wrapper builds
- use immutable image tags
- use readable deterministic container names
- prefer interactive selection over forcing users to type long identity arguments
- keep shared logic in `lib/`
- preserve Hermes-specific runtime state, seeding, and patching where still required

`shared` means the files are intended to work on both macOS and Linux. `macos` means macOS-only.

The directory structure should follow the Hermes layout pattern:

- `config/shared/` for shared config
- `config/macos/` for macOS-only config if needed
- `config/containers/` for shared container build files
- `config/patches/` for wrapper-specific upstream patch files
- `docs/shared/` for shared docs
- `docs/macos/` for macOS-only docs if needed
- `lib/shell/` for shared shell helpers
- `scripts/shared/` for shared wrapper commands
- `scripts/macos/` for macOS-only helpers if needed
- `tests/shared/` for shared shell tests
- `tests/macos/` for macOS-only tests if needed

## Scope

This plan applies to the Hermes Agent container wrapper itself, not to upstream Hermes core behavior.

The wrapper must preserve Hermes-specific concerns such as:

- `hermes-home` state layout
- `.env` and `config.yaml` seeding
- host-backed `AGENTS.md` precedence patching
- runtime compatibility links
- any narrow upstream patching that still remains justified after `0.8.0`

## Core Model

There are two distinct versioning dimensions:

1. Upstream app version
- `main`
- `latest`
- an explicit upstream version name exactly as used by the upstream team, for example `0.8.0`

2. Wrapper context
- `main` when run from the canonical main checkout
- the worktree name when run from a worktree

These dimensions must stay separate in naming and selection logic.

## Source Rules

### Production

Production builds:

- must run from the canonical main checkout
- must not run from a linked worktree, even if that worktree is checked out on branch `main`
- require a clean working tree
- require no unpushed commits
- require the canonical main checkout to be in sync with GitHub

Primary detection:

- use Git primary-vs-linked-worktree detection

Fallback detection:

- use directory convention detection, such as `*-worktrees/`

### Test

Test builds:

- may run from the canonical main checkout or from a worktree
- require a clean working tree
- do not require pushes to GitHub

The wrapper context is always inferred from where the command is run.

## Upstream Version Rules

The upstream argument always means the upstream app version selector. It does not select the local wrapper source.

Accepted upstream values:

- `main`
- `latest`
- explicit upstream version name, for example `0.8.0`

Resolution:

- `main` stays `main`
- explicit version stays exactly as given
- `latest` resolves live from upstream releases to a display label plus exact git ref
- the display label is used in immutable wrapper naming
- the exact upstream git ref is kept separately in image metadata and build arguments

Examples:

- `latest` -> `0.8.0`
- `0.8.0` -> `0.8.0`
- `main` -> `main`

## Image Model

### Base Image

Always use the latest Ubuntu LTS and a current Node LTS, but pin both in configuration.

Implementation:

- keep the Ubuntu LTS and Node LTS pins in a configuration file
- the Dockerfile consumes that configured pin
- `hermes-build` checks the current latest Ubuntu LTS and Node LTS live before building
- if either latest LTS differs from the configured pin, prompt the user to:
  - keep the current pin
  - update the pin and continue
  - cancel

If the user chooses to update:

- update the configuration file
- continue the build using the new pin

There is no separate `upgrade` command.

### Image Naming

Each built image gets exactly one immutable tag.

Image reference shape:

- `<image-name>:<lane>-<upstream>-<wrapper>-<commitstamp>`

Where:

- `<lane>` is `production` or `test`
- `<upstream>` is the resolved upstream name
- `<wrapper>` is `main` or the worktree name
- `<commitstamp>` is the wrapper commit identity in the format `YYYYMMDD-HHMMSS-<commitid>`
- the date/time component is the wrapper commit timestamp, not build time

Examples:

- `hermes-agent-local:production-0.8.0-main-20260408-153210-ab12cd3`
- `hermes-agent-local:production-main-main-20260408-153210-ab12cd3`
- `hermes-agent-local:test-0.8.0-improve-production-and-testing-20260408-153210-ab12cd3`
- `hermes-agent-local:test-main-main-20260408-153210-ab12cd3`

Rationale:

- one unique image tag identifies exactly one binary
- no mutable lane aliases like `:production` or `:test`
- no shared plain tags like `:main` or `:0.8.0`

## Container Model

Containers should be human-readable and deterministic.

Container name shape:

- `<project>-<workspace>-<lane>-<upstream>-<wrapper>`

Examples:

- `hermes-agent-ezirius-production-0.8.0-main`
- `hermes-agent-ezirius-production-main-main`
- `hermes-agent-ezirius-test-0.8.0-improve-production-and-testing`
- `hermes-agent-ezirius-test-main-main`

Notes:

- the duplicate `main-main` form is acceptable
- first `main` means upstream version selector
- second `main` means wrapper context

Containers are persistent and long-lived.

CLI operations should `exec` into the running container rather than starting transient second containers against the same state.

## Persistent Layout

Per workspace, use separate host-backed paths for persistent app state and user project workspace.

Expected shape:

- `<base-root>/<workspace>/hermes-home` -> mounted into the container for Hermes state/config
- `<base-root>/<workspace>/workspace` -> mounted to `/workspace`

The in-container state path remains `/opt/data`.

On first run, the wrapper should continue to seed missing baseline files such as:

- `.env`
- `config.yaml`
- `SOUL.md`
- `AGENTS.md`

The wrapper should keep the host-backed `AGENTS.md` precedence behavior that this repo already depends on.

## Script Set

Keep these scripts:

- `scripts/shared/hermes-build`
- `scripts/shared/hermes-bootstrap`
- `scripts/shared/hermes-start`
- `scripts/shared/hermes-open`
- `scripts/shared/hermes-shell`
- `scripts/shared/hermes-logs`
- `scripts/shared/hermes-status`
- `scripts/shared/hermes-stop`
- `scripts/shared/hermes-remove`

Remove these scripts from the old model:

- `scripts/shared/hermes-upgrade`
- `scripts/shared/bootstrap-test`

## Shared Code Placement

Any code reused by more than one script must go into `lib/`.

Primary shared location:

- `lib/shell/common.sh`

Shared code should include:

- config loading
- path helpers
- Podman helpers
- Git validation helpers
- canonical-main vs linked-worktree detection
- worktree name resolution
- upstream release lookup
- latest Ubuntu LTS lookup
- wrapper commit timestamp and commit id resolution
- image tag generation
- container name generation
- project-scoped image/container discovery
- sorting helpers
- picker rendering and selection helpers
- status formatting helpers

## Configuration

Use a shell-sourced configuration file.

Path:

- `config/shared/hermes.conf`

This config should hold at least:

- image base name
- project/container prefix
- upstream repo URL
- pinned Ubuntu LTS version
- base workspace root

Example fields:

- `HERMES_IMAGE_NAME`
- `HERMES_PROJECT_PREFIX`
- `HERMES_REPO_URL`
- `HERMES_UBUNTU_LTS_VERSION`
- `HERMES_BASE_ROOT`

## Command Contracts

### hermes-build

Usage:

- `hermes-build <lane> <upstream>`
- `hermes-build <lane>`

Rules:

- `lane` is required
- `lane` must be `production` or `test`
- if `upstream` is omitted, show a selectable list containing:
  - `main`
  - all upstream releases fetched live, newest to oldest
- for `production`, enforce canonical main checkout rules
- for `test`, use the current execution context as wrapper context
- before building, check the Ubuntu LTS pin against the current latest Ubuntu LTS

### hermes-bootstrap

Usage:

- `hermes-bootstrap <workspace> [hermes args...]`

Behavior:

- show a workspace target picker that may include existing project containers and image-only targets
- fail with a helpful message if no built project images exist for that workspace
- start if needed
- forward any extra args to Hermes inside the selected running container

### hermes-start

Usage:

- `hermes-start <workspace> [hermes args...]`
- `hermes-start <workspace> <lane> <upstream>`

Behavior:

- same target picker behavior as `hermes-bootstrap`
- the picker may include existing project containers and image-only targets
- fail with a helpful message if no built project images exist for that workspace
- start if needed
- forward any extra args to Hermes inside the selected running container
- in explicit mode, bypass the picker and resolve the target directly from `workspace`, `lane`, and `upstream`

### hermes-open

Usage:

- `hermes-open <workspace> [hermes args...]`
- `hermes-open <workspace> <lane> <upstream> [hermes args...]`

Behavior:

- show a workspace container picker
- fail with a helpful message if no matching project containers exist for that workspace
- `exec` Hermes inside the running container
- forward all extra args to Hermes
- in explicit mode, bypass the picker and resolve the deterministic container name directly from `workspace`, `lane`, and `upstream`

Examples:

- `hermes-open ezirius doctor`
- `hermes-open ezirius model`
- `hermes-open ezirius tools`
- `hermes-open ezirius gateway`
- `hermes-open ezirius chat`
- `hermes-open ezirius mcp serve`

### hermes-shell

Usage:

- `hermes-shell <workspace> [command args...]`

Behavior:

- show a workspace container picker
- fail with a helpful message if no matching project containers exist for that workspace
- if no extra args are given, open an interactive shell in the container
- if extra args are given, execute that command in the container instead of opening a shell

### hermes-logs

Usage:

- `hermes-logs <workspace> [podman logs args...]`

Behavior:

- show a workspace container picker
- fail with a helpful message if no matching project containers exist for that workspace
- forward additional args to `podman logs`

### hermes-status

Usage:

- `hermes-status <workspace>`

Behavior:

- show a workspace container picker
- fail with a helpful message if no matching project containers exist for that workspace
- inspect/report the selected container state

### hermes-stop

Usage:

- `hermes-stop <workspace>`

Behavior:

- show a workspace container picker
- fail with a helpful message if no matching project containers exist for that workspace
- stop the selected running container

### hermes-remove

Usage:

- `hermes-remove <container|image>`

Rules:

- no workspace arg
- mode is required
- mode must be `container` or `image`

Menu layout:

1. `All, but newest`
2. `All`
3. then individual items newest to oldest by wrapper commit date

Semantics:

- `container` mode operates only on project containers
- `image` mode operates only on project images
- `All, but newest` in container mode leaves the newest container per workspace
- `All, but newest` in image mode leaves the newest image overall per workspace

## Picker UX

### General Picker Rules

When a workspace command only receives `<workspace>`, it should show a project-scoped interactive list.

There are two picker types:

- target picker: used by `hermes-bootstrap` and `hermes-start`; may show existing project containers and image-only targets for the selected workspace
- container picker: used by `hermes-open`, `hermes-shell`, `hermes-logs`, `hermes-status`, and `hermes-stop`; shows only existing project containers for the selected workspace

Selection ordering:

1. production targets first
2. within production, newest to oldest by wrapper commit date
3. test targets next
4. within test, newest to oldest by wrapper commit date

Only project-specific images/containers should be shown. This project scoping applies to all picker-based scripts.

For `hermes-bootstrap` and `hermes-start`, image-only targets are valid because the command may create or recreate the workspace container from the selected image.

For `hermes-open`, `hermes-shell`, `hermes-logs`, `hermes-status`, and `hermes-stop`, only existing containers are valid targets.

### Container Display

Display columns:

- lane
- upstream
- wrapper
- commit stamp
- container status

Example:

- `production  0.8.0     main                              running`
- `test        main       improve-production-and-testing    stopped`

Status labels:

- `running`
- `stopped`

### Image Display

Display columns should align with container display for consistency:

- lane
- upstream
- wrapper
- commit stamp
- image usage/status

Example:

- `production  0.8.0     main                              in use`
- `test        main       improve-production-and-testing    unused`

Status labels:

- removal picker: `in use`, `unused`
- workspace target picker when image-backed rows are mixed with containers: `running`, `stopped`, `image only`

### Empty Results

If a picker finds no valid targets for the command being run:

- fail with a helpful message
- do not auto-build

## Patch Minimisation For 0.8.0

Upstream Hermes `0.8.0` now covers most of the broad Matrix wrapper patch surface.

### Remove

- `apply-hermes-matrix-upload-filesize.py`
- `apply-hermes-matrix-encrypted-media.py`
- `apply-hermes-matrix-auto-verification.py`

Reasons:

- upstream already includes upload `filesize`
- upstream already includes encrypted media event handling, attachment decryption, and local-file caching
- auto-verification is not a wrapper behavior worth preserving and previously did not work as intended

### Keep

- `apply-hermes-matrix-device-id.py`

Reason:

- the wrapper must support a stable Matrix device using `MATRIX_USER_ID`, `MATRIX_PASSWORD`, and `MATRIX_DEVICE_ID`
- this wrapper policy must not rely on access-token auth for the stable-device path
- upstream `0.8.0` still does not implement the wrapper’s stronger password-login `device_id` preservation path

### Current narrow remainder

- `apply-hermes-matrix-config-overrides.py`

Current retained remainder:

- `MATRIX_ALLOWED_USERS`

### Keep unchanged outside Matrix

- `apply-hermes-host-agents-context.py`
- `apply-hermes-transcription-oga.py`

## Matrix Runtime Notes

The wrapper should stay as close to upstream Matrix behavior as practical, while still preserving the explicitly required stable password-login device behavior.

Important points:

- Matrix support still requires the right image dependencies
- `libolm-dev` remains part of the image while encrypted Matrix support still depends on it
- state should continue to persist through `HERMES_HOME` and the wrapper compatibility link to `/opt/data`

Matrix validation should explicitly verify:

- one stable device appears when using `MATRIX_USER_ID`, `MATRIX_PASSWORD`, and `MATRIX_DEVICE_ID`
- the same device persists across restarts
- encrypted DM/group/threaded media flows work on the real homeserver
- if `MATRIX_ALLOWED_USERS` remains, its wiring still behaves exactly as intended

## Build Discovery and Selection

For `hermes-build <lane>` without an explicit upstream argument:

- fetch the release list live from upstream
- present `main` first
- then present releases newest to oldest

The build script should not require any third argument, because wrapper context always comes from where the command is run.

## Podman and Execution Model

Use Podman throughout.

Expected behavior:

- build images with Podman
- run persistent named containers with restart policy
- `exec` into running containers for Hermes commands and shell commands
- allow additional arguments to flow through to either Podman or Hermes, depending on the command

Forwarding rules:

- `hermes-bootstrap`, `hermes-start`, `hermes-open`: forward extra args to Hermes
- `hermes-logs`: forward extra args to `podman logs`
- `hermes-shell`: with args, execute the command in-container; without args, open a shell

## Validation and Safety Rules

Build-time validation:

- reject invalid lane values
- reject invalid upstream values
- reject production builds from linked worktrees
- reject dirty working trees for both lanes
- reject production builds when canonical main has unpushed commits or is not in sync with GitHub

Remove-time safety:

- operate only on project-scoped items
- sort newest to oldest by wrapper commit date
- preserve the newest target where required by `All, but newest`

## Implementation Phases

### Phase 1: Skeleton and Config

- add `config/shared/hermes.conf`
- add shared loading and validation logic in `lib/shell/common.sh`
- define image and container naming helpers

### Phase 2: Build Logic

- implement upstream release discovery
- implement canonical main vs worktree detection
- implement wrapper commit identity resolution
- implement Ubuntu LTS pin check and prompt
- implement immutable image tagging logic
- implement `hermes-build`

### Phase 3: Runtime and Selection

- implement project-scoped image/container listing
- implement newest-first sorting
- implement interactive pickers
- implement `hermes-bootstrap`, `hermes-start`, `hermes-open`, `hermes-shell`

### Phase 4: Operational Scripts

- implement `hermes-logs`, `hermes-status`, `hermes-stop`, `hermes-remove`
- implement remove-mode menus and `All, but newest` behavior

### Phase 5: Patch Reduction

- remove obsolete Matrix patches
- reduce `apply-hermes-matrix-config-overrides.py` to the narrow remaining `MATRIX_ALLOWED_USERS` behavior
- validate that the required password-login stable-device behavior still works with the retained `matrix-device-id` patch

### Phase 6: Docs and Tests

- document all script contracts clearly
- enforce strict argument counts and usage help
- update shell tests for naming, selection, build validation, removal behavior, config update flow, and retained patch behavior

## Testing Requirements

Tests should cover:

- argument validation
- upstream resolution for `main`, `latest`, and explicit versions
- canonical main vs linked worktree detection
- production clean/pushed requirements
- test clean requirements
- image tag generation
- container name generation
- sorting by wrapper commit date
- picker ordering
- remove semantics for `All, but newest` and `All`
- Ubuntu LTS pin update prompt flow
- retained Matrix password-login stable-device behavior
- reduced patch inventory still applying cleanly

## Summary

The Hermes wrapper should move to:

- immutable image tags
- readable deterministic container names
- config-driven Ubuntu LTS pinning with build-time update prompts
- interactive workspace-based target selection
- a reduced script set with no `hermes-upgrade` and no `bootstrap-test`
- a sharply reduced Matrix patch surface for upstream `0.8.0`
- shared implementation in `lib/`

This document should be treated as the implementation source of truth for the current worktree.
