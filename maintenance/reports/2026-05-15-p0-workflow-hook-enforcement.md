# 2026-05-15 P0 Workflow Hook Enforcement

## Scope

- Source class: managed Codex workflow/harness control plane.
- Root: `C:\Users\anise\.codex`
- Owning config: `hooks.json`, `hooks/lightweight-codex-policy.json`, `config.toml` agent role entries.
- Dependency chain: `hooks.json` -> `hooks/lightweight-codex-hook.ps1` -> `hooks/state/lightweight-status.json` -> `maintenance/scripts/codex_agent_harness.py eval --eval-id hook-policy-smoke`.

## Incident

User reported a P0 workflow failure: prompt-start and prompt-input hooks stated subagent authorization, English intent framing, goal setup, L1-L4 classification, and watcher expectations, but the PM could skip the flow without noticing. Missing GPT-5.3-Codex-Spark inspect/watcher usage was cited as evidence that the runtime behavior was not enforced.

## Root Cause

The prior hook behavior was advisory. `UserPromptSubmit` injected reminder text, but did not persist structured `taskClass`, `delegationAuthorized`, `goalRequired`, `watcherExpected`, or an English intent frame. Stop-hook readiness checked only changed surfaces and broad final-audit wording, so an L4 delegated workflow incident could finalize without subagent/watcher evidence or `WATCHER_NOT_USED`. Harness smoke coverage also focused on secret/diff guardrails and did not test the delegated P0 workflow contract.

## Changes

- `hooks/lightweight-codex-hook.ps1`
  - Adds L1-L4 prompt classification for root-cause/workflow/subagent incidents.
  - Persists structured intent and workflow fields in hook state.
  - Records `delegation_authorized` when the prompt authorizes subagents.
  - Emits an actionable PM startup packet with English intent-frame and goal/watcher actions.
  - Tracks subagent-related tool events.
  - Blocks Stop for active L4 delegated incidents unless final output includes accepted/rejected subagent evidence plus watcher coverage, or explicit `WATCHER_NOT_USED`.
- `hooks/lightweight-codex-policy.json`
  - Documents the L1-L4 runtime contract.
- `maintenance/scripts/codex_agent_harness_workflows.py`
  - Extends `hook-policy-smoke` with a behavioral P0 delegated workflow prompt.
- `evals/hook-policy-smoke.json`
  - Updates success criteria to include the new PM contract and persisted state checks.
- `skills/resolve-agent-incidents/references/incident-manual.md`
  - Adds the reusable pattern `Advisory PM Contract Without Verifiable State`.

## Verification

- PowerShell parser check for `hooks/lightweight-codex-hook.ps1`: pass.
- JSON parse for `hooks/lightweight-codex-policy.json`: pass.
- JSON parse for `evals/hook-policy-smoke.json`: pass.
- Python compile for `maintenance/scripts/codex_agent_harness_workflows.py`: pass.
- Synthetic `UserPromptSubmit` with Korean failure + hook + P0 + subagent/watcher terms:
  - emitted `task_class=L4`;
  - emitted required PM startup packet;
  - emitted English intent-frame requirement;
  - emitted goal action requirement;
  - emitted watcher action requirement;
  - persisted structured hook state.
- Synthetic Stop negative:
  - final audit wording without watcher/subagent evidence blocked.
- Synthetic Stop positive:
  - final audit with `WATCHER_NOT_USED` passed.
- `codex_agent_harness.py eval --eval-id hook-policy-smoke`: pass.
- `codex_agent_harness.py eval --eval-id worker-watcher-normalized-handoff-smoke`: pass.
- `codex_agent_harness.py eval --eval-id goal-integrity-gate-smoke`: pass.
- `codex_agent_harness.py eval --eval-id dont-even-try-integration-smoke`: pass.
- `codex_agent_harness.py eval --eval-id orchestration-governance-smoke`: pass.
- `codex_agent_harness.py doctor --json`: pass.
- `check-worktree-sensitive-diff.ps1`: pass, findings 0.
- `git diff --check`: pass; line-ending normalization warnings only.

## Not Run

- Real Codex Desktop internal subagent scheduler inspection was not run; the app does not expose that scheduler state directly to the hook.
- Full end-to-end app restart was not run; existing session loaded the edited hook script for direct synthetic samples.
- Commit/push was not run because the user did not request Git publishing for this workstation-maintenance patch.

## Residual Risk

- Hook enforcement still cannot create a Codex Goal by itself; it makes L3/L4 goal action explicit and verifiable in state/reminders.
- Actual subagent `SessionStart` payload shape remains runtime-owned. Existing Vowline injection uses representative markers; future runtime changes may require fixture updates.
- Existing unrelated dirty files remain in the worktree and were not reverted.

## Rollback

Revert the five changed control-plane files from this pass:

- `hooks/lightweight-codex-hook.ps1`
- `hooks/lightweight-codex-policy.json`
- `maintenance/scripts/codex_agent_harness_workflows.py`
- `evals/hook-policy-smoke.json`
- `skills/resolve-agent-incidents/references/incident-manual.md`

Then rerun `codex_agent_harness.py eval --eval-id hook-policy-smoke` and `codex_agent_harness.py doctor --json`.
