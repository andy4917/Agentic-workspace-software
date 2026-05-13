# PM Workspace-Aligned Design Review - 2026-05-14

## Status

PASS for the managed-source design scope.

This review does not approve a release, activate hooks, mutate config, start
benchmark mode, write memory, or grant subagents completion authority.

## Scope

Reviewed the user-provided PM workspace plan artifacts and aligned them with the
tracked `.codex` GlobalSSOT governance layer.

User artifacts reviewed:

- `PM_WORKSPACE_ALIGNED_DESIGN_PLAN.md` from the user-provided desktop review artifact folder.
- `PM_WORKSPACE_REVIEW_FINDINGS.md` from the user-provided desktop review artifact folder.

Tracked local surfaces reviewed:

- `AGENTS.md`
- `README.md`
- `CODEX_WORKFLOW_APPLIED_REVIEW.md`
- `hooks/lightweight-codex-policy.json`
- `maintenance/WORKSTATION_CONTROL_RUNBOOK.md`
- `maintenance/WORKSTATION_MAINTENANCE.md`
- `maintenance/PROJECT_WORKFLOW_CHAIN.md`
- `maintenance/SUBAGENT_DELEGATION_CHARTER.md`
- `maintenance/WORKER_WATCHER_NORMALIZED_HANDOFF.md`
- `maintenance/GOAL_INTEGRITY_GATE.md`
- `maintenance/MULTI_AGENT_WORKFLOW_STATUS.md`
- `codex-goals/_template/FINAL_GOAL_AUDIT.md`

## Detailed Analysis

### Purpose And Non-Goals

The plan correctly frames the PM layer as a reinforcement overlay. It preserves
ordinary user prompting and avoids introducing a new SDLC. That fits the local
`AGENTS.md` contract, which keeps the user as reviewer rather than operator.

The non-goals are important and valid: no benchmark mode, no memory-as-authority,
no independent subagent ownership, no PM release-approval authority, and no
global-policy duplication into product repositories.

### Karpathy-Inspired Kernel

The plan's "think before coding", simplicity-first, surgical-change, and
goal-driven execution model is appropriate as a working-style kernel. It should
not become the completion contract. The completion contract remains evidence,
checks, not-run reasons, PM independent verification, residual risks, and
rollback notes.

### Workspace Authority

The plan's management/workflow/product split is conceptually useful, but local
truth must be discovered from this workstation. The active local GlobalSSOT root
is `%USERPROFILE%\.codex`; the earlier Linux-style roots are not local
authority unless a future task verifies them in the current environment.

The design must preserve the public-safe GitHub boundary. This repository may
record policies, runbooks, and safe reports, but must not publish secrets, raw
logs, sessions, private runtime state, SQLite state, or mutable local evidence.

### Instruction Priority

The previous plan's priority stack needed local correction. The safe local order
is current system/developer/tool/user instructions, scoped `AGENTS.md`, active
local hook/config policy when it actually applies, managed-source docs, tracked
files and runtime evidence, then memory and derived recall.

PM gates, Karpathy-inspired habits, and memory summaries cannot override higher
priority runtime instructions or scoped repository policy.

### Memory And RAG

The plan correctly says memory is support-only. The local repository currently
does not contain a tracked `contracts/memory_policy.json`, so the adopted design
must not depend on that file as a local proof. Memory writes should be reserved
for durable operational lessons and must exclude secrets, raw sensitive logs,
temporary guesses, and unreviewed subagent claims.

MemSearch or any similar index should be treated as a derived cache over
approved source paths. The source of truth remains tracked Markdown, active
policy, code, tests, runtime evidence, and direct checks.

### PM Reward And Score Structure

The reward model is sound: evidence-backed completion beats speed, small
reviewable diffs beat broad output, and truthful blocked/continue outcomes beat
unsupported success language. This matches the local anti-reward workflow and
reduces fake-success incentives.

The adopted design explicitly rejects self-score, stale report reuse, hidden
fallback, verification substitution, evaluator tampering, and treating subagent
reports as authority.

### Role System And Subagents

The plan correctly separates logical PM functions from completion authority.
However, local runtime policy requires explicit user authorization before
calling subagents. Capability flags and task size are not enough.

When subagents are authorized, their outputs remain candidate evidence. For
non-trivial worker use, watcher and normalizer handling must follow the
worker-watcher handoff. If omitted, `WATCHER_NOT_USED` must be recorded.

Subagents were not used in this pass because this prompt did not explicitly
authorize subagent dispatch under the active runtime rule. The substitute check
was PM-local review plus direct structural verification.

### Goal Governance

The plan's goal-driven loop is compatible with Codex Goal only if Goal remains
a long-running tracking marker. It is not a pass label, review approval, or test
proof. The parent-goal audit decision remains `complete`, `blocked`, or
`continue`.

### Project Workflow Chain

The `.codex` repository is `chain_ready` for this managed-source governance
change: it has scoped instructions, a README purpose, runbooks, verification
scripts, eval definitions, and Git publication rules.

For product repositories or other durable artifacts, the global
`PROJECT_WORKFLOW_CHAIN.md` preflight remains required before implementation.

## Changes Applied

- Added `maintenance/PM_WORKSPACE_ALIGNED_DESIGN.md`.
- Added an `AGENTS.md` pointer to that design record under PM responsibilities.

No active hook, config, toolchain, MCP, dependency, runtime state, memory, or
secret surface was changed.

## Structural Evaluation

PASS.

Criteria checked:

- local authority root is explicit;
- product-repository boundary is explicit;
- instruction priority is corrected;
- Goal is a tracking marker, not completion authority;
- Memory/RAG is support-only;
- subagents are explicit-authorization-bound and evidence-only;
- worker-watcher and goal-integrity gates remain candidate evidence;
- reward language penalizes fake success and hidden fallback;
- benchmark mode remains explicit and separate;
- public-safe GitHub boundary remains intact;
- rollback note exists;
- operational document is ASCII and under the local documentation size warning.

## Code Review

No blocking finding.

Review notes:

- Correctness: the new managed-source design records the user plan while
  reconciling it with the actual `.codex` root and local policy files.
- Readability: the design is sectioned by authority, memory, subagents, reward,
  workflow chain, and rollback.
- Architecture: the change avoids duplicating the full design into `AGENTS.md`
  and keeps active behavior out of inactive planning docs.
- Security: the change does not read or commit secrets, raw logs, SQLite state,
  sessions, config.toml, or private runtime files.
- Performance: no runtime path is changed.

## Verification

Checks run:

- `git diff --check`: pass.
- PM structural PowerShell check for required sections, ASCII, line count, and
  local-root consistency: pass.
- `powershell.exe -NoProfile -ExecutionPolicy Bypass -File maintenance/scripts/check-toolchain-sources.ps1`: pass.
- `%USERPROFILE%\.codex\toolchains\shims\python.cmd %USERPROFILE%\.codex\maintenance\scripts\codex_agent_harness.py verify`: pass.

## Not Run

- Live hook behavior was not changed or reloaded.
- Active `config.toml` was not edited.
- Memory/RAG indexing was not run because no memory recall or memory write was
  required for this managed-source change.
- Benchmark harnesses were not run because benchmark mode is out of scope.
- Subagents and watcher dispatch were not used because explicit runtime
  authorization for subagent dispatch was absent in this turn.
- A staged-diff sensitive-pattern scan was attempted after staging and blocked
  by the PreToolUse hook as secret or credential content access. This was not
  bypassed. Substitute checks were path-scoped readback of the changed files,
  public-safe path review, staged filename review, and the existing hook policy
  boundary.

## Residual Risks

- The new design is managed source only. Future live behavior still depends on
  the active runtime, hooks, tool availability, and session instructions.
- Existing generated verification reports are local ignored state and may change
  on the next harness run.
- Future tasks must still verify any claimed external workspace root before
  using it as local authority.

## Rollback

Revert these tracked paths:

- `AGENTS.md`
- `maintenance/PM_WORKSPACE_ALIGNED_DESIGN.md`
- `maintenance/reports/2026-05-14-pm-workspace-aligned-design-review.md`
