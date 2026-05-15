# Hermes Agent Wrapper

This repository builds a small local image derived from the official Hermes Agent container, then runs one per-workspace runtime pod with repo-owned configuration, wrapper scripts, an app-local helper library, and shell tests.

## Layout

The repository follows the family layout already used across this repo:

```text
category/scope/family
```

Current layout:

```text
configs/shared/hermes-agent/hermes-agent-settings.conf
configs/shared/hermes-agent/Containerfile
docs/shared/hermes-agent/usage.md
docs/shared/hermes-agent/architecture.md
docs/shared/hermes-agent/plans/20260418-165535-config-driven-base-images.md
docs/shared/hermes-agent/plans/20260427-000000-hermes-official-gateway-command.md
scripts/shared/hermes-agent/common.sh
scripts/shared/hermes-agent/hermes-agent-build
scripts/shared/hermes-agent/hermes-agent-run
scripts/shared/hermes-agent/hermes-agent-shell
tests/shared/shared/test-asserts.sh
tests/shared/hermes-agent/test-all.sh
tests/shared/hermes-agent/test-hermes-agent-build.sh
tests/shared/hermes-agent/test-hermes-agent-layout.sh
tests/shared/hermes-agent/test-hermes-agent-run.sh
tests/shared/hermes-agent/test-hermes-agent-shell.sh
```

## Commands

- Build the image: `scripts/shared/hermes-agent/hermes-agent-build`
- Start a configured workspace: `scripts/shared/hermes-agent/hermes-agent-run`
- Open nushell in an ephemeral workspace CLI container: `scripts/shared/hermes-agent/hermes-agent-shell`

## Configuration

Repo-owned runtime and build settings live in:

```text
configs/shared/hermes-agent/hermes-agent-settings.conf
```

Container build configuration lives in:

```text
configs/shared/hermes-agent/Containerfile
```

The image build starts from the official upstream `nousresearch/hermes-agent` image for `arm64` and only adds repo-local shell tooling. It prefers the distro `nushell` package first and otherwise falls back to the configured Nushell binary version and checksums, which stays the default shell opened by `hermes-agent-shell`.

Successful builds use an image-id suffix in the final local tag: `hermes-agent-<version>-<YYYYMMDD-HHMMSS>-<12-character-image-id>`.

Runtime pods use `<image-name>-<workspace>`. Role containers inside each pod use `<image-name>-<workspace>-gateway` and `<image-name>-<workspace>-dashboard`. Interactive CLI containers use the exact name `<image-name>-<workspace>-cli`, stay outside the pod, publish no ports, and the wrapper removes stale stopped same-workspace exact-name containers before launch.

## Documentation

- Usage guide: `docs/shared/hermes-agent/usage.md`
- Architecture notes: `docs/shared/hermes-agent/architecture.md`
- Historical plans: `docs/shared/hermes-agent/plans/`
- Repository authoring rules: `AGENTS.md`

## Security Note

The wrapper starts Hermes dashboard mode with `--host 0.0.0.0` so the published Podman port can reach the containerized dashboard. The published host port is bound to `127.0.0.1` to keep that surface local by default. This is still an explicit local-development tradeoff, not a hardened deployment mode.

If a matching workspace container dies before attach, the wrapper removes it and recreates it once before failing. When startup still fails, the wrapper prints a short container state summary and recent container logs so the cause is visible immediately.

## Tests

Run the shell suite sequentially because tests temporarily rewrite the shared config file:

```text
bash tests/shared/hermes-agent/test-all.sh
```

Or run the individual checks in order:

```text
bash tests/shared/hermes-agent/test-hermes-agent-layout.sh
bash tests/shared/hermes-agent/test-hermes-agent-build.sh
bash tests/shared/hermes-agent/test-hermes-agent-run.sh
bash tests/shared/hermes-agent/test-hermes-agent-shell.sh
```
