# Hermes Agent container usage

## Current model

This wrapper now uses:

- immutable image tags
- deterministic container names
- picker-based workspace commands
- pinned Ubuntu LTS and Node LTS versions configured in `config/shared/hermes.conf`
- no `hermes-upgrade`
- no `bootstrap-test`
- no auto-build from workspace commands

## Build

Use:

- `./scripts/shared/hermes-build <lane> <upstream>`
- `./scripts/shared/hermes-build <lane>`

Where:

- `lane` is `production` or `test`
- `upstream` is `main`, `latest`, or an exact upstream version name

If `upstream` is omitted, the script prompts with:

- `main`
- available upstream release tags, newest to oldest

If `latest` is selected, the wrapper resolves it from the upstream release list, uses the display label in the immutable image tag, and stores the exact upstream git ref separately in image metadata.

Production builds:

- must run from the canonical main checkout
- must be clean
- must have no unpushed commits

Test builds:

- may run from the canonical main checkout or a worktree
- must be clean

## Workspace commands

The default workspace-facing commands take a workspace name and use interactive project-scoped selection:

- `./scripts/shared/hermes-bootstrap <workspace> [hermes args...]`
- `./scripts/shared/hermes-start <workspace> [hermes args...]`
- `./scripts/shared/hermes-open <workspace> [hermes args...]`
- `./scripts/shared/hermes-shell <workspace> [command args...]`
- `./scripts/shared/hermes-logs <workspace> [podman log args...]`
- `./scripts/shared/hermes-status <workspace>`
- `./scripts/shared/hermes-stop <workspace>`

`hermes-bootstrap` and `hermes-start` can select image-only targets for a workspace.

`hermes-open`, `hermes-shell`, `hermes-logs`, `hermes-status`, and `hermes-stop` select only existing containers for a workspace.

The current shared scripts also support explicit targeting where a picker is not desired:

- `./scripts/shared/hermes-start <workspace> <lane> <upstream>`
- `./scripts/shared/hermes-open <workspace> <lane> <upstream> [hermes args...]`

In explicit mode, the wrapper derives the deterministic container name and immutable image reference from the supplied `workspace`, `lane`, and `upstream` values together with the current wrapper context and commit identity.

Picker ordering:

- production first
- newest to oldest within production
- then test
- newest to oldest within test

Picker display shows:

- lane
- upstream
- wrapper
- commit stamp
- status

Status values are:

- target picker: `running`, `stopped`, `image only`
- container picker: `running`, `stopped`
- image removal picker: `in use`, `unused`

## Remove

Use:

- `./scripts/shared/hermes-remove container`
- `./scripts/shared/hermes-remove image`

The remove picker shows:

1. `All, but newest`
2. `All`
3. individual targets newest to oldest

`All, but newest` means:

- for containers: leave the newest container per workspace
- for images: leave the newest image per workspace where a workspace association exists through existing containers; if no image can be associated to a workspace through current containers, keep the newest image overall

## Workspace state

Each workspace uses:

- `<workspace-root>/hermes-home` for persistent Hermes state
- `<workspace-root>/workspace` for project files

Hermes runs with:

- `/opt/data` mapped to `hermes-home`
- `/workspace` mapped to the project workspace

The wrapper continues to seed missing baseline files such as:

- `.env`
- `config.yaml`
- `SOUL.md`
- `AGENTS.md`

## Matrix patch direction

For upstream `0.8.0`, the wrapper now keeps only the narrow Matrix behavior still required by policy:

- keep `apply-hermes-matrix-device-id.py`
- keep the narrow `MATRIX_ALLOWED_USERS` remainder from `apply-hermes-matrix-config-overrides.py`

Removed from the wrapper patch surface:

- `apply-hermes-matrix-upload-filesize.py`
- `apply-hermes-matrix-encrypted-media.py`
- `apply-hermes-matrix-auto-verification.py`

## Source of truth

For the full design rationale and the remaining implementation details, use:

- `docs/shared/implementation-plan.md`
