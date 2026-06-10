"""Worker-watcher managed-source templates for the Codex harness."""

ROLE_CONFIGS = {}
SKILL_TEMPLATES = {}
DELEGATION_CHARTER = ""
EVAL_TEMPLATES = {}

ROLE_CONFIGS["agents/observer.toml"] = """# Managed by codex-agent-harness.
name = "observer"
description = "Independent watcher for worker handoff integrity, goal drift, evidence quality, and instruction compliance."
developer_instructions = \"\"\"
Goal: observe a bounded worker task and detect drift, contamination, unsupported evidence, instruction violations, and unsafe merge risk.
Use clean-all-slop in read-only audit mode as the adversarial review lens for the immediately previous worker or PM turn.
You are not a second implementer by default.
You do not repair during the watcher pass.
You do not complete the PM parent goal.
You do not approve a worker by summary.

Required output sections:
- Watcher Role
- Watched Subject
- Active Parent Goal
- Bounded Worker Goal
- Prior Claim Reconstructed
- Artifact Comparison
- Validation Attack
- Defect Classes Checked
- Adversarial Review Verdict
- Findings
- Checked
- Not Checked
- Residual Risk
- PM Merge Recommendation

Return a WATCHER_REPORT artifact.
\"\"\"
nickname_candidates = ["OBS-Watcher", "OBS-DriftGuard", "OBS-Sentinel"]
# nickname_prefix = "OBS"
# required_delegation_fields, required_output_sections, success_claim_policy,
# reward_hacking_guard, and worker-watcher rules are documented in
# maintenance/SUBAGENT_DELEGATION_CHARTER.md.
"""

DELEGATION_CHARTER += """

## Worker-Watcher Normalized Handoff

When the PM dispatches a non-trivial worker subagent, at least one independent
watcher is required by default before PM merge or finalization. The watcher is
not a second implementer by default.

Worker raw output is source material only. The PM-facing artifact is a
`NORMALIZED_WORKER_PACKET`, and that packet is candidate evidence rather than
completion authority.

The watcher uses `clean-all-slop` in read-only audit mode as an adversarial
review lens for the immediately previous worker or PM turn. A `CLEAN` watcher
verdict is not PM completion, and `FIX REQUIRED` findings must be mapped to the
Goal Integrity Gate before merge decisions.

If a watcher is not used, the PM must record `WATCHER_NOT_USED` with reason,
risk, substitute check, and confidence impact. Omission is not a pass.

Required PM-facing handoff artifacts for non-trivial delegated work:

1. `NORMALIZED_WORKER_PACKET`
2. `WATCHER_REPORT` or `WATCHER_NOT_USED`
3. `PM_MERGE_DECISION`
4. PM independent verification before any parent-goal completion claim
"""

WORKER_WATCHER_TEMPLATES = {
    "maintenance/WORKER_WATCHER_NORMALIZED_HANDOFF.md": """# Worker-Watcher Normalized Handoff

This is managed source for delegated worker integrity. It is not active runtime
configuration, not a hook, and not completion authority.

## Operating Rule

Non-trivial worker dispatch requires at least one independent watcher by default.
Raw worker output is not PM-ready until normalized. Worker complete is not PM complete.
Watcher CLEAN is not PM complete.

```text
PM Goal
  -> Progress Ledger
  -> Worker Dispatch
      -> Worker Result
      -> Watcher Dispatch
          -> clean-all-slop read-only audit of the immediately previous worker or PM turn
          -> WATCHER_REPORT
      -> Normalize output with maintenance/templates/NORMALIZED_WORKER_PACKET.md
  -> PM_MERGE_DECISION
  -> PM Independent Verification
  -> Goal Integrity Gate
```

## Required Artifacts

- `NORMALIZED_WORKER_PACKET`: evidence-first packet extracted from worker output.
- `WATCHER_REPORT`: read-only integrity review using `clean-all-slop` audit mode.
- `WATCHER_NOT_USED`: required when a watcher is omitted.
- `PM_MERGE_DECISION`: PM decision to accept, rework, reject, quarantine, or continue.

## Watcher Default

The default watcher role is `OBS-Watcher`. It uses `clean-all-slop` to attack
claims, validation, instruction compliance, hidden fallback, contamination,
reward hacking, and unsupported success language. It does not repair.

## Merge Rules

- Raw worker output is noise until normalized.
- Normalized output is candidate evidence only.
- Watcher findings are candidate evidence only.
- PM merge requires accepted claims, rejected claims, changed surfaces, checks
  run, checks not run, residual risks, and a PM recheck plan.
- PM final completion still requires the final goal audit.

## Watcher Omission

When a watcher cannot be dispatched, record `WATCHER_NOT_USED` before merge.
Impact on confidence must be `normal`, `degraded`, or `blocked`. High-risk
surfaces without a watcher should default to degraded or blocked assurance.

## Adoption Status

Accepted as managed source for the Codex workstation control plane. Hook support
may enforce parts of this later, but this document alone does not mutate hooks.
""",
    "maintenance/GOAL_INTEGRITY_GATE.md": """# Goal Integrity Gate

This is managed source for midpoint and pre-ship integrity checks. It is not a
hook and not completion authority.

## Purpose

The gate prevents goal drift, fake success, hidden fallback, skipped checks, and
raw worker reports from becoming PM completion claims.

## Adversarial Review Mapping

Use `clean-all-slop` in read-only audit mode on the immediately previous
relevant worker, PM, validation, merge, or completion claim.

| Adversarial review result | Contamination score | Required action |
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
2. Apply `clean-all-slop` read-only audit mode to the immediately previous relevant turn.
3. Map the verdict to C0-C4.
4. Decide continue, correct-plan, redo-from-checkpoint, quarantine-and-restart,
   or stop-for-user.

## Pre-Ship Gate

Before final completion, commit, PR, publish, merge, or terminal handoff:

1. Create `PRE_SHIP_AUDIT_CONTEXT`.
2. Apply `clean-all-slop` read-only audit mode to the immediately previous completion claim.
3. Map the verdict to C0-C4.
4. Block completion unless evidence, not-run reasons, residual risks, and PM
   independent verification are adequate.

## Completion Eligibility

Completion is eligible only when no unresolved P0/P1/P2 finding remains, no
material unchecked surface is hidden, PM independent verification exists, final
audit includes checked and not-run items, and worker evidence was normalized
with watcher coverage or an explicit `WATCHER_NOT_USED` record.
""",
    "maintenance/templates/GOAL_CAPSULE.md": """# GOAL_CAPSULE

## Original User Objective

...

## Parent Goal

...

## Acceptance Criteria

- ...

## Boundaries

- In scope:
- Out of scope:

## Evidence Required

- Direct PM checks:
- Worker packets:
- Watcher reports:

## Completion Authority

Goal is tracking only. PM completion requires final audit evidence.
""",
    "maintenance/templates/WORKER_FINAL.md": """# WORKER_FINAL

## Worker

...

## Bounded Subgoal

...

## Status

complete | partial | blocked | suspect

## Claims

1. ...

## Evidence

| Claim | Evidence |
|---|---|

## Changed Surfaces

| Surface | File/Path | Risk |
|---|---|---|

## Commands Run

| Command | Result | Notes |
|---|---|---|

## Commands Not Run

| Command/Check | Reason | Risk |
|---|---|---|

## Not Checked

...

## Residual Risks

...

## Parent Goal Boundary

This worker does not complete the PM parent goal.
""",
    "maintenance/templates/NORMALIZED_WORKER_PACKET.md": """# NORMALIZED_WORKER_PACKET

## Worker

...

## Subgoal

...

## Status

complete | partial | blocked | suspect

## Merge Candidate

yes | no | needs-pm-review | reject

## Authority

This packet is candidate evidence, not completion authority.

## Claims Accepted For PM Review

1. ...

## Claims Rejected Or Unsupported

1. ...

## Evidence Index

| Claim | Evidence | PM Recheck Needed |
|---|---|---|

## Changed Surfaces

| Surface | File/Path | Risk |
|---|---|---|

## Commands Run

| Command | Result | Notes |
|---|---|---|

## Commands Not Run

| Command/Check | Reason | Risk |
|---|---|---|

## Residual Risks

...

## Recommended PM Action

merge-review | request-rework | spawn-replacement | block | continue
""",
    "maintenance/templates/WATCHER_REPORT.md": """# WATCHER_REPORT

## Watcher Role

OBS-Watcher | REV-Integrity | VAL-Skeptic | other

## Watched Subject

PM turn | worker final | worker mid-report | validation claim | pre-ship claim

## Active Parent Goal

...

## Bounded Worker Goal

...

## Prior Claim Reconstructed

...

## Artifact Comparison

...

## Validation Attack

...

## Defect Classes Checked

- hardcoding:
- legacy residue:
- hidden fallback:
- contamination:
- instruction skipping:
- bypass behavior:
- reward hacking:
- slop:

## Adversarial Review Verdict

CLEAN | FIX REQUIRED

## Findings

[P0-P3] FIX REQUIRED: ...

## Checked

...

## Not Checked

...

## Residual Risk

...

## PM Merge Recommendation

accept-for-review | request-rework | reject | quarantine | stop-for-user
""",
    "maintenance/templates/WATCHER_NOT_USED.md": """# WATCHER_NOT_USED

## Reason

runtime unavailable | task tiny | user forbade subagents | emergency stop | other

## Risk

...

## Substitute Check

...

## Impact On Confidence

normal | degraded | blocked

## PM Note

Watcher omission is not a pass.
""",
    "maintenance/templates/MIDPOINT_AUDIT_CONTEXT.md": """# MIDPOINT_AUDIT_CONTEXT

## Original User Objective

...

## Parent Goal

...

## Current Progress

...

## Current Work Since Start

...

## Worker Packets Since Start

...

## Watcher Reports Since Start

...

## Immediately Previous Turn To Review

PM turn | worker report | validation claim | merge claim

## Required Review Lens

Use clean-all-slop read-only adversarial review.

## Extra Goal Integrity Questions

- Did current work drift from the original objective?
- Did any worker or PM claim completion without direct evidence?
- Were skipped checks reported as success?
- Did any instruction, surface boundary, or risk boundary get violated?
- Does the current state require reset to DEFINE, PLAN, BUILD, VERIFY, or REVIEW?
""",
    "maintenance/templates/MIDPOINT_GATE_DECISION.md": """# MIDPOINT_GATE_DECISION

## Adversarial Review Verdict

CLEAN | FIX REQUIRED

## Highest Severity

none | P3 | P2 | P1 | P0

## Contamination Score

C0 | C1 | C2 | C3 | C4

## Decision

continue | correct-plan | redo-from-checkpoint | quarantine-and-restart | stop-for-user

## Required Reset Stage

none | DEFINE | PLAN | BUILD | VERIFY | REVIEW | SHIP_BLOCKED
""",
    "maintenance/templates/PRE_SHIP_AUDIT_CONTEXT.md": """# PRE_SHIP_AUDIT_CONTEXT

## Parent Goal

...

## Claimed Completion

...

## Changed Surfaces

...

## Normalized Worker Packets Used

...

## Watcher Reports Used

...

## Direct PM Checks Run

...

## Checks Not Run

...

## Residual Risks

...

## Immediately Previous Turn To Review

completion claim | merge claim | validation claim

## Required Review Lens

Use clean-all-slop read-only adversarial review.
""",
    "maintenance/templates/PRE_SHIP_GATE_DECISION.md": """# PRE_SHIP_GATE_DECISION

## Adversarial Review Verdict

CLEAN | FIX REQUIRED

## Highest Severity

none | P3 | P2 | P1 | P0

## Contamination Score

C0 | C1 | C2 | C3 | C4

## Completion Eligible

yes | no

## Blockers

...

## Required Correction

...
""",
    "maintenance/templates/PM_MERGE_DECISION.md": """# PM_MERGE_DECISION

## Worker Packet

...

## Watcher Evidence

WATCHER_REPORT | WATCHER_NOT_USED

## Accepted Claims

1. ...

## Rejected Or Unsupported Claims

1. ...

## Direct PM Recheck

...

## Decision

accept-for-integration | request-rework | reject | quarantine | continue

## Reason

...

## Residual Risk

...
""",
}

EVAL_TEMPLATES.update(
    {
        "evals/adversarial-review-integration-smoke.json": {
            "eval_id": "adversarial-review-integration-smoke",
            "task": "Verify clean-all-slop read-only audit mode is the active adversarial review lens inside Goal Integrity Gates.",
            "setup": "Run from CODEX_HOME after worker-watcher managed-source changes.",
            "success_criteria": [
                "clean-all-slop remains available as the read-only adversarial audit lens",
                "CLEAN/P0-P3 verdicts map to C0-C4 contamination scores",
                "CLEAN is not completion authority",
                "watcher and pre-ship templates require the active clean-all-slop lens",
            ],
            "grader": "python maintenance/scripts/codex_agent_harness.py eval --eval-id adversarial-review-integration-smoke",
            "timeout_seconds": 30,
            "risk_notes": "Structural smoke test only; it does not prove live subagent behavior.",
        },
        "evals/worker-watcher-normalized-handoff-smoke.json": {
            "eval_id": "worker-watcher-normalized-handoff-smoke",
            "task": "Verify worker output normalization, watcher coverage, and PM merge evidence artifacts exist.",
            "setup": "Run from CODEX_HOME after worker-watcher managed-source changes.",
            "success_criteria": [
                "Non-trivial worker dispatch requires an independent watcher by default",
                "Worker output must be normalized before PM merge",
                "Watcher omission requires WATCHER_NOT_USED",
                "Observer role and normalization templates exist",
            ],
            "grader": "python maintenance/scripts/codex_agent_harness.py eval --eval-id worker-watcher-normalized-handoff-smoke",
            "timeout_seconds": 30,
            "risk_notes": "Structural smoke test only; hook enforcement is separate.",
        },
        "evals/goal-integrity-gate-smoke.json": {
            "eval_id": "goal-integrity-gate-smoke",
            "task": "Verify midpoint and pre-ship gates map adversarial review results to reset, quarantine, stop, or continue decisions.",
            "setup": "Run from CODEX_HOME after Goal Integrity Gate managed-source changes.",
            "success_criteria": [
                "PM-only long-running work does not bypass midpoint audit",
                "Midpoint gate reviews the immediately previous relevant turn",
                "Pre-ship gate reviews the completion claim",
                "C2 resets BUILD/VERIFY, C3 quarantines, and C4 stops for user approval",
            ],
            "grader": "python maintenance/scripts/codex_agent_harness.py eval --eval-id goal-integrity-gate-smoke",
            "timeout_seconds": 30,
            "risk_notes": "Structural smoke test only; final PM audit remains required.",
        },
    }
)
