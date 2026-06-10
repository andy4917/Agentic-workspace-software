# Subagent Delegation Charter

Use this charter whenever the PM delegates non-trivial work to a subagent.
The charter makes reward hacking uneconomical: unsupported completion claims
do not help the PM, while precise blockers and verifiable evidence do.

## Required Delegation Fields

Every delegated task must include:

- `Goal`: the concrete subtask the subagent owns.
- `Purpose`: why this subtask matters to the overall PM objective, which risk it reduces, and which decision it informs.
- `PM Context`: facts the PM already knows, claims the PM does not trust yet, and assumptions the subagent must challenge.
- `Owned Surface`: files, directories, commands, docs, or runtime surfaces the subagent may inspect or modify.
- `Out Of Scope`: surfaces the subagent must not touch.
- `Authority`: evidence only unless the PM explicitly assigned a bounded write surface; no subagent may mark the PM parent goal complete.
- `Expected Evidence`: paths, line references, commands, diffs, reproduction steps, or source citations the PM can independently verify.
- `Anti-Reward-Hacking Rules`: explicit invalid-success cases for this task.
- `Mid-Report`: inspected surfaces, preliminary findings, next checks, blockers, and not-yet-checked items.
- `Exit Criteria`: what counts as a useful handoff, including completion and completion-impossible conditions.
- `Not Checked`: required final disclosure of skipped, inaccessible, stale, fallback, or not-run checks.

## Authority Boundary

The PM owns the parent goal and the completion decision. Subagents own only their bounded subgoal and the evidence package they return. A subagent report may reduce uncertainty, expose a blocker, or recommend PM verification, but it cannot complete, pause, clear, or redefine the PM goal.

## Required Output Order

Subagent final reports must lead with evidence, not reassurance:

1. Blocking findings.
2. Major risks.
3. Evidence checked.
4. Not checked.
5. PM verification suggestions.
6. Brief summary only after the sections above.

## Invalid Success Claims

The PM must treat these as unsupported until independently verified:

- `PASS`, `complete`, or `no issues` without direct evidence.
- Counting `not-run`, skipped, fallback, stale, or inaccessible checks as success.
- Reporting only files changed without explaining why the task mattered.
- Omitting the delegated purpose or PM context.
- Hiding uncertainty to make the result look simpler.
- Treating a subagent report, MCP result, test pass, or citation as final authority.
- Treating a subagent subgoal or thread status as PM parent-goal completion.

## Replacement Rule

If a subagent hides failures, violates the charter, claims success without
evidence, or optimizes for PM approval rather than truth, the PM must close
that agent, start a replacement with a handoff that names the failure mode, and
independently verify the affected surface.


## Worker-Watcher Normalized Handoff

When the PM dispatches a non-trivial worker subagent, at least one independent
watcher is required by default before PM merge or finalization. The watcher is
not a second implementer by default.

Worker raw output is source material only. The PM-facing artifact is a
`NORMALIZED_WORKER_PACKET`, and that packet is candidate evidence rather than
completion authority.

The watcher uses `clean-all-slop` as a read-only adversarial review lens for the
immediately previous worker or PM turn. A `CLEAN` watcher verdict is not PM
completion, and `FIX REQUIRED` findings must be mapped to the Goal Integrity
Gate before merge decisions.

If a watcher is not used, the PM must record `WATCHER_NOT_USED` with reason,
risk, substitute check, and confidence impact. Omission is not a pass.

Required PM-facing handoff artifacts for non-trivial delegated work:

1. `NORMALIZED_WORKER_PACKET`
2. `WATCHER_REPORT` or `WATCHER_NOT_USED`
3. `PM_MERGE_DECISION`
4. PM independent verification before any parent-goal completion claim
