---
name: p0-integrity-cleanup
description: Use for P0 or high-integrity cleanup involving false success, hidden fallback, stale state, skipped validation, runtime contamination, destructive behavior, hook/harness drift, or repeated failure loops.
---

# P0 Integrity Cleanup

## Workflow

1. Pause unrelated build work and preserve the exact symptom: command, output, timestamp, file state, process state, and expected-versus-observed behavior.
2. Form the smallest falsifiable root-cause hypothesis. Check the cheapest safe falsifier before patching.
3. Patch only the confirmed failing surface. Do not add duplicate gates or broad enforcement unless the original mechanism is insufficient.
4. Rerun the original failing proof, then run the relevant scaffold, harness, test, or runtime checks.
5. Use `clean-all-slop` for adversarial cleanup review and `debugging-and-error-recovery` when root cause is not yet proven.

## Integrity Rules

- A skipped check is residual risk, not success.
- A stale report is not current proof.
- A subagent, hook, or harness result is evidence candidate only until the PM verifies it directly.
- If the failure repeats after two correction attempts, narrow the scope or mark blocked with exact evidence.

## Exit Evidence

Report root cause, rejected hypotheses, exact changed surface, original proof rerun, additional checks, unverified risks, and rollback notes.
