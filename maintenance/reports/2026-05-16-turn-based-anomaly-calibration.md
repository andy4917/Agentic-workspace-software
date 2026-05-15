# 2026-05-16 Turn-Based Anomaly Calibration

## Goal

Make workflow failure handling user-evaluable: when a hook, state file, command,
report, or final preflight contradicts the active workflow, the PM pauses the
active path, traces the first mismatch, checks overlap with existing gates, then
resumes only with direct verification or blocked/continue status.

## Problem And Risk Inventory

- Hook limits: hooks can enforce fixed checkpoints, but cannot make broad
  context-sensitive judgment.
- Agent limits: an agent can miss already-executed same-turn evidence unless a
  pause/trace rule forces a visible state transition.
- Live-state pollution: synthetic `UserPromptSubmit` smoke tests wrote the same
  `hooks/state/lightweight-status.json` consumed by real Stop hooks.
- Final-prose compensation: stale or contradictory Stop reminders could be
  satisfied by adding wording instead of tracing the control-plane mismatch.
- Duplicate process risk: Goal, Worker-Watcher, Stop hook, incident manual, and
  verification-loop already cover parts of this problem; a separate heavy gate
  would increase confusion.
- Delegation visibility risk: if the user authorizes subagents, task-class
  reminder text alone is not enough; the user needs an explicit used/not-used
  call decision.
- Code/process bloat risk: broad governance additions can exceed the user's
  requested compactness and make future failures harder to localize.

## Design Plan

1. Document the calibration contract in `AGENTS.md` where PM behavior is already
   governed.
2. Extend lightweight hook state with `anomalyPauseExpected` and an intent-frame
   `calibration_action`.
3. Emit a prompt reminder that says exactly when to pause, trace, check overlap,
   and resume.
4. Persist `subagentDecisionRequired` whenever delegation is authorized, and
   require `SUBAGENT_CALL used` or `SUBAGENT_CALL not_used` in visible evidence
   independent of task-class reminder availability.
5. Require Stop output for active anomaly-calibration incidents to mention the
   pause/trace trigger, first mismatch or root cause, verification or
   blocked/continue status, and residual risk.
6. Snapshot and restore live hook state in `hook-policy-smoke` so synthetic
   probes cannot contaminate real workflow state.
7. Record reusable incident-manual patterns for live-state pollution, missing
   subagent-call declarations, and missing turn-based anomaly calibration.
8. Keep changes within existing control surfaces rather than adding a new
   standalone gate.

## User-Perspective Pass Criteria

- The L4 workflow/harness reminder includes a calibration action.
- The persisted hook state records `anomalyPauseExpected`.
- Delegated prompts require and persist a `SUBAGENT_CALL` decision even when
  task-class reminder text is unavailable.
- Stop rejects delegated final output missing exact `SUBAGENT_CALL used` or
  `SUBAGENT_CALL not_used` with reason/evidence.
- Stop rejects active anomaly-calibration final output that lacks pause/trace
  evidence.
- `hook-policy-smoke` proves synthetic probes restore the live state.
- The final handoff maps expected behavior to observed evidence and lists
  remaining risks.

## Rollback

Revert this report and the related changes in:

- `AGENTS.md`
- `hooks/lightweight-codex-hook.ps1`
- `maintenance/scripts/codex_agent_harness_workflows.py`
- `evals/hook-policy-smoke.json`
- `skills/resolve-agent-incidents/references/incident-manual.md`

Then rerun `python maintenance/scripts/codex_agent_harness.py eval --eval-id hook-policy-smoke`.

## Known Limit

Stop-hook runtime enforcement depends on prior hook state. If that state is
missing or unparsable and Stop receives no original prompt text, the hook cannot
reconstruct explicit subagent authorization. In that path, the PM-visible
`AGENTS.md` contract is the fallback requirement.
