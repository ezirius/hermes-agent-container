# Config-Driven Base Images Implementation Plan

> Historical note: this plan is retained for context and does not describe the current Hermes runtime architecture. Current behavior derives from the official upstream Hermes Agent image and is documented in `docs/usage/shared/architecture.md`.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move the pinned Node and Ubuntu base image references into the shared repo config so the build stays reviewable, pinned, and configurable from one place.

**Architecture:** The shared config will own two full image references: one for the frontend builder stage and one for the runtime stage. The build script will pass them as build args, and the `Containerfile` will consume those args in its `FROM` lines so the final image shape remains config-driven.

**Tech Stack:** Bash, Podman/Containerfile, shell tests

---

### Task 1: Add failing tests for config-driven base images

**Files:**
- Modify: `tests/agent/shared/test-hermes-agent-build.sh`
- Modify: `tests/agent/shared/test-hermes-agent-layout.sh`
- Test: `tests/agent/shared/test-hermes-agent-build.sh`

- [ ] **Step 1: Write the failing tests**

Add assertions for these behaviors:

```bash
assert_file_contains '--build-arg HERMES_AGENT_NODE_IMAGE=node:22-bookworm-slim' "$PODMAN_LOG" 'build should pass the configured Node base image to the container build'
assert_file_contains '--build-arg HERMES_AGENT_RUNTIME_IMAGE=ubuntu:24.04' "$PODMAN_LOG" 'build should pass the configured runtime base image to the container build'
assert_file_contains 'ARG HERMES_AGENT_NODE_IMAGE' "$ROOT/config/containers/shared/Containerfile" 'container build should declare the configured Node base image arg'
assert_file_contains 'ARG HERMES_AGENT_RUNTIME_IMAGE' "$ROOT/config/containers/shared/Containerfile" 'container build should declare the configured runtime base image arg'
assert_file_contains 'FROM ${HERMES_AGENT_NODE_IMAGE} AS hermes-web-builder' "$ROOT/config/containers/shared/Containerfile" 'frontend builder should use the configured Node base image'
assert_file_contains 'FROM ${HERMES_AGENT_RUNTIME_IMAGE}' "$ROOT/config/containers/shared/Containerfile" 'runtime image should use the configured runtime base image'
```

Add layout assertions for the new config keys:

```bash
grep -q '^HERMES_AGENT_NODE_IMAGE="node:22-bookworm-slim"$' "$ROOT/config/agent/shared/hermes-agent-settings-shared.conf"
grep -q '^HERMES_AGENT_RUNTIME_IMAGE="ubuntu:24.04"$' "$ROOT/config/agent/shared/hermes-agent-settings-shared.conf"
```

- [ ] **Step 2: Run the failing test**

Run: `bash tests/agent/shared/test-hermes-agent-build.sh`
Expected: FAIL because the build script and `Containerfile` do not yet carry the new image settings.

### Task 2: Implement config-driven pinned base images

**Files:**
- Modify: `config/agent/shared/hermes-agent-settings-shared.conf`
- Modify: `scripts/agent/shared/hermes-agent-build`
- Modify: `config/containers/shared/Containerfile`
- Test: `tests/agent/shared/test-hermes-agent-build.sh`

- [ ] **Step 1: Add the pinned image refs to shared config**

Add:

```bash
HERMES_AGENT_NODE_IMAGE="node:22-bookworm-slim"
HERMES_AGENT_RUNTIME_IMAGE="ubuntu:24.04"
```

- [ ] **Step 2: Pass the config through the build script**

Extend the `podman build` invocation with:

```bash
  --build-arg HERMES_AGENT_NODE_IMAGE="$HERMES_AGENT_NODE_IMAGE" \
  --build-arg HERMES_AGENT_RUNTIME_IMAGE="$HERMES_AGENT_RUNTIME_IMAGE" \
```

- [ ] **Step 3: Consume the build args in the Containerfile**

Add these declarations before the stage `FROM` lines and switch both stages to use them:

```Dockerfile
ARG HERMES_AGENT_NODE_IMAGE
FROM ${HERMES_AGENT_NODE_IMAGE} AS hermes-web-builder

ARG HERMES_AGENT_RUNTIME_IMAGE
FROM ${HERMES_AGENT_RUNTIME_IMAGE}
```

- [ ] **Step 4: Re-run the tests**

Run: `bash tests/agent/shared/test-hermes-agent-build.sh`
Expected: PASS

### Task 3: Verify the repo guards still pass

**Files:**
- Test: `tests/agent/shared/test-hermes-agent-layout.sh`
- Test: `tests/agent/shared/test-hermes-agent-build.sh`

- [ ] **Step 1: Run the layout test**

Run: `bash tests/agent/shared/test-hermes-agent-layout.sh`
Expected: PASS

- [ ] **Step 2: Run the build test again**

Run: `bash tests/agent/shared/test-hermes-agent-build.sh`
Expected: PASS
