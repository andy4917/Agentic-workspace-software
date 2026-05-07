# Harness V2 Integrity Compatibility Actions

Status: conditional PASS for SSOT/Harness V2 documents.

Production transition remains on hold until shadow observation and representative
repo adoption receipts are complete.

## Compatibility Definition

Harness V2 is integrity-compatible only when all of these hold:

- Global Harness V2 does not interrupt normal project work for conversation,
  planning, read-only inspection, image generation, or normal implementation.
- Repo-local `AGENTS.md`, workflow documents, test commands, package managers,
  and monorepo tools remain respected as guidance and validation inputs, but do
  not weaken global completion authority.
- Each representative project has a normal verification path: lint, typecheck,
  test, build, secret scan, policy/config validation, or explicit not-run
  evidence where a check is not applicable.
- Fake pass reports, subagent PASS, stale or future-dated receipts, warning
  concealment, evaluator manipulation, and candidate completion receipts cannot
  obtain completion authority.
- Main-agent PM failures cannot obtain completion authority, including missing
  required routes, missing subagent spawn, unreviewed reports, unresolved
  inspector findings, worker blame shifting, and premature completion claims.
- Completion authority comes only from the Stop-issued
  `gate_issued_completion_receipt.json`.
- Event ledger entries are append-only and preserve parent/subagent lineage.
- PM decision ledger entries are append-only and preserve the main agent's
  orchestration decision, reviewed reports, unresolved findings, and failure
  reason codes.
- On failure, only the affected artifact from the current attempt is discarded;
  unrelated clean artifacts are not rolled back.

## Current Status

Satisfied on the SSOT side:

- Isolated V2 design, policy, acceptance tests, runner, migration plan, and
  discussion notes exist under `Maintenance/harness-v2`.
- Acceptance runner passes the current isolated case set.
- PreToolUse is scoped as action safety only.
- Missing required-tool evidence is Stop-only.
- PM accountability is Stop-only and ledger-based; it does not make PreToolUse
  stricter.
- `completion_receipt.json` is candidate input only.
- Future-dated validation timestamps are invalid evidence.
- Path-scope mismatch is observational as `path_scope_observed`; concrete risk
  blockers remain active.

Not yet production complete:

- V2 shadow observation has not completed as production evidence.
- Production hook replacement has not occurred.
- Representative frontend and backend repo adoption receipts are not complete.
- Individual repos have not all provided lint/typecheck/test/build evidence or
  explicit not-run evidence.

## Required Stages

1. Stage 0 isolated acceptance:
   Keep files under `Maintenance/harness-v2`, run
   `Invoke-HarnessV2Acceptance.ps1`, and keep production wiring at `none`.

2. Stage 1 shadow observation:
   Record V2 decisions to separate JSONL without blocking or continuing turns.
   Compare V1 live hook decisions with V2 for conversation, planning, image
   generation, read-only inspection, normal implementation, and completion
   claims.

3. Stage 2 PreToolUse replacement:
   Replace only action safety. Keep completion evidence, required-tool route
   validation, freshness, and authority receipt issuance out of PreToolUse.

4. Stage 3 Stop replacement:
   Move completion evidence, required-tool validation, freshness, dependency
   alignment, PM aggregation validation, and gate-issued receipt authority to
   Stop.

5. Stage 4 ledger and receipt hardening:
   Keep append-only ledger records, preserve lineage, treat subagent and
   agent-written receipts as candidate evidence only, record `pm_decision.v1`
   events, and issue authority only from Stop.

6. Stage 5 fresh session verification:
   Verify SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, and Stop in a
   fresh Codex app session.

## Repo Adoption Receipt Template

```yaml
repo_v2_adoption_receipt:
  repo_path: ""
  project_type: frontend | backend | fullstack | library | infra | docs
  git_dirty_state: clean | dirty | not_git_repo | unknown
  current_branch: ""
  active_agents_chain: []
  applied_hook_state: []
  detected_package_manager: npm | pnpm | yarn | uv | poetry | gradle | maven | other | none
  detected_monorepo_tool: nx | turborepo | bazel | none | unknown
  required_tool_routes: []
  pm_decision:
    pm_decision: submit_to_stop | do_not_claim_complete | repair | ask_user | continue
    pm_failure: true | false
    pm_failure_reason_codes: []
    reports_reviewed: []
    unresolved_findings: []
  lint:
    command: ""
    result: pass | fail | not_run
    not_run_reason: ""
  typecheck:
    command: ""
    result: pass | fail | not_run
    not_run_reason: ""
  test:
    command: ""
    result: pass | fail | not_run
    not_run_reason: ""
  build:
    command: ""
    result: pass | fail | not_run
    not_run_reason: ""
  secret_scan:
    command: ""
    result: pass | fail | not_run
    not_run_reason: ""
  policy_config_validation:
    command: ""
    result: pass | fail | not_run
    not_run_reason: ""
  contamination_cases:
    result: pass | fail | not_run
    covered_cases: []
  gate_issued_receipt:
    state: verified_complete | candidate | invalid | absent
    decision: ALLOW_COMPLETE_CLAIM | DO_NOT_CLAIM_COMPLETE | BLOCKED | absent
  warnings_or_limits: []
```

## Representative Repo Minimums

Frontend repo:

- README or package config identifies install, run, lint, typecheck, test, and
  build commands or explicit not-run reasons.
- No fake product data is treated as completed product behavior.
- Generated image artifacts and executable UI artifacts are separated.
- Env documentation avoids exposing secrets.

Backend repo:

- Request processing and response/effect paths are documented or testable.
- Unit/integration, contract/schema, lint, typecheck, and build checks run or
  have explicit not-run evidence.
- Warning/error/non-zero exit handling is not hidden.
- Auth, secret, or private credential material is not accessed without explicit
  user instruction.

## Production Transition Ban Conditions

Production transition is forbidden if any of these are true:

- V2 acceptance fails.
- Direct production wiring happens before shadow observation.
- PreToolUse blocks ordinary conversation, planning, image generation,
  read-only inspection, or normal implementation.
- Stop blocks non-final responses for missing direct evidence.
- Candidate receipts, PASS labels, tests, subagent PASS, or final prose become
  completion authority.
- Event ledger entries can be overwritten.
- Stale or future-dated receipts pass.
- Warning, error, exit-code, evaluator, or fake-success manipulation passes.
- Repo-local `AGENTS.md` weakens global completion definitions.
- Full development-environment completion is claimed before representative repo
  adoption receipts exist.
