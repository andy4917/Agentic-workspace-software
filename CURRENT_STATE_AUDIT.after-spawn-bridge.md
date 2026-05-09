# Current State Audit: After Subagent Spawn Bridge

Generated: 2026-05-09 KST

## Runtime Scope

- Active turn fingerprint: `41c134bedf43c2b72e2a760bc32c8ff986ca077fb18e13f44402fc5490360b8b`
- Active task class: `Class 4`
- Required worker routes: `control_plane_worker`
- Fresh Codex app worker session observed: `019e08aa-39bf-7e61-8642-a9271e4c1edd`
- Matched worker job: `worker-eb843f89a71549579e3da4561e9bb485`

## Required Counts

- Worker-required turn count: `1`
- Canonical `worker_spawn_event` count for active turn: `1`
- Canonical `inspector_spawn_event` count for active turn: `0`
- Live Stop `required_worker_not_spawned` count: `0`
- Live Stop `direct_evidence_missing` count: `38` cumulative historical hook rows; latest live Stop probe returned `state_in_progress`, not `direct_evidence_missing`.
- Gate-issued receipt state: `candidate`
- Gate-issued receipt reason: `user_prompt_submit_invalidated_previous_gate_receipt`

## Direct Evidence

- `Settings/Codex_App_RUNTIME/subagent_lifecycle_events.jsonl` contains a canonical lifecycle row for the fresh worker session:
  - `schema_version`: `subagent_lifecycle_event.v1`
  - `record_type`: `worker_spawn_event`
  - `event_type`: `worker_spawn_event`
  - `agent_role`: `worker`
  - `authority`: `candidate_artifact_only`
  - `status`: `spawned`
  - `source`: `codex_app_session_meta`
  - `source_thread_id`: `019e08aa-39bf-7e61-8642-a9271e4c1edd`
  - `job_id`: `worker-eb843f89a71549579e3da4561e9bb485`
- `Settings/Codex_App_RUNTIME/subagent_worker_jobs.jsonl` has the matched job appended as `status=spawned` with `spawn_event_id=sle_40bd6c794d524c7c831d2c68ef1e06d2`.
- `Settings/Codex_App_RUNTIME/runtime_capability_receipt.json` records the runtime worker subagent and standing inspector agents as configured/standing-authorized capabilities.

## Verification

- PowerShell parse check for `Settings/Dev_Codex_HOOKS/codex-ssot-hook.ps1`: `parse_ok`
- `Maintenance/Test-PmOrchestrationRuntimeEvidence.ps1`: `status=passed`
- `Maintenance/harness-v2/Invoke-HarnessV2Acceptance.ps1`: `133/133`, `fail_count=0`
- Fresh Stop probe after bridge: blocked at `state_in_progress`; no new `direct_evidence_missing` precedence failure was observed.

## Final Verdict

`SPAWN_BRIDGE_REPRODUCED_FOR_WORKER_REQUIRED_CLASS4`

The app-level worker subagent session is now bridged into the GlobalSSOT canonical lifecycle ledger as `worker_spawn_event.v1` evidence. Completion authority remains candidate-only because the active contract is still `in_progress` and gate-issued completion receipt state is `candidate`.
