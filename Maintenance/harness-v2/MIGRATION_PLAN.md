# Harness V2 Migration Plan

This migration is intentionally staged. The isolated harness must keep passing
before any production hook replacement is attempted.

## Stage 0: Isolated Acceptance

- Keep V2 files under `Maintenance/harness-v2`.
- Run `Invoke-HarnessV2Acceptance.ps1`.
- Include task classification and need resolution cases: missing receipts,
  UNKNOWN need, downshifted classification, unsatisfied required routes, and
  basic positive-allowlist denial.
- Include PM accountability cases for missing routes, missing subagents,
  unreviewed reports, unresolved findings, premature completion claims, and
  repeated PM failure.
- Treat failures as design failures, not production hook failures.
- Do not wire V2 into `C:\Users\anise\.codex\hooks.json` yet.

## Stage 1: Shadow Observation

- Add a shadow-only V2 runner that records decisions to a separate JSONL file.
- Do not block or continue turns from V2 during shadow mode.
- Compare V1 live hook decisions against V2 decisions for:
  - conversation;
  - planning;
  - image generation;
  - read-only inspection;
  - normal implementation;
  - completion claim.

## Stage 2: PreToolUse Replacement

- Replace only the action safety portion first.
- Keep blocking limited to actual risk operations:
  - credential or secret access;
  - destructive side effects;
  - unauthorized control-plane mutation;
  - evaluator, pass/fail, warning, or exit-code manipulation;
  - product fake-success shortcuts.
- Keep completion evidence checks out of PreToolUse.

## Stage 3: Stop Finalization Replacement

- Move completion evidence, required-tool route validation, freshness, and
  authority receipt issuance into the V2 Stop layer.
- Require PM aggregation evidence and `pm_decision=submit_to_stop` for routed
  executable or procedural completion claims.
- Treat PM failures as completion-credit denial, including worker blame shift,
  unreviewed reports, unresolved findings, and early completion claims.
- Return `DO_NOT_CLAIM_COMPLETE` for incomplete completion claims.
- Let non-final conversation, planning, image, explanation, and status replies
  finish without direct-evidence blockers.

## Stage 4: Ledger and Receipts

- Keep ledger writes append-only.
- Preserve parent and subagent lineage.
- Treat subagent output as candidate evidence only.
- Record hook-routed `subagent_spawn` and `subagent_report` events with
  job id, parent turn id, agent name, sandbox mode, target paths, status, and
  `authority=candidate_evidence_only`.
- Record main-agent PM decisions in
  `Settings/Codex_App_RUNTIME/pm_decisions.jsonl` as append-only
  `pm_decision.v1` events.
- Keep agent-written completion receipts as candidate input only.
- Issue authority only from Stop.

## Stage 4A: Hook-Routed Spark Inspection

- Queue inspector jobs from UserPromptSubmit, PostToolUse, or Stop without
  waiting inside hooks.
- Spawn only `%USERPROFILE%\.codex\config.toml` standing-authorized Spark
  inspector roles.
- Keep every inspector read-only, route-limited, job-envelope-limited, and
  max-depth 1.
- Missing inspector jobs or reports block only completion claims, not
  PreToolUse.

## Stage 5: Fresh Session Verification

- Start a new Codex app session after wiring changes.
- Confirm SessionStart, UserPromptSubmit, PreToolUse, PostToolUse, and Stop
  events are observed.
- Confirm ordinary image generation is not blocked.
- Confirm reward-like completion claims do not receive authority.
- Confirm gate-issued receipt is produced only on accepted completion claims.

## Non-Goals

- Do not preserve V1 complexity for compatibility.
- Do not add new fallback completion routes.
- Do not make scores, PASS labels, tests, subagent reports, or final prose
  completion authority.
