# Harness V2 Design

Status: isolated prototype plus live hook-routed Spark inspection patch.

This design treats the current SSOT hook history as trace material, not as the
primary architecture for the next harness. The V2 goal is smaller responsibility
boundaries:

- normal work stays light and fast;
- reward hacking cannot obtain completion authority;
- conversation, explanation, planning, image generation, and read-only
  inspection are not finalization problems;
- the agent quietly orchestrates tools, skills, checks, and logs;
- the user stays focused on intent and direction.

## Source Basis

- User review document:
  `C:\Users\anise\Downloads\codex_dev_env_remodel_review.md`.
- Main-agent accountability addendum:
  `C:\Users\anise\Downloads\main_agent_accountability_contract_addendum.md`.
- Official Codex hooks documentation:
  `https://developers.openai.com/codex/hooks`.
- Official Codex skills documentation:
  `https://developers.openai.com/codex/skills`.
- Official Codex AGENTS.md documentation:
  `https://developers.openai.com/codex/guides/agents-md`.
- Official Codex subagents documentation:
  `https://developers.openai.com/codex/subagents`.

The important alignment points are:

- `PreToolUse` and `PostToolUse` are tool lifecycle surfaces, not a complete
  proof system for user intent or task completion.
- `Stop` can continue a turn, so it is the right place to refuse completion
  claims without blocking non-final responses.
- Skills use progressive disclosure: installed is not the same as used.
- AGENTS.md is guidance with scope and precedence, not completion authority.
- Subagents are explicitly spawned helpers and remain candidate evidence.
- Hook-routed Spark inspectors are tool-like read-only helpers: the parent can
  command them only through a typed inspection job envelope, and the inspector
  must report `out_of_scope` instead of acting outside its configured route.

## V2 Layers

1. Task router
   - Classifies the user request and current action into Class 0 through
     Class 4 and writes `task_classification_receipt.v1`.
   - Treats basic work as a positive allowlist, not a fallback; ambiguous work
     classifies upward.

2. Need resolution
   - Runs `required_route_resolver` and writes
     `need_resolution_receipt.v1`.
   - Computes REQUIRED, RECOMMENDED, NOT_APPLICABLE, UNAVAILABLE, or UNKNOWN
     need from task class, touched surface, action class, risk class,
     completion claim, user instruction, changed paths, prior failures, and
     unresolved findings.
   - UNKNOWN or unsatisfied REQUIRED routes block only completion at Stop.

3. PreToolUse action safety
   - Blocks actual risk actions only.
   - Does not evaluate completion evidence.
   - Does not block ordinary conversation, planning, image generation,
     read-only inspection, or normal implementation.

4. Tool and skill router
   - Records matched required routes.
   - Records used, unavailable, or not applicable tools and skills.
   - Defers missing-route completion consequences to Stop.

5. PostToolUse observation ledger
   - Append-only event records.
   - Captures event id, turn id, attempt id, task type, action class, target
     paths, decision, tool name, exit code, warnings, and lineage.
   - Captures `subagent_spawn` and `subagent_report` events with `job_id`,
     `parent_turn_id`, `agent_name`, `sandbox_mode`, `target_paths`, `status`,
     and `authority=candidate_evidence_only`.
   - Does not directly block ordinary flow.

6. PM accountability ledger
   - Records whether the main agent performed orchestration before asking for
     completion credit.
   - Captures user intent contract id, delegation plan id, required and used
     routes, spawned subagents, received and reviewed reports, unresolved or
     conflicting findings, PM decision, and PM failure reason codes.
   - Treats missing delegation, unreviewed reports, hidden warnings, worker
     blame shifting, and premature completion claims as main-agent PM failures.
   - Remains append-only evidence for Stop; it does not make PreToolUse
     stricter.

7. Stop finalization gate
   - Applies only to completion claims for executable or procedural artifacts.
   - Refuses authority with `DO_NOT_CLAIM_COMPLETE` when evidence is missing.
   - Requires PM accountability evidence for routed executable or procedural
     completion claims.
   - Issues authority only through a gate-issued receipt.

8. Hook-routed Spark inspection
   - UserPromptSubmit, PostToolUse, and Stop may append inspection jobs to
     `Settings/Codex_App_RUNTIME/subagent_inspection_jobs.jsonl`.
- Hooks do not wait for subagents.
- Parent Codex spawns only standing-authorized roles from
  `%USERPROFILE%\.codex\config.toml`.
- Main/worker subagent orchestration caps recursive spawning at `max_depth=1`;
  concurrency belongs to thread/job limits. Actual code workers use the latest
  configured model, `gpt-5.5`, with `reasoning_effort=medium`.
- Default inspector sandbox is read-only and inspector max depth remains 1.
- Missing inspector reports block completion only, never PreToolUse.

## Task Types

- `conversation`
- `planning`
- `image_generation`
- `read_only_inspection`
- `code_implementation`
- `test_validation`
- `config_automation`
- `control_plane_repair`
- `finalization_claim`

## Task Classes

- `Class 0`: ordinary conversation, planning, image generation, and read-only
  inspection; no executable finalization gate.
- `Class 1`: simple non-executable artifacts with no code/config/runtime
  surface.
- `Class 2`: implementation work, including small code/test/config changes.
- `Class 3`: hook, runtime, receipt, ledger, AGENTS, workflow, CI, completion
  gate, validation, or security control-plane work.
- `Class 4`: multi-surface or repo adoption work.

## Severity Model

- `OBSERVE`: record only, no user-facing interruption required.
- `WARN`: continue, but report the limitation if it matters.
- `ASK`: user scope or intent is ambiguous enough to require clarification.
- `DO_NOT_CLAIM_COMPLETE`: keep working or report partial status, but do not
  claim completion authority.
- `BLOCKED`: stop the specific risky tool action.

## Blocking Boundary

`BLOCKED` is reserved for:

- secret, credential, auth, or token access without explicit user instruction;
- destructive side effects outside explicit scope;
- unauthorized control-plane mutation;
- hook, test, evaluator, pass/fail, warning, or exit-code manipulation;
- product-code shortcuts that fake success rather than implement behavior.

Out-of-scope read-only inspection is not a hard block unless it touches private
material. User-mentioned reference files are read-only references, not scope
expansion for mutation.

## Image Generation Route

Image generation is treated as a visual artifact route, not an executable or
procedural finalization route. The checks are intentionally small:

- image generation tool or route was used when available;
- generated file or artifact path exists when practical;
- output visibly matches the requested subject at a reasonable level;
- no secret/private source was accessed;
- generated image folders and image skill files are read-only references.

No dynamic reproduction gate or direct evidence blocker applies to ordinary
image generation unless the user explicitly asks for a procedural runtime asset
with executable behavior.

## Main Agent Accountability

The main agent may act as PM and orchestrator for the current task, but it does
not own completion authority. PM authority means PM responsibility:

- convert the user goal into a User Intent Contract;
- decompose work through the required routes;
- invoke required subagents, tools, skills, and checks;
- collect and review worker and inspector reports;
- resolve conflicts, findings, warnings, errors, and test failures;
- submit current Stop evidence only after the routed work is actually reviewed.

Worker and inspector lanes are intentionally different. Workers are for actual
code or production work and must run on the latest configured model with medium
reasoning. Hook-routed Spark inspectors remain read-only, route-bound,
candidate-evidence helpers; their reports are reviewed by the PM and never
become completion authority by themselves.

The fastest path to completion credit is normal orchestration. Skipping
required delegation, hiding issues, using PASS/test/subagent PASS as authority,
or claiming completion early is a PM failure and receives no completion credit.

PM failure reason codes include:

- `user_intent_contract_missing`;
- `user_instruction_ignored`;
- `task_classification_missing`;
- `need_resolution_missing`;
- `required_route_unsatisfied`;
- `required_route_not_used`;
- `required_subagent_not_spawned`;
- `required_tool_not_used`;
- `required_skill_not_used`;
- `subagent_report_missing`;
- `subagent_report_invalid_envelope`;
- `subagent_report_without_job_id`;
- `subagent_report_not_reviewed`;
- `subagent_report_not_evidence`;
- `pm_adopted_unverified_subagent_report`;
- `unresolved_inspector_findings`;
- `conflicting_worker_reports`;
- `pm_aggregation_missing`;
- `pm_decision_missing`;
- `premature_completion_claim`;
- `ignored_stop_gate`;
- `hidden_warning_or_error`;
- `bare_tests_pass_as_authority`;
- `subagent_pass_as_authority`;
- `reward_hacking_shortcut_attempted`;
- `reward_hacking_shortcut_tolerated`;
- `pm_shifted_blame_to_worker`;
- `repeated_pm_failure`.

When a PM failure occurs, Stop withholds completion credit and no gate-issued
receipt is issued. The affected artifact from the current attempt stays
candidate and may be reworked or discarded. A repeated identical PM failure
stops automatic retry and reports the failure to the user.

For executable or procedural completion claims, Stop requires:

- a User Intent Contract;
- current `task_classification_receipt.v1`;
- current `need_resolution_receipt.v1` with no UNKNOWN route need;
- a PM delegation plan when any required route matches;
- required subagent/tool/skill/check evidence or explicit unavailable/not
  applicable evidence;
- PM aggregation evidence in `Settings/Codex_App_RUNTIME/pm_decisions.jsonl`;
- received and reviewed required reports;
- no unresolved high-risk findings;
- `pm_decision=submit_to_stop`;
- `pm_failure=false`.

Subagent failure does not clear main-agent responsibility. Missing subagent
reports, unresolved subagent findings, and subagent PASS without evidence remain
PM-owned until repaired, explicitly waived by the user, or marked not applicable
with evidence.

## Completion Authority

Completion authority is not granted by:

- PASS labels;
- tests passing by themselves;
- subagent reports;
- subagent PASS or inspector report without a parent Stop gate receipt;
- candidate completion receipts;
- score-like outputs;
- final prose.

Authority requires a Stop decision for the current turn and, for executable or
procedural artifacts, path-linked evidence, spec relation, checks or explicit
not-run rationale, warnings or limits, freshness, PM aggregation evidence when a
required route matched, and a gate-issued receipt.

## Isolation Rule

The V2 harness is not wired into production hooks in this step. Acceptance tests
must pass in this isolated folder before any migration into
`Settings/Dev_Codex_HOOKS` or global Codex configuration is considered.
