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
- `logs-records`: SQLite logs, raw logs, manifests, reports, and diagnostic
  traces. Archived log roots are retired residue unless current runtime evidence
  proves active use.
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

## Control-Plane Alignment

Use this section when the task asks to audit or remediate workstation
control-plane drift across config, instructions, hooks, scripts, skills, MCP
runtime notes, toolchain policy, operational workflows, generated state, logs,
or records.

The objective is to make future Codex agents easier to operate correctly without
adding ceremony. Do not create another workflow layer when an existing source can
be clarified, consolidated, or referenced.

### Two-Pass Workflow

1. Read-only conflict audit: inspect narrowly but sufficiently, and build a
   control-plane map before editing.
2. Conservative adjustment: patch only after direct evidence identifies a
   duplicate, contradiction, stale rule, hidden fallback, completion-authority
   leak, workflow overreach or underreach, toolchain ambiguity, MCP/session
   drift, skill overlap, generated-state contamination, secret-boundary
   weakness, fake verification, or maintenance bloat.

### Authority Model

Before editing, name the authority chain for each affected topic:

- canonical source;
- secondary references;
- active runtime surface;
- generated or inventory surfaces;
- deprecated or historical surfaces;
- verification command or check;
- rollback or recovery note.

If two surfaces conflict, choose the canonical source first, update references
to point to it, and mark historical surfaces clearly. Do not patch multiple
surfaces blindly.

### Remediation Order

1. Fix dangerous contradictions.
2. Fix active-runtime or toolchain ambiguity.
3. Fix stale references that can cause wrong tool or session behavior.
4. Consolidate duplicate workflow rules.
5. Trim over-broad final evidence or hook requirements only when safety is
   preserved.
6. Update reports or handoff docs last.

### Failure Capsule

When the audit finds a failure, contradiction, false pass, stale state, hidden
fallback, or unsupported claim, preserve it instead of smoothing it over:

```text
Expected:
Observed:
First mismatch:
Evidence:
Affected surface:
Failure class:
Current risk:
Next-turn analysis target:
Unsafe next actions:
```

Classify failures with the smallest accurate set from: `claim failure`,
`validation failure`, `tool failure`, `instruction failure`, `state failure`,
`boundary failure`, `design failure`, or `maintenance failure`.

Do not claim root cause until the mechanism level is evidenced:
reproduce, boundary, mechanism, masking, prevention.

### Same-Proof Rerun And Goal Bridge

If a change fixes a confirmed failure, rerun the exact proof that failed before
using substitute evidence. A different passing check clears the issue only when
the original proof is no longer applicable and that reason is stated.

If the adjustment cannot be finished safely in one bounded pass, touches an
unapproved high-risk boundary, or exposes repeated agent failure behavior that
needs longer analysis, stop and produce a `GOAL_SPEC` with goal, failure capsule
summary, affected surfaces, priority, acceptance criteria, same-proof rerun,
verification commands, rollback or quarantine plan, not-yet-checked items,
residual risks, and the next bounded action.

### Alignment Report Shape

When reporting a non-trivial control-plane alignment pass, lead with outcome and
include:

- scope inspected;
- risk level;
- canonical authority map;
- findings with surface, evidence, why it matters, and action taken or required;
- changes made;
- conflicts resolved;
- duplicates consolidated;
- stale or historical surfaces;
- failure capsules, when present;
- verification checked and not checked;
- same-proof rerun status;
- sensitive-boundary checks;
- rollback;
- residual risks;
- next safe step.

## Worker-Watcher Gate

For non-trivial delegated workstation work, use
`maintenance/WORKER_WATCHER_NORMALIZED_HANDOFF.md` before PM merge. Worker raw
output must be converted to `NORMALIZED_WORKER_PACKET`, and an independent
watcher must return `WATCHER_REPORT` or the PM must record `WATCHER_NOT_USED`.

For long-running goals, use `maintenance/GOAL_INTEGRITY_GATE.md` at midpoint and
pre-ship. The gate maps `clean-all-slop` read-only audit `CLEAN`/`P0-P3`
outcomes to `C0-C4`;
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
- Cleanup: do not delete or move first; classify candidates by active ownership,
  retention value, sensitivity, and path-boundary safety. After explicit user
  authorization, delete retired residue directly instead of creating another
  archive.
- Codex setup: distinguish active runtime, managed source, hook wiring, runtime
  state, and versioned policy before edits.
- Logs: classify by source, age, size, sensitivity, duplicate likelihood, and
  recovery value; never delete active SQLite WAL/SHM companions directly.
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
