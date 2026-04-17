# AGENTS

This file defines the repository structure and naming rules for agents creating or reorganizing content in this repo.

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

## Category Meaning

Examples of categories:

- `config`
- `scripts`
- `tests`
- `docs`
- `lib`

## Preferred Subcategories

Use the most specific functional family that fits the content.

Current preferred subcategories in this repo:

- `config/agent/...`
- `config/containers/...`
- `scripts/agent/...`
- `tests/agent/...`
- `docs/usage/...`
- `docs/plans/...`
- `lib/shell/...`

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

## Root Files

- Keep `README.md` at the repository root.
- Keep `AGENTS.md` at the repository root.

## Cleanup Rules

- Do not leave obsolete empty directories behind after moves.
- Remove old category paths once their contents have been relocated.
- Update all references, tests, and layout assertions in the same change set as the move.

## Working Rules For This Repo

- Repo-owned runtime and build settings live in `config/agent/shared/hermes-agent-settings-shared.conf`.
- Container build configuration lives in `config/containers/shared/Containerfile`.
- Shared shell helpers live in `lib/shell/shared/common.sh`.
- User-facing documentation lives in `docs/usage/shared/`.
- Shell tests live in `tests/agent/shared/`.
- The shell tests mutate the shared config file during execution, so they must be run sequentially.
