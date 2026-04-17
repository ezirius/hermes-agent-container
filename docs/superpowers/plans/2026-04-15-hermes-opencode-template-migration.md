# Hermes OpenCode-Template Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild `hermes-agent-container` so it follows the `opencode-container` template while preserving Hermes Agent installation, the `hermes-home` and `hermes-workspace` layout, the current wrapper patches, and the repeat-on-every-run pinned-version prompt policy.

**Architecture:** Replace the current Hermes wrapper foundation with an OpenCode-template-shaped config, shell, command, documentation, and test structure. Re-merge only the Hermes-specific runtime, patch, and entrypoint behaviour that is still required. Keep current behaviour documentation in `README.md` and `docs/shared/usage.md`, and move historical rationale to `docs/shared/implementation-plan.md`.

**Tech Stack:** Bash, Podman, shell test scripts, Python patch scripts, Ubuntu wrapper images.

---

### Task 1: Rebase Shared Config And Shell Foundation

**Files:**
- Modify: `config/shared/hermes.conf`
- Create: `config/shared/tool-versions.conf`
- Modify: `lib/shell/common.sh`
- Test: `tests/shared/test-common.sh`
- Test: `tests/shared/test-args.sh`

- [ ] Write failing foundation tests for the new config-owned operational constants, omitted-workspace picker flow, and repeat-on-every-run version prompt behaviour.
- [ ] Run the targeted shared tests and confirm they fail for the expected missing-template behaviour.
- [ ] Rebuild `config/shared/hermes.conf` and add `config/shared/tool-versions.conf` so wrapper constants and pinned versions live in config rather than shell logic.
- [ ] Replace `lib/shell/common.sh` with an OpenCode-template-shaped foundation adapted for Hermes naming, paths, runtime rules, and preserved Hermes helpers.
- [ ] Re-run the targeted shared tests until they pass.

### Task 2: Rebuild The Container Runtime Layer

**Files:**
- Replace: `config/containers/Dockerfile`
- Create: `config/containers/Containerfile.wrapper`
- Create: `config/containers/Containerfile.source-base.template`
- Modify: `config/containers/entrypoint.sh`
- Test: `tests/shared/test-entrypoint.sh`
- Test: `tests/shared/test-patches.sh`

- [ ] Write failing tests for the template-style runtime container contract, preserved Hermes entrypoint seeding, and patch application expectations.
- [ ] Run the targeted entrypoint and patch tests and confirm they fail for the expected missing-template runtime shape.
- [ ] Replace the old container build definition with an OpenCode-template-style wrapper Containerfile and source-build template adapted for Hermes installation, Ubuntu and Node pinning, and the preserved patch pipeline.
- [ ] Update the entrypoint only as needed to fit the new template while preserving Hermes file seeding and AGENTS precedence behaviour.
- [ ] Re-run the targeted runtime tests until they pass.

### Task 3: Rework The Shared Commands

**Files:**
- Modify: `scripts/shared/hermes-build`
- Modify: `scripts/shared/hermes-bootstrap`
- Modify: `scripts/shared/hermes-start`
- Modify: `scripts/shared/hermes-open`
- Modify: `scripts/shared/hermes-shell`
- Modify: `scripts/shared/hermes-logs`
- Modify: `scripts/shared/hermes-status`
- Modify: `scripts/shared/hermes-stop`
- Modify: `scripts/shared/hermes-remove`
- Test: `tests/shared/test-runtime.sh`
- Test: `tests/shared/test-ref-resolution.sh`

- [ ] Write failing command and runtime tests for omitted-workspace selection, `--` disambiguation, template-style lane-first build flow, disabled-by-default ports, and Hermes-specific preserved runtime semantics.
- [ ] Run the targeted runtime and ref-resolution tests and confirm they fail for the expected old-command behaviour.
- [ ] Replace the Hermes shared scripts with OpenCode-template-shaped entrypoints adapted for Hermes names, runtime calls, and preserved Hermes semantics.
- [ ] Implement the every-run pinned-version prompt flow for all wrapper-owned pins used by build, installation, and upgrade workflows.
- [ ] Re-run the targeted command tests until they pass.

### Task 4: Rebaseline Documentation And Full Verification

**Files:**
- Modify: `README.md`
- Modify: `docs/shared/usage.md`
- Modify: `docs/shared/implementation-plan.md`
- Modify: `tests/shared/test-all.sh`
- Modify: `tests/shared/test-layout.sh`
- Modify: `tests/shared/test-build-smoke.sh`

- [ ] Write failing layout and docs-alignment tests for the new template-shaped repository contract and current-behaviour documentation rules.
- [ ] Run the targeted layout test and confirm it fails for the expected outdated repository contract.
- [ ] Rewrite the docs and final verification scripts so the current behaviour, config examples, ports policy, and preserved Hermes exceptions are documented accurately.
- [ ] Run `tests/shared/test-all.sh` and any required targeted smoke checks until the full suite reflects the new template-shaped wrapper.
- [ ] Review the final diff for leftover old-model behaviour or documentation drift and remove any remaining divergence that is not required by Hermes.
