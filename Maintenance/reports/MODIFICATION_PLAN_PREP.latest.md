# Modification Plan Preparation

## Current State Dependency
- This plan is valid only if `Maintenance/reports/CURRENT_STATE_AUDIT.latest.md` is accepted by user + GPT Pro.
- Current audit verdict is FAIL, so this is a remediation plan, not a production enablement plan.
- Do not patch production hooks as part of this preparation step.

## P0 Fixes

### P0.1 Canonical worker spawn enforcement
Target files:
- `Settings/Dev_Codex_HOOKS/codex-ssot-hook.ps1`
- `Settings/Codex_App_RUNTIME/runtime_state.schema.json`
- `Maintenance/Test-PmOrchestrationRuntimeEvidence.ps1`
- `Maintenance/harness-v2/harness_v2_acceptance_tests.yaml`

Reason:
- Runtime has 27 worker-required turns and 0 canonical `worker_spawn_event`.
- Worker jobs and worker reports exist, but actual worker spawn lifecycle is not proven.

Acceptance tests:
- Class 2 code edit + only inspector spawned -> `DO_NOT_CLAIM_COMPLETE:required_worker_not_spawned`
- Class 3 hook repair + only inspectors spawned -> `DO_NOT_CLAIM_COMPLETE:inspector_only_delegation_for_mutating_task`
- Worker job exists but no `worker_spawn_event` -> `DO_NOT_CLAIM_COMPLETE:canonical_spawn_event_missing`
- Worker report without matching spawn -> denied or quarantined

### P0.2 Stop reason code surfacing
Target files:
- `Settings/Dev_Codex_HOOKS/codex-ssot-hook.ps1`
- `Maintenance/harness-v2/Invoke-HarnessV2Acceptance.ps1`
- `Maintenance/harness-v2/harness_v2_acceptance_tests.yaml`

Reason:
- `required_worker_not_spawned` exists in code/acceptance but has not appeared as a live Stop reason in the latest ledger.
- Current live Stop denials collapse to `direct_evidence_missing` or `state_in_progress`, which hides the orchestration failure.

Acceptance tests:
- Missing worker route must beat generic direct-evidence failure when worker route is required.
- Inspector-only delegation must produce its own PM failure reason.

### P0.3 PM route decision completeness
Target files:
- `Settings/Dev_Codex_HOOKS/codex-ssot-hook.ps1`
- `Settings/Codex_App_RUNTIME/runtime_state.schema.json`

Reason:
- Only 4 PM decision events currently include both `route_id` and `job_id`.
- PM decision must be per-route and per-job, not just preflight initialization.

Acceptance tests:
- Worker report without PM `accept_report` or `reject_report` decision -> `pm_decision_missing`
- Inspector report without PM decision -> `pm_decision_missing`
- Quarantined report cannot satisfy route.

### P0.4 Persist latest acceptance result
Target files:
- `Maintenance/harness-v2/Invoke-HarnessV2Acceptance.ps1`
- `Maintenance/harness-v2/final_acceptance_result.json`

Reason:
- Latest command output: 128/128 passed.
- Persisted result file: stale 126/126 candidate evidence from 2026-05-07T19:16:13Z.

Acceptance tests:
- Acceptance runner writes latest result atomically.
- Report generator flags stale persisted results if command output is newer.

## P1 Toolchain Modernization

### P1.1 Add root justfile
Target files:
- `justfile`

Reason:
- Current audit commands are scattered across PowerShell scripts.
- `just` should become the user-facing entrypoint while preserving existing scripts.

Recipes:
- `audit-current`
- `harness-acceptance`
- `pm-orchestration-audit`
- `config-audit`
- `ledger-audit`
- `subagent-audit`
- `report-current`
- `py-sync`

Test needed:
- `just --list`
- `just harness-acceptance`
- `just pm-orchestration-audit`

### P1.2 Add uv-managed Python audit package
Target files:
- `Tools/harness_py/pyproject.toml`
- `Tools/harness_py/uv.lock`
- `Tools/harness_py/src/harness_py/**`

Reason:
- JSONL aggregation and Markdown report generation should be testable library code.

Test needed:
- `uv sync --locked`
- `uv run python -m harness_py.audit.current_state`
- `uv run python -m harness_py.reports.current_state`

### P1.3 Report generation parity
Target files:
- `Tools/harness_py/src/harness_py/reports/current_state.py`
- `Maintenance/reports/*.latest.md`

Reason:
- Reports should be generated from canonical runtime state, not hand-written summaries.

Test needed:
- Generated report matches key counts: worker turns 27, worker spawns 0, inspector-only 16, Stop `required_worker_not_spawned` 0.

## P2 Rust Helper Candidate

### P2.1 Harness core spike
Target files:
- `Tools/harness-core/Cargo.toml`
- `Tools/harness-core/src/**`

Candidate modules:
- `event_envelope`
- `jsonl_ledger`
- `path_scope`
- `dedupe_key`
- `stop_predicate`
- `receipt_freshness`

Reason:
- The PowerShell hook is 8,047 lines. Hot-path canonical validation and ledger scans are better isolated in a typed helper once behavior is fully specified.

Test needed:
- Rust helper validates a fixture ledger exactly the same way as PowerShell/Python shadow audits.
- No production hook switch until parity is proven.

## Do Not Change Yet
- Do not replace the production hook entrypoint.
- Do not rewrite the full PowerShell hook in Rust.
- Do not treat `subagent_worker_jobs.jsonl` as spawn evidence.
- Do not treat worker report ledgers as completion authority.
- Do not issue gate receipts from subagent reports alone.
- Do not remove compatibility fields until all consumers use `resolved_model`.
- Do not normalize away the `features.hooks` vs `features.codex_hooks` conflict without a dedicated config authority patch.

## Acceptance Tests Required Before Patch
- Class 2 code edit + only inspector spawned -> `DO_NOT_CLAIM_COMPLETE:required_worker_not_spawned`
- Class 3 hook repair + only inspectors spawned -> `DO_NOT_CLAIM_COMPLETE:inspector_only_delegation_for_mutating_task`
- Class 3 hook repair + worker + inspectors -> `route_satisfied_candidate`, then Stop requires gate authority
- `Write-Output "spawn_agent ..."` -> not accepted as canonical spawn event
- child worker prompt must not overwrite parent `active_contract`
- `max_threads` / `max_depth` semantics verified
- subagent PASS without parent Stop receipt cannot complete
- installed skill without `skill_usage_event` cannot satisfy route
- configured subagent without lifecycle spawn cannot satisfy route
- stale `final_acceptance_result.json` detected when command output is newer

## Recommended Execution Order
1. P0.1 and P0.2 together, because worker spawn evidence and Stop reason surfacing are the same authority chain.
2. P0.3 before any PASS claim.
3. P0.4 to prevent stale candidate reports.
4. P1.1 as a facade only.
5. P1.2 and P1.3 in shadow mode.
6. P2 only after Python reports reproduce the live ledger findings.
