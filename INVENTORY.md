# Dev_Codex_App_GlobalSSOT Inventory

This root inventory summarizes the managed SSOT surfaces. `MANIFEST.json` is
the machine-readable registry; this file is the human scan surface.

## Root Records

- `MANIFEST.json`: managed element registry.
- `ROOT_MAP.json`: canonical root and imported runtime storage mapping.
- `CHANGELOG.md`: non-runtime change record.
- `.gitignore`: Git staging guard for runtime ledgers, caches, dependencies,
  and large local mirrors.
- `.gitattributes`: Git line-ending normalization rules.
- `AGENTS.md`, `AGENT.md`, `AGENTS.override.md`: guidance surfaces, not
  completion authority.

## Harness V2

- `Maintenance/agent-skills-integration/agent_skills_inventory.json`: fixed
  upstream `addyosmani/agent-skills` source URL/HEAD, installed P0 skill list,
  skipped skill list, and copied `SKILL.md` hashes for skill-route adoption.
- `Maintenance/harness-v2/HARNESS_V2_DESIGN.md`: isolated prototype design.
- `Maintenance/harness-v2/harness_v2_policy.yaml`: machine policy.
- `Maintenance/harness-v2/harness_v2_acceptance_tests.yaml`: acceptance oracle.
- `Maintenance/harness-v2/Invoke-HarnessV2Acceptance.ps1`: isolated acceptance
  runner.
- `Maintenance/Test-RepoV2AdoptionReceiptV2.ps1`: repo-specific v2 adoption
  receipt generator and verifier for Git state, active agent chain, checks,
  routes, inspector evidence, scan result, gate link, and handoff readiness.
- `Maintenance/Test-CodexConfigAuthority.ps1`: verifies active Codex config
  authority alignment for `features.hooks` and `features.goals`, trusted
  project config overrides, pre-2026-05-07 backup absence, historical
  non-authority mentions, Desktop deprecation log source classification, and
  packaged app internal legacy overrides.
- `Maintenance/Test-CodexHookUiSurface.ps1`: separates hook runner execution
  from Codex Desktop webview rendering by checking hook config keys, actual
  hook invocations, package hook renderer/statusMessage support, compact/latest
  hook icon suppression, and Desktop message-handler hook loss logs.
- `Maintenance/Test-SubagentInspectionRouting.ps1`: live hook smoke check for
  queued Spark inspector jobs and candidate-only spawn/report ledger events.
- `Maintenance/Test-HeuristicFalsePositiveReview.ps1`: live hook regression for
  reward-hacking SUSPECT review jobs and preserved absolute deny blockers.
- `Maintenance/harness-v2/MIGRATION_PLAN.md`: staged production migration plan.
- `Maintenance/harness-v2/GPT_PRO_DISCUSSION_NOTE.md`: English discussion note.
- `Maintenance/harness-v2/GPT_PRO_DISCUSSION_NOTE.ko.md`: Korean discussion
  note.
- `Maintenance/harness-v2/harness_v2_integrity_compatibility_actions.md`:
  conditional PASS, repo adoption, and production transition action record.
- `Maintenance/harness-v2/final_acceptance_result.json`: machine-readable
  PM-reviewed final acceptance candidate evidence.
- `Maintenance/harness-v2/final_acceptance_report.md`: human-readable
  PM-reviewed final acceptance candidate evidence.

## Runtime And Hooks

- `Settings/Dev_Codex_HOOKS/codex-ssot-hook.ps1`: live hook runner.
- `Settings/Dev_Codex_HOOKS/*.yaml`: hook policy/config surfaces.
- `Maintenance/Test-RepoGateAdoption.ps1`: verifies actual global hook wiring
  and documented handler keys before issuing repo gate adoption evidence.
- `Settings/Codex_App_RUNTIME/*.json`: generated runtime receipts and state
  files. They are local operational artifacts and ignored by Git except
  `runtime_state.schema.json`.
- `Settings/Codex_App_RUNTIME/tool_usage_events.jsonl`: append-only usage
  ledger.
- `Settings/Codex_App_RUNTIME/heuristic_review_jobs.jsonl`: append-only
  reward-hacking SUSPECT review job queue.
- `Settings/Codex_App_RUNTIME/heuristic_review_reports.jsonl`: append-only
  candidate-only false-positive review report ledger.
- `Settings/Codex_App_RUNTIME/task_classification_receipt.json`: current-turn
  task classification receipt, with basic work as a positive allowlist.
- `Settings/Codex_App_RUNTIME/need_resolution_receipt.json`: current-turn route
  need receipt from `required_route_resolver`.
- `Settings/Codex_App_RUNTIME/skill_resolution_receipt.json`: current-turn
  skill route receipt generated after need resolution; installation is not
  completion evidence.
- `Settings/Codex_App_RUNTIME/skill_usage_events.jsonl`: append-only
  `skill_usage_event.v1` ledger proving actual required-skill use or explicit
  unavailable/not_applicable evidence.
- `Settings/Codex_App_RUNTIME/repo_v2_adoption_receipt.json`: repo-specific
  adoption receipt bundling repo path, Git state, active agent chain,
  lint/typecheck/test/build evidence, required routes, inspector reports,
  contamination scan, gate decision, and handoff confirmation.
- `Settings/Codex_App_RUNTIME/subagent_inspection_jobs.jsonl`: append-only
  Spark inspector job queue.
- `Settings/Codex_App_RUNTIME/subagent_inspection_reports.jsonl`: append-only
  candidate-only inspector report ledger.
- `Settings/Codex_App_RUNTIME/subagent_worker_jobs.jsonl`: append-only
  worker job queue for scoped workspace-write candidate artifact routes.
- `Settings/Codex_App_RUNTIME/subagent_worker_reports.jsonl`: append-only
  worker report ledger; reports remain `candidate_artifact_only` until parent
  PM review and Stop authority.
- `Settings/Codex_App_RUNTIME/subagent_lifecycle_events.jsonl`: append-only
  `subagent_lifecycle_event.v1` worker/inspector lifecycle ledger, including
  automatic close events after route resolution.
- `Settings/Codex_App_RUNTIME/subagent_inspection_loop_state.json`: Stop-only
  loop breaker for missing inspector jobs or reports.
- `Settings/Codex_App_DECLARATIVE/*.yaml`, `*.json`, `*.toml`: declarative
  policy and clean-slate configuration.
- `Settings/Codex_App_DECLARATIVE/clean-slate.agent.config.toml`
  `[codex_config_authority]`: current local config key authority for hook
  features and diagnostic source boundaries.
- `Settings/Codex_App_RUNTIME/codex_config_authority_receipt.json`:
  detailed config authority audit receipt for active config layers, trusted
  project overrides, historical state classification, and Desktop app/cache
  or internal override timing evidence.
- `Settings/Codex_App_RUNTIME/codex_hook_ui_surface_receipt.json`: detailed
  hook UI surface audit receipt for runner evidence versus Desktop webview
  icon/statusMessage rendering and compact/latest suppression.
