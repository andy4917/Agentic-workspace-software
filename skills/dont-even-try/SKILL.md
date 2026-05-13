---
name: dont-even-try
description: Lightweight read-only adversarial review of the immediately previous Codex turn. Use when the user asks for a skeptical third-party audit of prior work, especially to find hardcoding, legacy residue, hidden fallback, contamination, ignored instructions, bypass commands, reward hacking, fake tests, fake verification, unsupported success claims, or sloppy work that must be removed or corrected.
---

# Don't_Even_Try

## Mission

Review the immediately previous turn as a hostile but fair third-party reviewer. Assume success claims are untrusted until proven by direct evidence. Stay read-only unless the user separately asks for fixes.

## Read-Only Rules

- Inspect transcripts, tool calls, changed files, diffs, validation output, and governing instructions.
- Prefer read-only commands: `git status`, `git diff`, `git show`, `rg`, `Get-Content`, directory listings.
- Do not edit, stage, commit, push, delete, install, reconfigure, or run mutating checks.
- If a useful check may write files, caches, logs, or state, mark it `not run` and explain why.

## Review Pass

1. Reconstruct the prior claim: user goal, promised changes, claimed checks, skipped checks, and completion wording.
2. Compare claims to artifacts: touched files, diffs, metadata, generated files, indexes, configs, and unrelated changes.
3. Attack validation: confirm command output or exit status exists; reject stale output, partial runs, hidden failures, pass labels, and "looks good" claims.
4. Search for these defect classes:
   - Hardcoding: fixed paths, IDs, magic constants, test-only values, locale assumptions.
   - Legacy residue: old paths, duplicate mechanisms, stale comments, placeholders, abandoned files.
   - Hidden fallback: swallowed errors, fake defaults, degraded behavior reported as success.
   - Contamination: leaked prompt/context, unrelated artifacts, machine-specific assumptions, secret-adjacent material.
   - Instruction skipping: ignored user constraints, AGENTS.md, skills, read-only limits, language rules, verification rules.
   - Bypass behavior: commands or tool use that evade hooks, tests, review, policy, or normal workflow.
   - Reward hacking: optimizing for PASS, green output, or reassuring prose instead of the user goal.
   - Slop: vague implementation, brittle parsing, broad exceptions, unclear ownership, unreviewed generated code.

## Verdict

Lead with findings. If any issue exists, mark it `FIX REQUIRED`. If no actionable issue is found, mark the result `CLEAN`.

Finding format:

```text
[P0-P3] FIX REQUIRED: <short title>
Evidence: <path + line, diff hunk, command output, or transcript claim>
Why it matters: <specific risk>
Required correction: <remove, change, or re-verify>
```

Severity:

- `P0`: destructive, secret exposure, policy bypass, severe data risk.
- `P1`: user goal likely unmet, invalid validation, major regression, instruction breach.
- `P2`: correctness, maintainability, fallback, legacy residue, scope risk.
- `P3`: minor slop, weak evidence, unclear wording, cleanup.

Clean format:

```text
CLEAN
Checked: <read-only evidence inspected>
Not checked: <skipped checks and reasons>
Residual risk: <remaining uncertainty, or "none identified">
```

## Hard Rule

Do not repair during this skill. A review that finds a real blocker is successful. Unsupported success claims are defects until independently verified.
