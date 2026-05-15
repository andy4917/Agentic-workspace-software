---
name: clean-all-slop
description: Combined adversarial review and behavior-preserving cleanup workflow for AI-generated slop. Use when Codex must audit or fix hardcoding, legacy residue, hidden fallback, contamination, ignored instructions, bypass commands, reward hacking, fake tests, fake verification, unsupported success claims, bloated code, duplicate code, dead code, needless abstractions, weak boundaries, missing tests, or UI/design slop. Use in read-only audit mode for skeptical review requests and in cleanup mode when the user asks to remove or correct the slop.
---

# Clean All Slop

## Mission

Find unsupported success, hidden fallback, and low-signal AI residue before it
ships. When fixes are in scope, remove the slop with behavior locked by direct
evidence and tests. When the user asks only for review, stay read-only.

## Mode Selection

- Use **audit mode** when the request asks for review, skeptical audit, prior
  turn inspection, evidence checking, or contamination detection. Do not edit.
- Use **cleanup mode** when the request asks to clean, refactor, deslop, fix, or
  remove the issues. Keep changes scoped to the requested files or feature.
- If mode is ambiguous, start with audit mode, report findings, then ask or
  proceed only when the user has already authorized fixes.

## Audit Mode

1. Reconstruct the claim: user goal, promised changes, claimed checks, skipped
   checks, and completion wording.
2. Compare claims to artifacts: touched files, diffs, generated files,
   metadata, indexes, config, and unrelated changes.
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

Cleanup report:

```text
CLEAN ALL SLOP REPORT
Scope: <files or feature area>
Behavior Lock: <tests/checks added or run before editing>
Cleanup Plan: <bounded smells and order>
Fallback Findings: <none or finding -> classification -> action>
Passes Completed: <one-smell-at-a-time fixes>
Quality Gates: <regression, lint, typecheck, tests, static/security as applicable>
Changed Files: <path -> simplification>
Not Checked: <checks skipped and why>
Remaining Risks: <none or deferred issue>
```

## Hard Rules

- A review finding a real blocker is successful.
- A passing check is evidence, not completion authority.
- Unsupported success claims are defects until independently verified.
- In audit mode, do not repair.
- In cleanup mode, preserve behavior unless the user explicitly asked for a
  behavior change.
