# Skill, Plugin Cache, And Hook-Level Simplification

Date: 2026-05-16 KST
Scope: `%USERPROFILE%\.codex` tracked skill scripts, lightweight hook workflow
classification, and plugin-cache compatibility classification.

## Objective

Reduce oversized tracked skill scripts, make PreToolUse and PostToolUse capable
of raising task level from direct tool evidence, require compatibility impact
review for control-plane changes, and preserve existing workflow/toolchain/MCP
boundaries.

## Simplified Tracked Skill Scripts

- `skills/ui-ux-pro-max/scripts/design_system.py` was split into:
  - `design_system_core.py`
  - `design_system_format.py`
  - `design_system_persistence.py`
- `skills/keep-codex-fast/scripts/keep_codex_fast.py` was split into:
  - `keep_codex_fast_core.py`
  - `keep_codex_fast_inspection.py`
- `skills/.system/imagegen/scripts/image_gen.py` was split into:
  - `image_gen_batch.py`
  - `image_gen_files.py`

All tracked `.codex` skill scripts are under the 800-line workspace script
limit after the split.

## Plugin Cache Handling

Large files under `plugins/cache` are ignored runtime cache material. The
workflow now classifies large plugin-cache files separately instead of treating
them as owned source to force-track or rewrite. This preserves upstream plugin
compatibility while still making the cache size visible in `doctor` output.

Current classified cache large files:

- `plugins/cache/openai-bundled/chrome/0.1.7/skills/chrome/SKILL.md`
- `plugins/cache/openai-primary-runtime/presentations/26.506.11943/skills/presentations/scripts/run_prompt_battle.mjs`

`plugins/cache/**/node_modules/**` is external dependency material and remains
excluded from simplification/refactor actions.

## Hook Workflow Change

- `PreToolUse` can raise stored task class when a pending tool call targets
  workflow, hook, harness, toolchain, MCP, debugger-tool, skill script, plugin
  cache, or large-change surfaces.
- `PostToolUse` can raise stored task class from actual file/line change
  evidence and can raise to L4 when incident/root-cause language intersects
  governance surfaces.
- Tool-stage adjustment only raises task level. It never lowers task level and
  never grants completion authority.
- Compatibility review is now a required reminder for control-plane or
  multi-surface changes.

## Compatibility Impact

Affected surfaces:

- `hooks/lightweight-codex-hook.ps1`
- `hooks/lib/lightweight-codex-workflow.ps1`
- `hooks/lightweight-codex-policy.json`
- `maintenance/scripts/codex_agent_harness_status.py`
- `maintenance/scripts/codex_agent_harness_smoke.py`
- `AGENTS.md`
- `maintenance/PROJECT_WORKFLOW_CHAIN.md`
- the three tracked skill script groups listed above

Existing safety boundaries preserved:

- secret/destructive/fake-success PreToolUse blocks are unchanged;
- UserPromptSubmit remains the primary initial classifier;
- tool-stage classification is additive and evidence-only;
- plugin cache remains ignored runtime material, not active source;
- Memento remains support-only and not completion authority.

## Direct Checks

Use these as the minimum verification set:

- Python compile for split skill and harness modules.
- PowerShell AST parse for lightweight hook files.
- `codex_agent_harness.py eval --eval-id hook-policy-smoke`.
- `codex_agent_harness.py benchmark --eval-id hook-policy-smoke`.
- `codex_agent_harness.py doctor --json`.
- `codex_agent_harness.py verify`.
- `maintenance/scripts/check-toolchain-sources.ps1`, including debugger
  availability checks for `gdb`, `cdb`, `python-pdb`, `debugpy`, `rust-gdb`,
  and `rust-lldb`.
- Direct CLI smoke tests for the split `image_gen.py`, `keep_codex_fast.py`,
  and `design_system.py` entry points.
- `git diff --check`.

## Rollback

Revert the commit containing this report to restore the previous monolithic
skill script layout and hook-level adjustment behavior. The change does not
modify secrets, external services, persistent PATH, or package dependencies.
