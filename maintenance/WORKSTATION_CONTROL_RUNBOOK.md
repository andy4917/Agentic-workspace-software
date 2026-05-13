# Workstation Control Runbook

This runbook adapts the agent-delegated workstation meta-prompting plan for this
Codex home. It is managed source, not active runtime configuration, not a script,
and not completion authority.

## Operating Model

For workstation management, the main Codex session is the Workstation PM. The
user is the reviewer and owner of trust, irreversible, and publishing decisions;
the user is not the normal operator for inspection, formatting, evidence
gathering, tool selection, or routine cleanup.

The Workstation PM must start by classifying affected surfaces, then inspect
narrowly, then plan the smallest safe change. Worker, subagent, MCP, command, or
test outputs are candidate evidence only.

## Surface Classes

Use these surface names in plans, handoffs, review reports, and final audits:

- `active-runtime`: live files and settings read by Codex, shells, tools,
  package managers, MCP loaders, hooks, or plugins.
- `managed-source`: versioned policies, runbooks, templates, prompt recipes,
  inactive plans, and future control-plane material.
- `inventory`: factual snapshots, reports, manifests, and maps; inventory is
  evidence, not authority.
- `toolchain`: installed programs, package managers, shims, runtimes, PATH-like
  state, MCP stdio packages, and version selectors.
- `runtime-version`: specific Node, Python, Rust, package-manager, browser, or
  SDK versions that affect reproducibility.
- `logs-records`: SQLite logs, raw logs, archived logs, manifests, reports, and
  diagnostic traces.
- `secrets-credentials`: tokens, auth files, keys, private config, credential
  stores, and secret-adjacent metadata.
- `project-repository`: product repositories and project-specific configs
  outside this Codex home.
- `cache-generated-state`: temporary files, plugin caches, package caches,
  generated runtime state, build outputs, and app caches.
- `external-publish`: GitHub remotes, pushes, releases, public repositories,
  connectors, hosted services, and any operation that exposes local state
  outside the workstation.

## Risk Levels

Classify each proposed action before mutation:

- `observe`: read-only inspection, metadata review, summaries, or status
  checks. Normally allowed when task-relevant.
- `draft`: create or revise inactive planning documents, runbooks, or templates
  under managed source. Allowed inside requested scope.
- `controlled-change`: modify managed source, local wrappers, non-secret
  reports, or task-scoped files with verification and rollback notes.
- `high-risk-change`: active runtime config, hooks, trust settings, tool
  install/uninstall/upgrade, PATH or runtime version behavior, log movement,
  secret access, destructive filesystem action, or external publishing.

High-risk changes require explicit user intent for the risk boundary. If the
user has already clearly requested that boundary, execute narrowly and record
the evidence. If the risk is ambiguous, stop and ask.

## Default Lifecycle

1. Intake: restate the goal, likely affected surfaces, non-goals, and immediate
   risk boundary.
2. Snapshot: inspect only relevant surfaces before mutation. Do not read secret
   contents unless the user names the exact file.
3. Risk map: assign `observe`, `draft`, `controlled-change`, or
   `high-risk-change` to each proposed action.
4. Plan: name acceptance criteria, checks, rollback or recovery notes, and what
   will remain unresolved.
5. Execute: make only the bounded changes required for the accepted task.
6. Verify: run direct checks or record precise not-run reasons.
7. Review: challenge PM and subagent claims before treating evidence as usable.
8. Ship: report changed surfaces, checks run, checks not run, residual risks,
   rollback notes, and status.

## Worker-Watcher Gate

For non-trivial delegated workstation work, use
`maintenance/WORKER_WATCHER_NORMALIZED_HANDOFF.md` before PM merge. Worker raw
output must be converted to `NORMALIZED_WORKER_PACKET`, and an independent
watcher must return `WATCHER_REPORT` or the PM must record `WATCHER_NOT_USED`.

For long-running goals, use `maintenance/GOAL_INTEGRITY_GATE.md` at midpoint and
pre-ship. The gate maps `dont-even-try` `CLEAN`/`P0-P3` outcomes to `C0-C4`;
`CLEAN` is still only evidence, not completion authority.

## Delegation Prompt Shape

Use this shape for workstation subagents:

```text
Role: [PREFIX-NAME].
Goal: [bounded subtask].
Purpose: [risk reduced or decision informed].
PM Context: [known facts, untrusted claims, assumptions to challenge].
Owned Surface: [specific files, directories, commands, docs, or runtime surface].
Out Of Scope: [what must not be touched].
Authority: evidence only unless the PM grants a bounded write surface.
Expected Evidence: [paths, commands, line references, diffs, citations, outputs].
Anti-Reward-Hacking Rules: [invalid success claims].
Mid-Report: [when useful, inspected surfaces, early risks, next checks].
Exit Criteria: [useful handoff, blocker, or not-possible condition].
Not Checked: [mandatory skipped/inaccessible/stale/fallback disclosure].
```

Subagents must not claim parent-goal completion. The PM must independently
verify material claims before finalizing.

## Common Prompt Cards

Use these as compact prompt recipes:

- Workstation check: classify surfaces, inspect read-only, report unmanaged
  drift, high-risk areas, and next safe actions.
- Cleanup: do not delete or move first; classify candidates by reversibility,
  retention value, sensitivity, and Recycle Bin suitability.
- Codex setup: distinguish active runtime, managed source, hook wiring, runtime
  state, and versioned policy before edits.
- Logs: classify by source, age, size, sensitivity, duplicate likelihood, and
  recovery value; never permanently delete directly.
- Tool install/update: first identify need, existing coverage, affected
  surface, dependency chain, verification, and rollback.
- Broken workstation behavior: state the failure, form hypotheses, inspect
  relevant surfaces, confirm the first mismatch, then patch narrowly.

## Reporting Shape

Every non-trivial workstation report should include:

- outcome first;
- affected surfaces;
- risk level;
- direct evidence;
- approval points, if any;
- not checked;
- residual risks;
- next safe step.

Avoid broad words such as cleanup, sync, repair, optimize, or done unless the
concrete affected surface and evidence are also named.

## Adoption Status

Accepted for this Codex home on 2026-05-13 as a managed-source runbook. This
does not activate scripts, hooks, config changes, deletion logic, package
recipes, or automation by itself.
