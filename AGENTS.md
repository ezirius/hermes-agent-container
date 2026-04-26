# AGENTS

This file defines the repository structure, naming rules, and safe-editing rules for agents creating or reorganizing content in this repo.

## Core Shape

- Canonical directory shape is `category/subcategory/scope`.
- `category` is the top-level bucket.
- `subcategory` is the functional family inside that category.
- `scope` describes OS applicability only.

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

- `config`
- `scripts`
- `tests`
- `docs`
- `lib`

## Canonical Subcategories For This Repo

Use the most specific functional family that fits the content.

Current canonical subcategories in this repo are:

- `config/agent/...`
- `config/containers/...`
- `scripts/agent/...`
- `tests/agent/...`
- `docs/usage/...`
- `lib/shell/...`

Future-facing subcategories, only when needed, are:

- `docs/plans/...`
- `docs/specs/...` if plans and designs are split later

Do not reuse the application name as a generic subcategory when a stronger functional family exists.

## Config Filename Rule

The special filename convention applies only to files under `config`.

Format:

```text
<subcategory>-<filejob>-<host>.<ext>
```

Rules:

- `filejob` describes what the file does, not an internal object name.
- `host` is `shared` for all hosts in that OS scope, or a hostname token for one machine.
- Prefer descriptive `filejob` terms such as `settings`, `runtime`, `packages`, `service`, or `machine-settings`.

Examples:

- `config/agent/shared/hermes-agent-settings-shared.conf`
- `config/podman/macos/podman-machine-settings-shared.conf`
- `config/podman/macos/podman-runtime-settings-maldoria.conf`
- `config/caddy/shared/caddy-runtime-shared.Caddyfile`
- `config/brew/shared/brew-packages-shared.Brewfile`

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

## Superpowers Documents

- Superpowers planning documents belong under `docs/plans/<scope>/`.
- Timed or date-dependent document names must start with `YYYYMMDD-HHMMSS-`.
- Example:

```text
docs/plans/shared/20260417-104635-hermes-agent-layout-migration.md
```

- If future design documents are kept separately from plans, place them in a separate sibling subcategory such as `docs/specs/<scope>/`.

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

- `config/agent/shared/hermes-agent-settings-shared.conf`
- `config/containers/shared/Containerfile`
- `docs/usage/shared/usage.md`
- `docs/usage/shared/architecture.md`
- `lib/shell/shared/common.sh`
- `scripts/agent/shared/hermes-agent-build`
- `scripts/agent/shared/hermes-agent-run`
- `scripts/agent/shared/hermes-agent-shell`
- `tests/agent/shared/test-asserts.sh`
- `tests/agent/shared/test-hermes-agent-build.sh`
- `tests/agent/shared/test-hermes-agent-layout.sh`
- `tests/agent/shared/test-hermes-agent-run.sh`
- `tests/agent/shared/test-hermes-agent-shell.sh`

## Root Files

- Keep `README.md` at the repository root.
- Keep `AGENTS.md` at the repository root.
- These are the only expected root documentation files in the current repo layout.

## Cleanup Rules

- Do not leave obsolete empty directories behind after moves.
- Remove old category paths once their contents have been relocated.
- Update all references, tests, and layout assertions in the same change set as the move.

## Current Behavioral Rules

- Repo-owned runtime and build settings live in `config/agent/shared/hermes-agent-settings-shared.conf`.
- Container build configuration lives in `config/containers/shared/Containerfile` and derives from the official upstream Hermes Agent image.
- Shared shell helpers live in `lib/shell/shared/common.sh`.
- User-facing documentation lives in `docs/usage/shared/`.
- Shell tests live in `tests/agent/shared/`.
- The shell tests mutate the shared config file during execution, so they must be run sequentially.
- `scripts/agent/shared/hermes-agent-build` must only build from a clean, committed checkout.
- `scripts/agent/shared/hermes-agent-build` requires main to track `origin/main` and prints `Build requires main to be pushed and in sync with origin/main` when ahead, behind, or diverged.
- Non-main remote-tracking branches must not be used for builds; use a clean committed local worktree branch or main tracking `origin/main`.
- Local image names must include the 12-character image-id suffix after the timestamp.
- Hermes container and pod names follow the OpenCode-derived `<image-name>-<workspace>` order.
- Meaningful tracked changes, meaningful untracked files, and executable-bit changes all count as dirty for build safety.
- Harmless host junk such as `.DS_Store` should not count as a dirty checkout by itself.
- `scripts/agent/shared/hermes-agent-run` must only remove older workspace pods and containers after the replacement container is running.
- `scripts/agent/shared/hermes-agent-run` must use `--userns keep-id` for non-root runtime containers and repair mounted host path ownership while skipping rootless `keep-id` mode when launched as root.
- `scripts/agent/shared/hermes-agent-run` delegates first-run setup and state bootstrapping to the upstream Hermes entrypoint.
- Shared interactive Podman exec behavior lives in `lib/shell/shared/common.sh` and must preserve non-TTY stdin behavior as well as interactive-host behavior.
- `tests/agent/shared/test-hermes-agent-layout.sh` is the layout guard for the normalized repository structure and key headline comments.

## Current Implementation Notes

- Container lookup and stale cleanup are workspace-scoped across Hermes image versions in the shared shell helpers.
- Version-bump work should review `lib/shell/shared/common.sh`, `scripts/agent/shared/hermes-agent-run`, and `scripts/agent/shared/hermes-agent-shell` carefully so older workspace containers do not become unmanaged or invisible by accident.
- Treat these notes as current implementation constraints, not as the ideal long-term design.
