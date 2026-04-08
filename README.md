# Hermes Agent container wrapper

This repo is the multi-workspace Podman-first wrapper for running Hermes Agent in a persistent container.

Upstream Hermes already provides an official single-container Docker workflow. This repo exists to add:

- named workspace containers
- separate persistent Hermes state and project workspace mounts
- immutable image tags and deterministic container names
- interactive target selection so users do not have to type long identity arguments
- shared scripts that work on both macOS and Linux

## Layout

- `config/shared/` holds shared wrapper configuration
- `config/macos/` is reserved for macOS-only config if needed
- `config/containers/` holds shared container build files
- `config/patches/` holds wrapper-specific upstream patches
- `docs/shared/` holds shared documentation for macOS and Linux
- `docs/macos/` is reserved for macOS-only docs if needed
- `lib/shell/` holds shared shell helpers
- `scripts/shared/` holds shared wrapper commands
- `scripts/macos/` is reserved for macOS-only helper commands if needed
- `tests/shared/` holds the shared shell test suite
- `tests/macos/` is reserved for macOS-only tests if needed

`shared` means the files are intended to work on both macOS and Linux. `macos` means macOS-only.

## Current status

This worktree now follows the newer immutable-image multi-workspace model for the shared build and runtime scripts.

The detailed implementation plan lives in:

- `docs/shared/implementation-plan.md`

The shared usage document reflects the current script contracts:

- `docs/shared/usage.md`

## Command set

- `hermes-bootstrap`
- `hermes-build`
- `hermes-start`
- `hermes-open`
- `hermes-shell`
- `hermes-logs`
- `hermes-status`
- `hermes-stop`
- `hermes-remove`

## Key decisions already made

- production builds only run from the canonical main checkout
- test builds may run from canonical main or from a worktree
- upstream selector values are `main`, `latest`, or an explicit upstream version name
- image tags are immutable and include lane, upstream, wrapper, and wrapper commit identity
- container names are human-readable and deterministic
- Ubuntu LTS and Node LTS are pinned in config, and `hermes-build` checks whether newer LTS versions exist
- `hermes-bootstrap` and `hermes-start` select from existing project targets for a workspace, while `hermes-open`, `hermes-shell`, `hermes-logs`, `hermes-status`, and `hermes-stop` operate on existing project containers for a workspace
- `hermes-start` and `hermes-open` also support explicit `workspace lane upstream` targeting when the user wants to bypass the picker
- there is no `hermes-upgrade` command and no `bootstrap-test`

## Command style

The default workflow is workspace-first and picker-driven:

- `hermes-build <lane> [upstream]`
- `hermes-bootstrap <workspace> [hermes args...]`
- `hermes-start <workspace> [hermes args...]`
- `hermes-open <workspace> [hermes args...]`

For power-user and scriptable flows, the current shared scripts also allow explicit target selection where implemented:

- `hermes-start <workspace> <lane> <upstream>`
- `hermes-open <workspace> <lane> <upstream> [hermes args...]`

When `latest` is selected, the wrapper resolves it from upstream releases, uses the human release label in immutable image naming, and keeps the exact upstream git ref separately in image metadata.

## Matrix and patches

Upstream Hermes `0.8.0` now covers most of the broad Matrix wrapper patch surface.

Current patch state:

- removed `apply-hermes-matrix-upload-filesize.py`
- removed `apply-hermes-matrix-encrypted-media.py`
- removed `apply-hermes-matrix-auto-verification.py`
- kept `apply-hermes-matrix-device-id.py` because the wrapper must support stable password-login Matrix identity via `MATRIX_USER_ID`, `MATRIX_PASSWORD`, and `MATRIX_DEVICE_ID`
- reduced `apply-hermes-matrix-config-overrides.py` to the narrow `MATRIX_ALLOWED_USERS` remainder

## Current source of truth

Use the detailed shared implementation plan for the full rationale and remaining follow-up work:

- `docs/shared/implementation-plan.md`
