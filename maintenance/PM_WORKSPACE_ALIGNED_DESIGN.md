# PM Workspace-Aligned Design

This is managed source for the PM workspace-aligned operating design. It records
how the PM reinforcement plan is adopted into this `.codex` GlobalSSOT without
turning the plan into active runtime configuration by itself.

This document is not a hook, not a config file, not a benchmark protocol, and
not completion authority.

## Scope

- Active local root: `%USERPROFILE%\.codex`.
- Repository purpose: public-safe managed source for workstation governance,
  workflows, runbooks, verification scripts, toolchain wrappers, and handoff
  records.
- Product repositories under `%USERPROFILE%\code\Dev-Product` remain outside
  this GlobalSSOT scope unless the user explicitly targets them.
- The management/workflow/product split is a workspace authority model, not a
  reason to duplicate global policy into product repositories.

## Source Basis

This design reconciles the PM-aligned plan with the local managed source:

- user-provided `PM_WORKSPACE_ALIGNED_DESIGN_PLAN.md`;
- user-provided `PM_WORKSPACE_REVIEW_FINDINGS.md`;
- `AGENTS.md`;
- `README.md`;
- `CODEX_WORKFLOW_APPLIED_REVIEW.md`;
- `hooks/lightweight-codex-policy.json`;
- `maintenance/WORKSTATION_CONTROL_RUNBOOK.md`;
- `maintenance/WORKSTATION_MAINTENANCE.md`;
- `maintenance/PROJECT_WORKFLOW_CHAIN.md`;
- `maintenance/SUBAGENT_DELEGATION_CHARTER.md`;
- `maintenance/WORKER_WATCHER_NORMALIZED_HANDOFF.md`;
- `maintenance/GOAL_INTEGRITY_GATE.md`;
- `maintenance/MULTI_AGENT_WORKFLOW_STATUS.md`.

## Design Judgment

The plan is directionally correct and compatible with the current workstation
governance layer when treated as a reinforcement overlay:

- ordinary user prompts remain unchanged;
- the main session acts as PM for non-trivial work;
- Karpathy-inspired behavior is a working style, not the completion contract;
- Memory/RAG is support-only and cannot override current files or evidence;
- subagents produce candidate evidence, not parent-goal authority;
- reward and scorecard language favors verified, reviewable, truthful work;
- benchmark work remains excluded unless the user explicitly starts benchmark
  mode.

The plan needs local alignment before adoption. The corrections below are the
active interpretation for this repository.

## Local Alignment Corrections

### Authority Roots

Use `%USERPROFILE%\.codex` as the local GlobalSSOT root. Do not hard-code remote
or Linux-only roots as local truth. If a future task needs Dev-Management,
Dev-Workflow, or Dev-Product roots, first verify their local existence and the
current user scope.

### Instruction Priority

Use this priority for this repository:

```text
System, developer, tool, and current user instructions
> scoped AGENTS.md
> active local hook/config policy when it actually applies
> managed-source runbooks, templates, and reports
> project files, code, tests, and runtime evidence
> Memory/RAG, summaries, prior conversations, and derived indexes
```

Safety, security, release, and external-publish boundaries are not optional
style preferences. They remain enforced through the higher-priority current
instructions, scoped `AGENTS.md`, active hook policy, and specific runbooks.

### Goal Status Vocabulary

Use Codex Goal status as a tracking marker only. The parent-goal audit decision
uses `complete`, `blocked`, or `continue` as recorded in `AGENTS.md` and
`codex-goals/_template/FINAL_GOAL_AUDIT.md`.

User-facing reports may summarize a structural review as `PASS`, `FAIL`,
`BLOCKED`, or `WAIVED`, but a `PASS` label is never completion authority without
changed surfaces, direct checks, not-run reasons, PM independent verification,
residual risks, and rollback notes.

### Subagents And Role System

Current runtime policy requires explicit user authorization before calling
subagents. Capability flags and large task size are not authorization by
themselves.

When authorization exists, use the active local limits from
`hooks/lightweight-codex-policy.json` and the dispatch shape in
`maintenance/SUBAGENT_DELEGATION_CHARTER.md`. Logical functions such as worker,
auditor, verifier, explorer, reviewer, security, and observer are PM work
functions; they do not override runtime role availability or completion
authority.

When a non-trivial worker is used, apply
`maintenance/WORKER_WATCHER_NORMALIZED_HANDOFF.md`. If a watcher is omitted,
record `WATCHER_NOT_USED` with reason, risk, substitute check, and confidence
impact.

### Memory And RAG

Memory is a recall aid only. It can suggest where to look, but it cannot close a
goal or override current instructions, tracked files, tests, runtime evidence,
or direct verification.

Memory writes are allowed only for durable operational value:

- accepted decisions;
- invalidated assumptions;
- canonical proof commands;
- repeated false-pass patterns;
- user-stable operating preferences;
- release, rollback, migration, or control-plane lessons;
- subagent failure modes that should affect future delegation.

Do not write secrets, raw credential material, raw sensitive logs, broad
unreviewed summaries, temporary guesses, or benchmark results outside explicit
benchmark mode.

If Memento or another memory index is used, treat it as a derived support layer
over approved source paths. The human-readable Markdown, tracked policy, direct
runtime evidence, and current user instructions remain the source surfaces.

Normal workstation verification must prove the local PM memory support path
directly instead of leaving it as a residual risk. Use
`maintenance/scripts/memento-mcp-runtime.ps1 verify`, which checks the
Windows-native Memento MCP registration, HTTP health, PostgreSQL/pgvector
schema, Memento tool list, `get_skill_guide`, `context`, `recall`, and
`tool_feedback` without printing credential material. Legacy `memsearch` and
raw Markdown memories are retired historical surfaces, not active fallback.

### PM Reward And Score Alignment

The PM optimizes for gated correctness, not quick closure:

- evidence-backed completion over speed;
- small reviewable diffs over broad impressive output;
- acceptance-linked checks over generic green tests;
- truthful `blocked`, `continue`, or `waived with reason` over unsupported
  success language;
- clean-room or independent verification over self-claim;
- residual-risk visibility over polished summaries.

Negative-reward patterns include unsupported verification claims, hidden
fallbacks, stale report reuse, score or policy tampering, test deletion or
weakening without rationale, result fitting, and treating subagent output as
authority.

### Project Workflow Chain

For project repositories or durable project artifacts, run
`maintenance/PROJECT_WORKFLOW_CHAIN.md` before implementation. A global skill,
tool, MCP server, or frontend-only chain does not make an unrelated project
chain-ready.

For this `.codex` repository, the chain is currently `chain_ready` for managed
source governance work because it has scoped instructions, repository purpose,
runbooks, verification scripts, eval definitions, and Git publication rules.

### Benchmark Boundary

Benchmark work is out of scope unless explicitly requested. Normal PM workflow,
memory writes, workstation maintenance, and benchmark scoring must not be mixed
implicitly.

## Adoption Rules

Use this document as the compact design record for PM workspace alignment:

1. Keep `AGENTS.md` high-level and avoid copying this full design into it.
2. Keep active behavior changes in the correct active surface: hook policy,
   hook script, config, toolchain wrapper, or runbook.
3. Keep generated runtime files generated-only unless the user explicitly
   targets the generator or authoritative source.
4. Keep public GitHub commits free of secrets, raw logs, private runtime state,
   and mutable local evidence.
5. Keep completion claims tied to acceptance items and direct evidence.
6. Use `maintenance/scripts/check-staged-sensitive-diff.ps1` for pre-commit
   staged diff sensitive-pattern checks. It reports file, category, and line
   digest only; it does not print raw matched lines.
7. Use `maintenance/scripts/check-worktree-sensitive-diff.ps1` before claiming
   local dirty worktree changes are sensitive-pattern clean. It scans a
   temporary Git index and does not mutate the real staging area.

## Structural Evaluation Checklist

A future change to this design passes only when all applicable items are true:

- local authority root and product-repo boundary are explicit;
- current instruction priority is not weakened;
- Goal remains a tracking marker, not completion authority;
- Memory/RAG remains support-only;
- subagent use remains explicit-authorization-bound and evidence-only;
- worker-watcher and goal-integrity gates remain candidate evidence, not final
  authority;
- score/reward language penalizes fake success and hidden fallback;
- benchmark mode remains explicit and separate;
- public-safe GitHub boundary remains intact;
- direct checks, not-run reasons, residual risks, and rollback notes are
  reported before commit or push.

## Rollback

Revert this file and the corresponding `AGENTS.md` pointer if the PM
workspace-aligned design should no longer be part of the managed source. No
active runtime config, hook, toolchain, MCP, or secret state is changed by this
document alone.
