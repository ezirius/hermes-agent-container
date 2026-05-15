# AGENTS

This file defines the repository structure, naming rules, and safe-editing rules for agents changing this repo.

## Core Shape

- Canonical directory shape is `category/scope/family`.
- `category` is the top-level bucket.
- `scope` describes OS applicability only.
- `family` is the product or functional family inside that category.

## Allowed Scope Values

- `shared`
- `macos`
- `linux`

Meaning:

- `shared` means the content applies to both macOS and Linux.
- `macos` means the content is macOS-only.
- `linux` means the content is Linux-only.

## Scope Versus Host

- Directory `scope` is about OS applicability.
- Filename host tokens are about machine applicability.
- A specific host, such as `maldoria`, does not become a directory scope.
- Host-specific files still live under `shared`, `macos`, or `linux` based on OS applicability.

## Categories

Common categories in this repo are:

- `configs`
- `scripts`
- `tests`
- `docs`
- `lib`

## Current Repo Paths

Use the existing family path that best fits the content.

Current repo paths in active use are:

- `configs/shared/hermes-agent/...`
- `docs/shared/hermes-agent/...`
- `scripts/shared/hermes-agent/...`
- `tests/shared/hermes-agent/...`
- `tests/shared/shared/...`
- `docs/shared/hermes-agent/plans/...`

Do not split one product family across several ad hoc subcategories when one family directory fits.

## Config Filename Rule

The special filename convention applies only to files under `configs`.

Format:

```text
<family>-<filejob>.<ext>
```

Rules:

- `filejob` describes what the file does, not an internal object name.
- Prefer descriptive `filejob` terms such as `settings`, `runtime`, `packages`, or `service`.

Examples:

- `configs/shared/hermes-agent/hermes-agent-settings.conf`
- `configs/shared/podman/podman-machine-settings.conf`
- `configs/macos/podman/podman-runtime.conf`
- `configs/shared/caddy/Caddyfile`
- `configs/shared/brew/brew-packages.Brewfile`

## Script Naming Rule

- Scripts are not renamed by the config filename convention.
- Keep executable names meaningful and stable.
- Current script names are:
  - `hermes-agent-build`
  - `hermes-agent-run`
  - `hermes-agent-shell`

## Special Filename Exceptions

These basenames are exceptions to the config naming pattern when appropriate:

- `Containerfile`
- root metadata files such as `README.md` and `AGENTS.md`
- timestamped superpowers planning documents

## Planning Documents

- Historical and planning documents for this app belong under `docs/shared/hermes-agent/plans/`.
- Timed or date-dependent document names must start with `YYYYMMDD-HHMMSS-`.
- Example:

```text
docs/shared/hermes-agent/plans/20260417-104635-hermes-agent-layout-migration.md
```

## Required Comment Rules

- Shell-facing files under `scripts`, `lib`, and `tests` must explain themselves with comments.
- Each file must have a short header comment near the top.
- Each function must have a short comment directly above it.
- Each non-trivial block must have a short comment directly above it.
- Comment tone must be simple, friendly, and professional.
- Explain purpose and behavior, not obvious syntax.
- Avoid noisy comments like "set a variable" or childish phrasing.

## Current Canonical Paths

Current stable paths in this repo are:

- `configs/shared/hermes-agent/hermes-agent-settings.conf`
- `configs/shared/hermes-agent/Containerfile`
- `docs/shared/hermes-agent/usage.md`
- `docs/shared/hermes-agent/architecture.md`
- `scripts/shared/hermes-agent/common.sh`
- `scripts/shared/hermes-agent/hermes-agent-build`
- `scripts/shared/hermes-agent/hermes-agent-run`
- `scripts/shared/hermes-agent/hermes-agent-shell`
- `tests/shared/shared/test-asserts.sh`
- `tests/shared/hermes-agent/test-all.sh`
- `tests/shared/hermes-agent/test-hermes-agent-build.sh`
- `tests/shared/hermes-agent/test-hermes-agent-layout.sh`
- `tests/shared/hermes-agent/test-hermes-agent-run.sh`
- `tests/shared/hermes-agent/test-hermes-agent-shell.sh`

## Root Files

- Keep `README.md` at the repository root.
- Keep `AGENTS.md` at the repository root.
- These are the only expected root documentation files in the current repo layout.

## Cleanup Rules

- Do not leave obsolete empty directories behind after moves.
- Remove old category paths once their contents have been relocated.
- Update all references, tests, and layout assertions in the same change set as the move.

## Current Behavioral Rules

- Repo-owned runtime and build settings live in `configs/shared/hermes-agent/hermes-agent-settings.conf`.
- Container build configuration lives in `configs/shared/hermes-agent/Containerfile` and derives from the official upstream Hermes Agent image.
- App-local shell helpers live in `scripts/shared/hermes-agent/common.sh`.
- User-facing documentation and retained plans live under `docs/shared/hermes-agent/`.
- Shell tests live in `tests/shared/hermes-agent/`.
- The shell tests mutate the shared config file during execution, so they must be run sequentially.
- `scripts/shared/hermes-agent/hermes-agent-build` must only build from a clean, committed checkout.
- `scripts/shared/hermes-agent/hermes-agent-build` requires main to track `origin/main` and prints `Build requires main to be pushed and in sync with origin/main` when ahead, behind, or diverged.
- Non-main remote-tracking branches must not be used for builds; use a clean committed local worktree branch or main tracking `origin/main`.
- Local image names must include the 12-character image-id suffix after the timestamp.
- Hermes container and pod names follow the OpenCode-derived `<image-name>-<workspace>` order.
- Meaningful tracked changes, meaningful untracked files, and executable-bit changes all count as dirty for build safety.
- Harmless host junk such as `.DS_Store` should not count as a dirty checkout by itself.
- `scripts/shared/hermes-agent/hermes-agent-run` must only remove older workspace pods and containers after the replacement container is running.
- `scripts/shared/hermes-agent/hermes-agent-run` must use `--userns keep-id` for non-root runtime containers and repair mounted host path ownership while skipping rootless `keep-id` mode when launched as root.
- `scripts/shared/hermes-agent/hermes-agent-run` delegates first-run setup and state bootstrapping to the upstream Hermes entrypoint.
- Hermes pod names follow `<image-name>-<workspace>`; role containers inside the pod use `<image-name>-<workspace>-gateway` and `<image-name>-<workspace>-dashboard`, and infra containers use `<image-name>-<workspace>-infrastructure`.
- Interactive CLI containers use the exact name `<image-name>-<workspace>-cli`, share the same `/opt/data` and `/workspace/docs` mounts as the persistent runtime, do not join the workspace pod, do not publish ports, and may only remove stale stopped same-workspace exact-name containers.
- Shared interactive Podman exec behavior lives in `scripts/shared/hermes-agent/common.sh` and must preserve non-TTY stdin behavior as well as interactive-host behavior.
- `tests/shared/hermes-agent/test-hermes-agent-layout.sh` is the layout guard for the normalized repository structure and key headline comments.

## Current Implementation Notes

- Container lookup and stale cleanup are workspace-scoped across Hermes image versions in the app-local helper library.
- Version-bump work should review `scripts/shared/hermes-agent/common.sh`, `scripts/shared/hermes-agent/hermes-agent-run`, and `scripts/shared/hermes-agent/hermes-agent-shell` carefully so older workspace containers do not become unmanaged or invisible by accident.
- Treat these notes as current implementation constraints, not as the ideal long-term design.
