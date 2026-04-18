# Hermes Agent Wrapper Repo

This repository builds and runs a local Hermes Agent container with repository-owned configuration, wrapper scripts, shell helpers, and shell tests.

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
tests/agent/shared/test-hermes-agent-build.sh
tests/agent/shared/test-hermes-agent-layout.sh
tests/agent/shared/test-hermes-agent-run.sh
tests/agent/shared/test-hermes-agent-shell.sh
```

## Commands

- Build the image: `scripts/agent/shared/hermes-agent-build`
- Start a configured workspace: `scripts/agent/shared/hermes-agent-run`
- Open a shell in a running workspace container: `scripts/agent/shared/hermes-agent-shell`

## Configuration

Repo-owned runtime and build settings live in:

```text
config/agent/shared/hermes-agent-settings-shared.conf
```

Container build configuration lives in:

```text
config/containers/shared/Containerfile
```

The image build compiles the upstream Hermes frontend and bundles the resulting `hermes_cli/web_dist` assets into the runtime image before the Hermes package install. Without those built assets, the Hermes dashboard cannot serve the portal files and falls back to its missing-frontend error path.

## Documentation

- Usage guide: `docs/usage/shared/usage.md`
- Architecture notes: `docs/usage/shared/architecture.md`
- Repository authoring rules: `AGENTS.md`

## Security Note

The wrapper currently starts `hermes dashboard` with `--host 0.0.0.0 --insecure` so the published Podman port can reach the containerized dashboard. The published host port is bound to `127.0.0.1` to keep that surface local by default. This is still an explicit local-development tradeoff, not a hardened deployment mode.

If a matching workspace container dies before attach, the wrapper removes it and recreates it once before failing. When startup still fails, the wrapper prints a short container state summary and recent container logs so the cause is visible immediately.

## Tests

Run the shell suite sequentially because tests temporarily rewrite the shared config file:

```text
bash tests/agent/shared/test-hermes-agent-layout.sh
bash tests/agent/shared/test-hermes-agent-build.sh
bash tests/agent/shared/test-hermes-agent-run.sh
bash tests/agent/shared/test-hermes-agent-shell.sh
```
