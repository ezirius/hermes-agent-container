# Hermes Official Gateway Command Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Hermes gateway role container run the official upstream `gateway run` command instead of an idle placeholder command.

**Architecture:** Keep the existing workspace pod and role-container model. The dashboard role remains a dashboard process, while the gateway role becomes the official long-running gateway process inherited through the upstream image entrypoint. Shell access continues to exec into the running gateway container.

**Tech Stack:** Bash wrapper scripts, Podman CLI, shell behavior tests with fake Podman commands.

---

### Task 1: Lock Official Gateway Runtime Contract

**Files:**
- Modify: `tests/agent/shared/test-hermes-agent-run.sh`
- Modify: `scripts/agent/shared/hermes-agent-run`

- [ ] **Step 1: Write the failing test**

In `tests/agent/shared/test-hermes-agent-run.sh`, update the normal-run assertions near the existing gateway role checks so they require the gateway role container to start with `gateway run` and forbid the placeholder command:

```bash
assert_file_contains 'run -d --name hermes-agent-0.10.0-20260417-120000-abcdef123456-beta-gateway' "$PODMAN_LOG" 'run should create a gateway role container for the workspace'
assert_file_contains 'gateway run' "$PODMAN_LOG" 'run should start the gateway role with the official Hermes gateway command'
assert_file_not_contains 'sleep infinity' "$PODMAN_LOG" 'run should not keep the gateway role alive with a placeholder command'
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
bash tests/agent/shared/test-hermes-agent-run.sh
```

Expected: `FAIL` because the fake Podman log currently contains `sleep infinity`, and it does not contain `gateway run` for the gateway role container.

- [ ] **Step 3: Write minimal implementation**

In `scripts/agent/shared/hermes-agent-run`, replace the gateway container command in `create_gateway_container()`:

```bash
    "$image_name" \
    gateway run)"
```

The complete final command tail should be:

```bash
    "$image_name" \
    gateway run)"
```

with no `sleep infinity` command remaining.

- [ ] **Step 4: Run targeted test to verify it passes**

Run:

```bash
bash tests/agent/shared/test-hermes-agent-run.sh
```

Expected: `hermes-agent-run behavior checks passed`.

- [ ] **Step 5: Run full suite**

Run:

```bash
bash tests/agent/shared/test-all.sh
```

Expected: all Hermes wrapper checks pass.

- [ ] **Step 6: Leave changes uncommitted**

Run:

```bash
git status --short
```

Expected: only the plan, test, and run script changes appear unless pre-existing user changes are present.
