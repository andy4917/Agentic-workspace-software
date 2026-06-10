# Goal Integrity Gate

This is managed source for midpoint and pre-ship integrity checks. It is not a
hook and not completion authority.

## Purpose

The gate prevents goal drift, fake success, hidden fallback, skipped checks, and
raw worker reports from becoming PM completion claims.

## Adversarial Review Mapping

| read-only review result | Contamination score | Required action |
|---|---:|---|
| CLEAN with adequate checked evidence | C0 | Continue. |
| Only P3 findings | C1 | Correct wording, ledger, or minor cleanup before continuing. |
| Any P2 finding | C2 | Reset affected BUILD or VERIFY slice. |
| Any P1 finding | C3 | Quarantine current result or restart from last clean checkpoint. |
| Any P0 finding | C4 | Stop and request user approval. |

Use the highest severity when multiple findings exist. CLEAN is not completion authority.
If checked evidence is too narrow, downgrade to C1 or C2.

## Midpoint Gate

PM-only long-running work does not bypass midpoint audit.

1. Create `MIDPOINT_AUDIT_CONTEXT`.
2. Apply `clean-all-slop` read-only audit to the immediately previous relevant turn.
3. Map the verdict to C0-C4.
4. Decide continue, correct-plan, redo-from-checkpoint, quarantine-and-restart,
   or stop-for-user.

## Pre-Ship Gate

Before final completion, commit, PR, publish, merge, or terminal handoff:

1. Create `PRE_SHIP_AUDIT_CONTEXT`.
2. Apply `clean-all-slop` read-only audit to the immediately previous completion claim.
3. Map the verdict to C0-C4.
4. Block completion unless evidence, not-run reasons, residual risks, and PM
   independent verification are adequate.

## Completion Eligibility

Completion is eligible only when no unresolved P0/P1/P2 finding remains, no
material unchecked surface is hidden, PM independent verification exists, final
audit includes checked and not-run items, and worker evidence was normalized
with watcher coverage or an explicit `WATCHER_NOT_USED` record.
