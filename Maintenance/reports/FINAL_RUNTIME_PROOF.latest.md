# FINAL_RUNTIME_PROOF.latest

Verdict: FAIL
Generated at UTC: 2026-05-09T06:35:07.9301547Z
Turn fingerprint: a9668047e0488c60304e7e597b66a7eb33b0f4026a76dcefca4bf76e6eeec49b

## Runtime Criteria
- [FAIL] 1. App runtime hook marker recorded in SSOT ledger -- runtime_identity_receipt:rir_f20cf0314ea489a29551d8aea73e164e; hook_surface_probe:hsp_cabe362b491d45a0b0dd8912ada14c84
- [FAIL] 2. App worker spawn bridged to canonical worker_spawn_event -- worker_spawn_event_count:0; worker_job_ids:
- [FAIL] 3. Required inspectors have spawn and report events -- inspector_routes:1; missing_links:1
- [FAIL] 4. worker_report_event is backed by same-job worker_spawn_event -- worker_report_count:0; unbacked_worker_reports:0
- [FAIL] 5. PM decision event exists for every required route/job -- required_job_count:0; missing_pm_decisions:0
- [PASS] 6. Stop precedence returns required_worker_not_spawned before direct_evidence_missing -- negative_stop_reason:required_worker_not_spawned; negative_stop_decision:DO_NOT_CLAIM_COMPLETE
- [PASS] 7. Inspector-only mutating task is rejected -- acceptance_case:inspector_only_delegation_for_mutating_task_fails
- [FAIL] 8. Gate-issued receipt allows verified completion claim -- gate_state:candidate; gate_decision:NOT_ISSUED_FOR_NEW_PROMPT; gate_reason:user_prompt_submit_invalidated_previous_gate_receipt
- [PASS] 9. Candidate receipts, subagent PASS, tests, final prose, and configured capability are not authority -- authority_cases_missing:0; harness_acceptance:144/144; gate_source_candidate_only:True
- [FAIL] 10. Dev-Product repo adoption receipt generated -- dev_product_receipt:dev-product-6c1167b06e229546; product_typecheck:passed

## Bridge Fix
- Regression fixture: PASS; job_id=subagent-3d02b85c8d6d4edeb53d34526f4abc67; route_id=required_tool_route_inspection; agent_name=spark_tool_route_inspector.
- Canonical worker bridge: 0 worker_spawn_event from codex_app_session_meta.
- Canonical inspector bridge: required_tool_route_inspection job subagent-3d02b85c8d6d4edeb53d34526f4abc67 has inspector_spawn_event and inspector_report_event.

## Positive Full Chain
- Acceptance case worker_and_inspector_success_with_stop_authority_allows_completion: passed=True; reason=verified_complete.
- Gate-issued receipt: state=candidate; decision=NOT_ISSUED_FOR_NEW_PROMPT; reason=user_prompt_submit_invalidated_previous_gate_receipt.

## Negative Live Stop
- Live Stop proof: passed=True; decision=DO_NOT_CLAIM_COMPLETE; reason=required_worker_not_spawned.
- Harness case canonical_spawn_event_missing_blocks_completion_at_stop: passed=True; reason=required_worker_not_spawned.

## Product Repo Adoption
- Receipt: dev-product-6c1167b06e229546; status=blocked.
- Product project_root: C:\Users\anise\code\Dev-Product\입실퇴실 안내문 생성기.
- App SessionStart marker: rir_f20cf0314ea489a29551d8aea73e164e; hook probe: hsp_cabe362b491d45a0b0dd8912ada14c84.
- Product typecheck: passed via npm run typecheck.

## MCP Auxiliary Chain
- MCP integration proof: status=PASS; usage_event_config_only=True.
- MCP auxiliary passed: True.
- MCP servers are candidate-only support and do not replace worker/inspector spawn, report, PM decision, Stop, or gate-issued receipt.

## Audit Commands
- Harness acceptance: 144/144, failed=0.
- Repo gate adoption: blocked.
- Repo V2 adoption: candidate.
- Product adoption: blocked.
- MCP integration: PASS.
