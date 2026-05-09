# Current State Audit

## Summary Verdict
FAIL

Current operating state remains `FAIL_UNTIL_REPROVEN`. The latest acceptance suite passes, but live runtime ledgers do not yet prove the PM/Subagent evidence chain for Class 2/3/4 work. The decisive blocker is that required worker jobs exist, while canonical `worker_spawn_event` evidence is absent.

Production use should stay restricted or shadow-only until user + GPT Pro accept a follow-up audit with real worker spawn/report/PM decision/Stop evidence.

## Evidence Window
- Checked from: 2026-05-06T13:36:56.5284764Z
- Checked to: 2026-05-08T16:33:49.9826400Z
- Local clock context: 2026-05-09 KST; timestamps above are UTC unless stated otherwise.
- Latest files:
  - `Maintenance/hook_invocations.jsonl`: 15,794 parsed events; latest 2026-05-08T16:33:43.3749216Z
  - `Settings/Codex_App_RUNTIME/tool_usage_events.jsonl`: 7,921 parsed events; latest 2026-05-08T16:33:39.8242436Z
  - `Settings/Codex_App_RUNTIME/subagent_worker_jobs.jsonl`: 94 records; latest worker job 2026-05-08T15:54:13.1162616Z
  - `Settings/Codex_App_RUNTIME/subagent_lifecycle_events.jsonl`: 592 records; latest lifecycle 2026-05-08T15:54:18.2919183Z
  - `Settings/Codex_App_RUNTIME/pm_decisions.jsonl`: 110 records
- Ignored stale docs:
  - Old design/plan docs were treated as history only.
  - `Maintenance/harness-v2/final_acceptance_result.json` is stale candidate evidence: it still records 126/126 at 2026-05-07T19:16:13Z, while the latest command run produced 128/128 at 2026-05-08T16:33Z.

## Runtime Status
- SessionStart: present in `Maintenance/hook_invocations.jsonl`
- UserPromptSubmit: present; current receipts regenerated for turn `41c134bedf43...`
- PreToolUse: present and append-only
- PostToolUse: present and append-only
- Stop: present; latest checked Stop samples deny completion for `direct_evidence_missing`
- gate-issued receipt: `Settings/Codex_App_RUNTIME/gate_issued_completion_receipt.json` is `candidate`, `NOT_ISSUED_FOR_NEW_PROMPT`; it is not completion authority.

## PM / Subagent Status
| task_id | class | required_worker | worker_spawned | worker_reported | required_inspector | inspector_spawned | inspector_reported | PM decision | Stop result |
|---|---|---:|---:|---:|---:|---:|---:|---|---|
| 8ff105b28858 | Class 3/4 proxy | implementation,test,control_plane | 0 | 18 | yes | 6 | 57 | route job decision missing | ALLOW_COMPLETE_CLAIM:receipt_verified_complete |
| ef9a3c586179 | Class 3/4 proxy | implementation,control_plane | 0 | 2 | yes | 6 | 4 | route job decision missing | ALLOW_COMPLETE_CLAIM:verified_complete |
| 94f10f480811 | Class 3 proxy | control_plane | 0 | 0 | yes | 1 | 2 | route job decision missing | DO_NOT_CLAIM_COMPLETE:direct_evidence_missing |
| f0bc354d83ba | Class 3 proxy | control_plane | 0 | 0 | yes | 1 | 4 | 1 route decision | DO_NOT_CLAIM_COMPLETE:direct_evidence_missing |
| 41c134bedf43 | Class 4 current receipt | control_plane | 0 | 0 | yes | 1 | 4 | 2 route decisions | DO_NOT_CLAIM_COMPLETE:direct_evidence_missing |

Aggregate latest-only runtime findings:
- Class 2/3/4 proxy turns with required worker jobs: 27
- Required worker turns with canonical `worker_spawn_event`: 0
- Class 2/3/4 proxy turns missing canonical worker spawn: 27
- Mutating/control-plane proxy turns with inspector spawn but no worker spawn: 16
- Canonical inspector spawn events: 29
- Canonical worker spawn events: 0
- Canonical worker report lifecycle events: 0
- Worker report ledger records exist: 31, but they are not backed by canonical worker spawn lifecycle records.
- PM decisions with both `route_id` and `job_id`: 4

## Config Vocabulary Findings
- `C:\Users\anise\.codex\config.toml` has `[features].hooks = true` and `[agents].max_threads = 8`, `[agents].max_depth = 1`.
- No project `.codex/config.toml` was found in this repo.
- `Maintenance/Test-CodexConfigAuthority.ps1` reports `verified`.
- Conflict remains as an operational note: local authority uses `features.hooks`, but current public Codex hooks docs still show `[features].codex_hooks = true`; local app package also contains internal legacy `features.codex_hooks` strings. This is documented, but not fully eliminated upstream.
- `max_depth` is no longer configured as 8 locally; it is 1. Official Codex docs define `agents.max_depth` as nesting depth and `agents.max_threads` as concurrent open thread count.
- Worker route names are aligned in schema/config/hook for `implementation_worker`, `control_plane_worker`, `frontend_worker`, and `backend_worker`.

## Tool / Skill Usage Findings
- `tool_usage_event.v2` and `skill_usage_events.jsonl` exist.
- `Test-PmOrchestrationRuntimeEvidence.ps1` passed checks that configured/installed capability is not accepted as usage evidence.
- 68 textual spawn claims were observed in `tool_usage_events.jsonl`, including `Write-Output 'spawn_agent ... subagent_spawned'`. Current runtime tests reject these as canonical spawn evidence.
- No evidence was found that those textual spawn claims are currently counted as valid `worker_spawn_event`.

## Stop Authority Findings
- `gate_issued_completion_receipt.json` is not issued for the current prompt.
- Acceptance tests include `required_worker_not_spawned` and inspector-only failure cases.
- Live Stop ledger does not show `required_worker_not_spawned` or `inspector_only_delegation_for_mutating_task` as actual reason codes. Latest live Stop denials are mostly `direct_evidence_missing` or `state_in_progress`.
- This means `required_worker_not_spawned` exists in code/acceptance, but has not yet been proven as the live Stop reason for the affected runtime turns.
- Two older worker-required turns had `ALLOW_COMPLETE_CLAIM` despite zero canonical worker spawn in lifecycle evidence. Treat those as tainted historical completion evidence until re-audited.

## Verdict Rationale
The latest code-level tests improved the guard shape, but PASS requires actual runtime evidence. The current ledgers show worker jobs and inspector activity, not canonical worker spawn lifecycle. Because worker spawn is the required distinction between configured capability and actual usage evidence, the system cannot be marked PASS.

## Required Fixes Before PASS
1. Emit canonical `worker_spawn_event` from actual worker spawn lifecycle, not from job scheduling or text.
2. Backfill or quarantine old worker reports without canonical worker spawn.
3. Make Stop surface `required_worker_not_spawned` and `inspector_only_delegation_for_mutating_task` as live reason codes when those conditions exist.
4. Require PM route decisions with `job_id` for each required worker and inspector route before any gate receipt can issue.
5. Refresh persisted acceptance result output so it cannot lag behind latest command output.
6. Keep candidate receipts, PASS labels, reports, and configured capabilities non-authoritative.

## Sources Checked
- Local: `Settings/Codex_App_RUNTIME/*`, `Maintenance/hook_invocations.jsonl`, `Settings/Dev_Codex_HOOKS/codex-ssot-hook.ps1`, `Maintenance/harness-v2/*`
- Official: [Codex hooks](https://developers.openai.com/codex/hooks), [Codex subagents](https://developers.openai.com/codex/subagents), [Codex config reference](https://developers.openai.com/codex/config-reference), [Codex skills](https://developers.openai.com/codex/skills)
