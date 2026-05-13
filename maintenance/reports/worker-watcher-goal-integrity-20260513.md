# Worker-Watcher Goal Integrity Handoff

## Managed Change

- name: worker-watcher-goal-integrity-gate
- source_class: managed-source
- owner: codex-agent-harness plus Codex-global policy docs
- exact_path: C:\Users\anise\.codex
- config_surface: managed source only; no active hook/config mutation was introduced by this pass
- dependency_chain: codex_agent_harness.py -> codex_agent_harness_base.py -> worker_watcher_templates.py -> eval definitions and templates
- scope: Codex-global workstation control plane
- risk_level: controlled-change

## Changed Surfaces

- AGENTS.md worker-watcher integrity gate policy
- maintenance/WORKER_WATCHER_NORMALIZED_HANDOFF.md
- maintenance/GOAL_INTEGRITY_GATE.md
- maintenance/templates/* handoff and gate templates
- agents/observer.toml
- skills/result-normalizer/SKILL.md
- skills/dont-even-try/SKILL.md frontmatter only
- evals/dont-even-try-integration-smoke.json
- evals/worker-watcher-normalized-handoff-smoke.json
- evals/goal-integrity-gate-smoke.json
- maintenance/scripts/codex_agent_harness_base.py
- maintenance/scripts/codex_agent_harness_lifecycle.py
- maintenance/scripts/codex_agent_harness_merge.py
- maintenance/scripts/codex_agent_harness_workflows.py
- maintenance/scripts/worker_watcher_templates.py
- .codex-harness/install-state.json

## Accepted Evidence

- `python maintenance/scripts/codex_agent_harness.py eval --eval-id dont-even-try-integration-smoke`: pass.
- `python maintenance/scripts/codex_agent_harness.py eval --eval-id worker-watcher-normalized-handoff-smoke`: pass.
- `python maintenance/scripts/codex_agent_harness.py eval --eval-id goal-integrity-gate-smoke`: pass.
- `python maintenance/scripts/codex_agent_harness.py eval`: pass.
- `python maintenance/scripts/codex_agent_harness.py verify`: pass.
- `python maintenance/scripts/codex_agent_harness.py self-test`: pass.
- `python maintenance/scripts/codex_agent_harness.py benchmark --eval-id worker-watcher-normalized-handoff-smoke`: pass.
- `powershell.exe -NoProfile -ExecutionPolicy Bypass -File maintenance/scripts/check-toolchain-sources.ps1`: pass.
- `rg.cmd --version`: pass, ripgrep 15.1.0.

## Not Run

- Live hook enforcement for missing watcher/normalizer/audit states was not changed or tested. Existing hook files already had unrelated dirty changes before this pass.
- Live subagent dispatch was not used because the current user prompt did not explicitly authorize subagents.
- Git commit, push, external publish, and active runtime config changes were not run.

## Residual Risks

- The new smoke evals are structural checks. They prove the managed source contains the required rules and templates; they do not prove every future live session will follow them.
- Hook support remains a later high-risk active-runtime change and should be handled separately after reviewing the pre-existing dirty hook edits.
- Existing unrelated dirty files remain in the worktree and were not reverted.

## Rollback

- Revert the changed Git paths from this pass, or rerun the harness apply from the previous revision.
- Harness apply created local rollback backups under `maintenance/backups/`; this directory is intentionally ignored by Git.

## Next Verification Command

```powershell
%USERPROFILE%\.codex\toolchains\shims\python.cmd %USERPROFILE%\.codex\maintenance\scripts\codex_agent_harness.py verify
```
