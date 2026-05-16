---
name: clean-all-slop
description: Combined adversarial review, failure exposure, root-cause analysis, and behavior-preserving cleanup workflow for AI-generated slop. Use when Codex must audit or fix hardcoding, legacy residue, hidden fallback, contamination, ignored instructions, bypass commands, reward hacking, fake tests, fake verification, unsupported success claims, bloated code, duplicate code, dead code, needless abstractions, weak boundaries, missing tests, UI/design slop, stale-state failures, tool failures, or hidden agent failure behavior. Use in read-only audit mode for skeptical review and midpoint checks; use cleanup mode only when the user asks to remove or correct the slop.
---

# Clean All Slop

## Mission

Find unsupported success, hidden fallback, and low-signal AI residue before it
ships. When a failure is found, expose it as useful evidence instead of hiding it
behind apology, retry, fallback, or reassuring prose. When fixes are in scope,
remove the slop with behavior locked by direct evidence and tests. When the user
asks only for review, stay read-only.

This skill is intended for code review, midpoint inspection, post-failure
analysis, broad-scope cleanup planning, or next-turn continuation after a large
agent pass. It is not a default ceremony for tiny tasks.

## Mode Selection

- Use **audit mode** when the request asks for review, skeptical audit, prior
  turn inspection, evidence checking, midpoint checking, continuation review, or
  contamination detection. Do not edit.
- Use **failure handoff mode** when a failure, contradiction, false pass, stale
  state, tool error, missing evidence, or unsupported completion claim is found
  and the user did not already authorize repair.
- Use **cleanup mode** when the request asks to clean, refactor, deslop, fix, or
  remove the issues. Keep changes scoped to the requested files or feature.
- If mode is ambiguous, start with audit mode. Report findings and preserve a
  failure handoff when needed. Proceed to cleanup only when fixes are already in
  scope or the user explicitly authorized them.

## Audit Mode

1. Reconstruct the claim: user goal, promised changes, claimed checks, skipped
   checks, and completion wording.
2. Compare claims to artifacts: touched files, diffs, generated files,
   metadata, indexes, config, runtime state, hook state, MCP/session state, and
   unrelated changes.
3. Attack validation: require command output, exit status, path evidence, line
   references, screenshots, or reproducible observations. Reject stale output,
   partial runs, hidden failures, pass labels, and "looks good" claims.
4. Search for defect classes:
   - Hardcoding: fixed paths, IDs, magic constants, test-only values, locale
     assumptions.
   - Legacy residue: old paths, duplicate mechanisms, stale comments,
     placeholders, abandoned files.
   - Hidden fallback: swallowed errors, fake defaults, degraded behavior
     reported as success.
   - Contamination: leaked prompt/context, unrelated artifacts,
     machine-specific assumptions, secret-adjacent material.
   - Instruction skipping: ignored user constraints, AGENTS.md, skills,
     read-only limits, language rules, verification rules.
   - Bypass behavior: commands or tools that evade hooks, tests, review,
     policy, or the normal workflow.
   - Reward hacking: optimizing for PASS, green output, or reassuring prose
     instead of the user goal.
   - Slop: vague implementation, brittle parsing, broad exceptions, unclear
     ownership, unreviewed generated code.
5. Lead with findings. Mark any actionable issue `FIX REQUIRED`; mark no
   actionable issue `CLEAN` with checked evidence, not-checked items, and
   residual risk.

## Failure Capsule

When a failure, contradiction, false pass, blocked check, stale state, tool
error, or unsupported claim is discovered, preserve it as evidence. Do not smooth
it over.

A failure capsule must include:

- Expected: what should have happened.
- Observed: what actually happened.
- First mismatch: the earliest confirmed divergence from the claim, plan, or
  expected behavior.
- Evidence: command, path, line, diff, screenshot, log excerpt, or tool output.
- Changed surface: files, config, runtime state, generated output, hook state,
  MCP/session state, cache, database, toolchain, or external surface.
- Current risk: what may be wrong if this is ignored.
- Next-turn target: the smallest causal question to answer next.
- Unsafe next actions: actions that would destroy evidence, hide the failure, or
  replace the failed proof with easier evidence.

## Compact Failure Taxonomy

Classify the failure before repair. Use the smallest label set that explains the
observed evidence.

- **Claim failure**: final wording claimed more than the evidence supports.
- **Validation failure**: a check failed, was partial, stale, not actually run,
  or was replaced by weaker evidence.
- **Tool failure**: shell, path, sandbox, MCP, permission, package, runtime, or
  command execution failed.
- **Instruction failure**: user constraints, scoped instructions, read-only
  limits, skill rules, or language requirements were skipped.
- **State failure**: cache, generated files, session state, hook state, DB state,
  browser state, MCP reload, or runtime injection was stale or mismatched.
- **Boundary failure**: unrelated files, secrets, external surfaces, destructive
  actions, or out-of-scope areas were touched.
- **Design failure**: implementation works mechanically but fails product intent,
  UX clarity, hierarchy, accessibility, or visual quality.
- **Maintenance failure**: the change adds duplicate mechanisms, hidden fallback,
  dead code, unclear ownership, over-abstraction, or drift-prone policy.

## Root-Cause Ladder

Do not stop at a symptom. Stop at the shallowest evidenced cause that explains
all observed evidence.

1. **Reproduce**: can the failure or mismatch be observed again?
2. **Boundary**: which file, command, state, tool, or workflow surface first
   diverged?
3. **Mechanism**: what code, config, dependency, tool behavior, or assumption
   caused the divergence?
4. **Masking**: did fallback, retry, stale output, broad exception handling, or
   final prose hide the divergence?
5. **Prevention**: what check, test, guard, workflow note, or deletion prevents
   recurrence?

Do not claim root cause until the mechanism level is evidenced. If mechanism is
not yet known, report `root cause not proven` and preserve the next-turn target.

## Turn Boundary Rule

When the active turn discovers a serious failure, contradiction, false pass, or
stale-state mismatch, prefer exposing the failure and preserving evidence over
rushing a repair in the same turn.

Repair in the same turn only when:

- cleanup mode is already authorized;
- the root cause mechanism is directly evidenced;
- the fix is narrow and behavior-preserving, unless the user requested behavior
  change;
- the failed proof can be rerun immediately.

Otherwise, produce `FAILURE_HANDOFF` and make the next turn an incident-analysis
or cleanup-goal turn.

## Same-Proof Rerun Rule

After fixing a confirmed failure, rerun the exact proof that failed before adding
new evidence. A different passing command does not clear the original failure
unless the original proof is no longer applicable and that reason is stated.

A valid repair report includes:

- failed proof before fix;
- change made;
- same proof after fix;
- additional regression proof, if applicable;
- checks not run and why.

## No Self-Repair Theater

Do not convert failure into reassuring prose. Acknowledging a mistake is not a
repair. A repair requires causal evidence, a bounded change, and a rerun of the
failed proof.

Invalid recovery patterns:

- apology without root-cause evidence;
- replacing a failed check with an easier passing check;
- adding retries, sleeps, broad catch blocks, or silent defaults without proving
  the cause;
- editing final wording to sound successful while evidence remains missing;
- treating `not reproduced` as fixed without explaining the reproduction gap;
- turning hard failures into warnings without an explicit degraded-mode contract.

## Masking Patch Ban

A patch is masking slop when it makes the symptom disappear without proving the
cause.

Treat these as suspicious until justified by evidence:

- broad try/catch;
- silent default values;
- retry loops or sleep/wait timing patches;
- feature flags that bypass the failing path;
- test expectation weakening;
- snapshot updates without behavioral explanation;
- removing assertions instead of fixing behavior;
- converting hard failures into warnings;
- alternate execution paths that skip the broken dependency.

Allowed fallback or degraded mode must state:

- root cause or explicit uncertainty;
- why fallback is legitimate compatibility or fail-safe behavior;
- proof for the primary path;
- proof for the fallback path;
- how users or operators detect degraded mode.

## Evidence Freshness

Evidence is stale if it was produced before the relevant file, config,
dependency, runtime state, hook state, MCP/session state, generated artifact, or
cache changed.

Do not use stale evidence as validation. If stale evidence is the only available
information, report it as historical context.

Fresh evidence should include at least one of:

- command and exit status;
- timestamp or current run marker;
- current git diff/status when relevant;
- path and line evidence from the current file state;
- screenshot or runtime observation from the current build/session.

## Cleanup Mode

1. Lock behavior first:
   - Identify behavior that must not change.
   - Run existing targeted regression checks before editing.
   - Add the narrowest missing regression coverage when practical.
   - For preserved compatibility or fail-safe behavior, cover both primary and
     fallback paths.
2. Plan before editing:
   - List the exact smells to remove.
   - Bound the pass to the requested files, changed-files list, or feature.
   - Order fixes from safest/highest-signal to riskiest.
   - Do not mix unrelated refactors into the cleanup.
3. Inventory fallback-like code:
   - Search for temporary workarounds, bypasses, broad compatibility shims,
     swallowed errors, silent defaults, and duplicate alternate execution paths.
   - Classify each finding as **masking fallback slop** or **grounded
     compatibility/fail-safe fallback**.
   - Prefer root-cause repair, deletion, boundary repair, or explicit failure
     behavior before preserving fallback paths.
   - Escalate broad, ambiguous, cross-layer fallback questions before editing.
4. Execute one smell at a time:
   - Resolve masking fallback slop first.
   - Delete dead code.
   - Remove duplication.
   - Simplify naming, error handling, and boundaries.
   - Reinforce tests where behavior was weakly protected.
   - Re-run the relevant check after each risky pass.
5. Keep the diff minimal:
   - No new abstractions unless they remove real duplication or match an
     existing local pattern.
   - No dependency additions unless explicitly required.
   - No nearby cleanup outside the requested scope.

## Goal Bridge

If cleanup requires more than one bounded pass, touches workflow/toolchain/runtime
surfaces, exposes repeated agent failure behavior, or cannot be completed safely
in the current turn, convert the result into a remediation goal instead of
continuing ad hoc.

A remediation goal should include:

- failure capsule summary;
- affected surfaces;
- priority: P0 immediate blocker, P1 correctness/security, P2 maintainability,
  or P3 hygiene;
- acceptance criteria;
- same-proof rerun requirement;
- rollback, quarantine, or deletion plan;
- checks not yet run;
- residual risks.

If a Goal tool is available, create or update one bounded Goal. If no Goal tool
is available, output a `GOAL_SPEC` block for the next turn.

## UI And Design Slop Signals

Treat visual issues as context-sensitive signals, not absolute bans:

- Korean body copy below 14px needs explicit dense-system justification.
- Avoid gratuitous shadows on every surface, logo, icon, or card.
- Trim repeated eyebrow/title/description stacks and generic filler copy.
- Question default blue/purple palettes when there is no brand or semantic
  rationale.
- Avoid reflexive uniform card grids when product context calls for rhythm,
  asymmetry, or stronger hierarchy.
- Tone down extreme gradients unless the brand or campaign requires them.

## Output Shapes

Audit report:

```text
[P0-P3] FIX REQUIRED: <short title>
Evidence: <path + line, diff hunk, command output, or transcript claim>
Why it matters: <specific risk>
Required correction: <remove, change, or re-verify>
```

Clean result:

```text
CLEAN
Checked: <read-only evidence inspected>
Not checked: <skipped checks and reasons>
Residual risk: <remaining uncertainty, or "none identified">
```

Failure handoff:

```text
FAILURE_HANDOFF
Status: failed | blocked | contradicted | unproven
Original claim: <what was claimed or attempted>
Expected: <expected behavior or evidence>
Observed: <actual result>
First mismatch: <earliest confirmed divergence>
Evidence preserved: <paths, command outputs, diffs, logs, screenshots>
Changed surface: <file | config | runtime | hook | MCP/session | cache | DB | toolchain | external>
Failure class: <claim | validation | tool | instruction | state | boundary | design | maintenance>
Root-cause ladder: <reproduce | boundary | mechanism | masking | prevention, with current stopping point>
Not yet concluded: <what must not be assumed>
Next-turn target: <smallest causal question>
Unsafe next actions: <actions that would hide or destroy evidence>
```

Cleanup report:

```text
CLEAN ALL SLOP REPORT
Scope: <files or feature area>
Behavior Lock: <tests/checks added or run before editing>
Cleanup Plan: <bounded smells and order>
Failure Capsules: <none or failure -> taxonomy -> root-cause ladder position>
Fallback Findings: <none or finding -> classification -> action>
Passes Completed: <one-smell-at-a-time fixes>
Same-Proof Rerun: <failed proof before -> proof after>
Quality Gates: <regression, lint, typecheck, tests, static/security as applicable>
Changed Files: <path -> simplification>
Not Checked: <checks skipped and why>
Remaining Risks: <none or deferred issue>
```

Goal spec:

```text
GOAL_SPEC
Goal: <bounded remediation objective>
Why now: <failure capsule summary and risk>
Affected surfaces: <files/config/runtime/toolchain/etc.>
Priority: P0 | P1 | P2 | P3
Acceptance criteria: <observable completion criteria>
Required proof: <same-proof rerun and regression checks>
Rollback/quarantine: <how to undo or isolate>
Not yet run: <checks still missing>
Residual risk: <known uncertainty>
Next action: <first bounded step>
```

## Hard Rules

- A review finding a real blocker is successful.
- A failure exposed with preserved evidence is useful progress.
- A passing check is evidence, not completion authority.
- Unsupported success claims are defects until independently verified.
- Stale evidence is historical context, not validation.
- In audit mode, do not repair.
- In failure handoff mode, do not rush repair unless cleanup mode is already in
  scope and same-proof rerun is possible.
- In cleanup mode, preserve behavior unless the user explicitly asked for a
  behavior change.
- Do not hide failure with apology, alternate checks, fallback, broad exception
  handling, or polished final prose.
- Finish with `SKILL_EVIDENCE used: clean-all-slop` plus checked evidence,
  not-run checks, and residual risk when this skill materially shaped the work.
