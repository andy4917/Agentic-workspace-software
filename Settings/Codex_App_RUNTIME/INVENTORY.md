# Inventory

- Runtime `.json` receipt/state files in this folder are generated local
  operational artifacts and are ignored by Git except
  `runtime_state.schema.json`.
- `active_contract.json`: active task contract state.
- `rejected_hypotheses.json`: rejected hypotheses state.
- `completion_receipt.json`: agent-written candidate completion receipt state.
- `gate_issued_completion_receipt.json`: Stop gate-issued final authority receipt for a validated candidate completion receipt.
- `task_classification_receipt.json`: current-turn `task_classification_receipt.v1` proving basic work was positively allowed or the task was classified upward.
- `need_resolution_receipt.json`: current-turn `need_resolution_receipt.v1` from `required_route_resolver`, including REQUIRED/RECOMMENDED/NOT_APPLICABLE/UNAVAILABLE/UNKNOWN route need.
- `skill_resolution_receipt.json`: current-turn `skill_resolution_receipt.v1` from required skill routes; installed/configured/available skills are not completion evidence.
- `skill_usage_events.jsonl`: append-only `skill_usage_event.v1` ledger proving actual skill use or explicit unavailable/not_applicable evidence.
- `runtime_capability_receipt.json`: generated receipt of loaded AGENTS.md sources, active hooks, Codex config authority quick status, available MCP servers, skills, configured subagents, cwd, project root, and trust state.
- `tool_usage_events.jsonl`: append-only `tool_usage_event.v2` observation ledger written from PostToolUse or equivalent PreToolUse observation, including event IDs, nonces, outcome, and parent lineage when present.
- `heuristic_review_jobs.jsonl`: append-only queue for reward-hacking keyword hits downgraded to `SUSPECT`.
- `heuristic_review_reports.jsonl`: append-only candidate-only review reports from `spark_false_positive_reviewer`.
- `required_tool_loop_state.json`: loop-breaker state for repeated `required_tool_not_used` completion attempts without artifact or evidence change.
- `subagent_inspection_jobs.jsonl`: append-only Spark inspector job queue; jobs are read-only and `candidate_evidence_only`.
- `subagent_inspection_reports.jsonl`: append-only candidate-only inspector report ledger reviewed by the parent PM before Stop evidence adoption.
- `subagent_worker_jobs.jsonl`: append-only worker job queue; jobs are scoped workspace-write and `candidate_artifact_only`.
- `subagent_worker_reports.jsonl`: append-only worker report ledger reviewed by the parent PM before Stop artifact adoption.
- `subagent_lifecycle_events.jsonl`: append-only `subagent_lifecycle_event.v1` ledger for spawned, quarantined, terminated, replacement, accepted, and auto-closed worker/inspector lifecycle decisions.
- `subagent_inspection_loop_state.json`: loop-breaker state for repeated `required_subagent_not_spawned` or `subagent_report_missing` completion attempts.
- `pm_decisions.jsonl`: append-only `pm_decision.v1` ledger for main-agent orchestration, report review, unresolved findings, PM failure reason codes, and completion-claim eligibility.
- `repo_gate_adoption_receipt.json`: runtime receipt proving actual hook wiring for repo/session gate adoption.
- `codex_config_authority_receipt.json`: detailed audit receipt for active config layers, trusted project overrides, backup absence, app global state legacy mentions, Desktop package legacy overrides, and Desktop deprecation log source classification.
- `codex_hook_ui_surface_receipt.json`: detailed audit receipt separating actual hook execution from Desktop webview hook icon/statusMessage rendering, compact/latest icon suppression, and message-handler hook loss logs.
- `repo_v2_adoption_receipt.json`: repo-specific adoption receipt bundling repo path, Git dirty state, active agent chain, lint/typecheck/test/build evidence, required routes, inspector reports, contamination scan, gate decision, and handoff confirmation.
- `stable_lessons.json`: stable lessons state.
- `runtime_state.schema.json`: runtime state declaration.
