# Hermes Agent Wrapper Repo

This repository builds a small local image derived from the official Hermes Agent container, then runs one per-workspace runtime pod with repository-owned configuration, wrapper scripts, shell helpers, and shell tests.

## Layout

The repository uses a normalized path shape:

```text
category/subcategory/scope
```

Current layout:

```text
config/agent/shared/hermes-agent-settings-shared.conf
config/containers/shared/Containerfile
docs/usage/shared/usage.md
docs/usage/shared/architecture.md
lib/shell/shared/common.sh
scripts/agent/shared/hermes-agent-build
scripts/agent/shared/hermes-agent-run
scripts/agent/shared/hermes-agent-shell
tests/agent/shared/test-asserts.sh
tests/agent/shared/test-all.sh
tests/agent/shared/test-hermes-agent-build.sh
tests/agent/shared/test-hermes-agent-layout.sh
tests/agent/shared/test-hermes-agent-run.sh
tests/agent/shared/test-hermes-agent-shell.sh
```

## Commands

- Build the image: `scripts/agent/shared/hermes-agent-build`
- Start a configured workspace: `scripts/agent/shared/hermes-agent-run`
- Open nushell in a running workspace container: `scripts/agent/shared/hermes-agent-shell`

## Configuration

Repo-owned runtime and build settings live in:

```text
config/agent/shared/hermes-agent-settings-shared.conf
```

Container build configuration lives in:

```text
config/containers/shared/Containerfile
```

The image build starts from the official upstream `nousresearch/hermes-agent` image for `arm64` and only adds repo-local customization packages. Today that customization is `nushell` from the official Nushell Debian package source, which is the default shell opened by `hermes-agent-shell`.

Successful builds use an image-id suffix in the final local tag: `hermes-agent-<version>-<YYYYMMDD-HHMMSS>-<12-character-image-id>`.

Runtime pods use `<image-name>-<workspace>`. Role containers inside each pod use `<image-name>-<workspace>-gateway` and `<image-name>-<workspace>-dashboard`.

## Documentation

- Usage guide: `docs/usage/shared/usage.md`
- Architecture notes: `docs/usage/shared/architecture.md`
- Repository authoring rules: `AGENTS.md`

## Security Note

The wrapper starts Hermes dashboard mode with `--host 0.0.0.0` so the published Podman port can reach the containerized dashboard. The published host port is bound to `127.0.0.1` to keep that surface local by default. This is still an explicit local-development tradeoff, not a hardened deployment mode.

If a matching workspace container dies before attach, the wrapper removes it and recreates it once before failing. When startup still fails, the wrapper prints a short container state summary and recent container logs so the cause is visible immediately.

## Tests

Run the shell suite sequentially because tests temporarily rewrite the shared config file:

```text
bash tests/agent/shared/test-all.sh
```

Or run the individual checks in order:

```text
bash tests/agent/shared/test-hermes-agent-layout.sh
bash tests/agent/shared/test-hermes-agent-build.sh
bash tests/agent/shared/test-hermes-agent-run.sh
bash tests/agent/shared/test-hermes-agent-shell.sh
```
