# ROOT_CAUSE_REPORT.latest

Checked at UTC: 2026-05-08T17:04:31.2111619Z  
Local clock context: 2026-05-09T02:04:31+09:00 KST  
Scope: P0 Harness V2 / PM orchestration remediation in `C:\Users\anise\.codex\Dev_Codex_App_GlobalSSOT`

## 1. Failing Check

The after-P0 runtime ledger audit still shows the original decisive runtime failure:

| Check | Value |
|---|---:|
| worker-required turns | 27 |
| canonical `worker_spawn_event` | 0 |
| canonical `worker_report_event` lifecycle | 0 |
| inspector-only worker-required turns | 2 |
| live Stop `required_worker_not_spawned` | 0 |
| live Stop `inspector_only_delegation_for_mutating_task` | 0 |

## 2. Expected Behavior

For Class 2/3/4 mutating or control-plane tasks, completion may only progress when a required worker route has canonical runtime evidence:

- `worker_spawn_event` with `schema_version=subagent_lifecycle_event.v1`
- `agent_role=worker`
- `authority=candidate_artifact_only`
- non-empty `parent_turn_id`, `attempt_id`, `job_id`, and `route_id`
- route/job-level PM decision before route satisfaction

If that evidence is missing, Stop should surface `required_worker_not_spawned` or `inspector_only_delegation_for_mutating_task` before generic `direct_evidence_missing`.

## 3. Actual Behavior

The P0 patch now enforces the expected code path in tests, but the existing runtime ledger remains historical evidence with no canonical worker spawn. `final_acceptance_result.json` is now fresh and synchronized with the latest command output, but it is still candidate evidence, not completion authority.

Current gate-issued receipt is still:

```text
state: candidate
decision: NOT_ISSUED_FOR_NEW_PROMPT
reason: user_prompt_submit_invalidated_previous_gate_receipt
```

## 4. Canonical Evidence Inspected

- `Settings/Codex_App_RUNTIME/subagent_worker_jobs.jsonl`
- `Settings/Codex_App_RUNTIME/subagent_worker_reports.jsonl`
- `Settings/Codex_App_RUNTIME/subagent_lifecycle_events.jsonl`
- `Settings/Codex_App_RUNTIME/pm_decisions.jsonl`
- `Settings/Codex_App_RUNTIME/gate_issued_completion_receipt.json`
- `Maintenance/hook_invocations.jsonl`
- `Maintenance/harness-v2/final_acceptance_result.json`

## 5. Missing Evidence

- No canonical `worker_spawn_event` exists in the inspected lifecycle ledger.
- No canonical `worker_report_event` lifecycle exists.
- No post-P0 live Stop denial has yet surfaced `required_worker_not_spawned` or `inspector_only_delegation_for_mutating_task`.
- Existing worker jobs/reports cannot be retroactively promoted to spawn evidence.

## 6. Root Cause Layer

Runtime evidence layer, not route configuration. The patch can enforce future behavior, but it cannot convert historical `subagent_worker_jobs.jsonl` records, worker report records, or textual spawn claims into canonical spawn evidence.

## 7. Why Previous Patch Did Not Fix It

Previous checks over-weighted static configuration, acceptance labels, and candidate records. They did not force the live Stop path to prioritize orchestration failures before generic direct evidence failure, and they allowed acceptance output to drift from the persisted result file.

This P0 patch fixes those code-path issues, but a fresh runtime observation is still required to reprove the system.

## 8. Next Minimal Patch

Do not patch broader toolchain modernization yet. The next minimal runtime proof should be one controlled Class 2/3/4 scenario that produces either:

- a canonical `worker_spawn_event`, worker report, route/job PM decision, and inspector evidence, or
- a Stop denial with `required_worker_not_spawned` / `inspector_only_delegation_for_mutating_task` when worker evidence is absent.

## 9. Regression Test To Add

Keep the new P0 checks and add a live fixture runner that builds a temporary runtime root and asserts:

- worker job without `worker_spawn_event` returns `required_worker_not_spawned`
- inspector-only mutating task returns `inspector_only_delegation_for_mutating_task`
- worker report without matching same-`job_id` spawn is quarantined and PM rejects it
- `direct_evidence_missing` never masks the above failures
