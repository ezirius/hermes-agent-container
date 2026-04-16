# Hermes OpenCode-Template Migration Design

## Goal

Reshape `hermes-agent-container` so it follows the `opencode-container` template for repository layout, config ownership, command surface, deterministic image and container identity, documentation, and tests, while preserving only the Hermes-specific runtime behaviour that is still required.

## Approved Architecture

`hermes-agent-container` becomes the Hermes-specific sibling of `opencode-container`, not a separate wrapper design. The repository structure, config ownership, command contracts, picker behaviour, deterministic naming, docs split, and test layout should mirror the OpenCode template unless Hermes has a concrete runtime need that requires an exception.

The wrapper keeps Hermes Agent as the installed application and preserves the current `hermes-home` and `hermes-workspace` host mounts. Hermes-native app state remains app-owned in `hermes-home`, while wrapper-owned defaults and operational constants move into `config/shared/hermes.conf` and related wrapper config files.

## Required Hermes Exceptions

The migration must preserve these Hermes-specific behaviours:

- install Hermes Agent instead of OpenCode
- keep the host workspace layout as `<workspace>/hermes-home` and `<workspace>/hermes-workspace`
- keep Hermes-native app state and file-based runtime behaviour under `/opt/data`
- keep the current Matrix patches:
  - `config/patches/apply-hermes-matrix-device-id.py`
  - `config/patches/apply-hermes-matrix-config-overrides.py`
- keep the existing non-Matrix Hermes wrapper patches unless implementation proves one is obsolete:
  - `config/patches/apply-hermes-transcription-oga.py`
  - `config/patches/apply-hermes-host-agents-context.py`
- preserve entrypoint seeding for `.env`, `config.yaml`, `SOUL.md`, and `AGENTS.md`
- preserve the host-backed `AGENTS.md` precedence behaviour already used by Hermes

## Command And Runtime Model

The shared command set remains:

- `hermes-build`
- `hermes-bootstrap`
- `hermes-start`
- `hermes-open`
- `hermes-shell`
- `hermes-logs`
- `hermes-status`
- `hermes-stop`
- `hermes-remove`

Command behaviour follows the OpenCode template:

- workspace-facing commands support omitted `<workspace>` values via an alphabetical picker
- `--` is used to disambiguate omitted-workspace flows and trailing application arguments
- `hermes-build` resolves lane first, then runs lane-specific checks, then resolves or prompts for upstream
- image tags are immutable and containers are deterministic
- `hermes-bootstrap` selects once and reuses the same resolved target through start and open
- `hermes-start` can choose image-only or existing-container targets
- `hermes-open`, `hermes-shell`, `hermes-logs`, `hermes-status`, and `hermes-stop` operate on existing containers only

## Config Rules

Wrapper-owned defaults and operational constants belong in config files, not shell logic. `config/shared/hermes.conf` becomes the canonical wrapper config file and must own path layout, label keys, lane names, upstream selectors, restart policy, container runtime paths, and wrapper-managed port settings.

Managed config files must include example entries for all supported config values so the full config surface is discoverable from the files themselves. Wrapper-managed ports are disabled by default. No port may be bound, published, or exposed unless that port is explicitly configured. When a port setting is included in example config, it must use the real Hermes application port rather than a placeholder.

## Pinned Version Policy

Pinned wrapper-owned defaults must follow the global `AGENTS.md` rule:

- every build, installation, and upgrade checks whether a newer suitable version exists
- if a pin is behind, the user is asked every time whether to keep the current pin, update the config pin and continue, or cancel
- if the user chooses the newer version, the config pin is updated first and the current workflow uses that updated pin
- if the newer version is not selected, the workflow continues with the current pin or cancels

This applies to all wrapper-owned pinned versions, including Ubuntu LTS, Node LTS, Hermes upstream defaults if pinned, and any pinned wrapper-managed tools.

## Documentation And Testing

`README.md` and `docs/shared/usage.md` are the current behaviour source of truth. `docs/shared/implementation-plan.md` becomes historical reference only.

The test suite should follow the OpenCode template structure:

- repository layout and invariant tests
- helper and parsing tests
- mocked runtime and lifecycle tests
- optional real smoke-build tests

Hermes-specific tests remain for entrypoint seeding, patch application, ref resolution, and any Hermes-only runtime contract that the template does not cover directly.
