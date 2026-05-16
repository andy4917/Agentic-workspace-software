---
name: roast-feedback-to-goal-hardening
description: Convert a harsh technical review, system roast, architecture audit, DX/AX review, security review, or lead-engineer takeover report into a bounded Codex Goal, prioritized remediation plan, evidence requirements, and narrow hardening workflow. Use when the user wants roast findings turned into a Goal, backlog, remediation slice, fix plan, or verified improvement work.
---

# Roast Feedback To Goal Hardening

## Core Rule

Do not blindly implement every finding. Convert the review into a verified remediation goal first.

Separate facts, hypotheses, preferences, and unsupported claims. A harsh finding becomes actionable only after it is mapped to a concrete surface, acceptance criteria, validation method, and rollback or non-goal boundary.

## Goal Behavior

If a persisted Goal mechanism is exposed and the work is long-running, create or update exactly one parent Goal for the remediation effort. If no Goal tool is appropriate or available, emit a `GOAL_SPEC` block.

The parent Goal must not say "fix everything." It must name a bounded remediation mission, success criteria, excluded work, evidence requirements, and stop condition.

## Finding Normalization

Extract findings into these buckets:

- `P0`: security exposure, secret leakage, destructive-action risk, false-success mechanism, data loss, broken completion authority.
- `P1`: reliability blocker, reproducibility break, state drift, brittle runtime coupling, missing rollback, CI/test gap.
- `P2`: developer or agent productivity drag, onboarding friction, documentation drift, command ergonomics, local-only assumptions.
- `P3`: polish, naming, report clarity, convenience improvements.

For each finding, record:

- summary;
- evidence cited by the review;
- affected surface;
- confidence: `confirmed`, `likely`, or `unverified`;
- remediation type: `delete`, `isolate`, `simplify`, `document`, `test`, `automate`, or `defer`;
- verification path;
- rollback or safe-stop path.

Reject or downgrade claims that lack direct evidence. The review is evidence, not authority.

## Surface Classification

Classify every proposed improvement before mutation:

- `managed-source`: docs, policies, templates, skill files, runbooks.
- `active-runtime`: live config, hooks, app/session settings, MCP registration, PATH/profile behavior.
- `toolchain`: wrappers, shims, runtime versions, package manager routes.
- `security-boundary`: credentials, secret handling, sandboxing, external publishing permissions.
- `runtime-state`: logs, SQLite, caches, browser state, memory DB, generated state.
- `project-codebase`: product code, tests, dependencies, CI.
- `product-ops`: onboarding, support, delivery, ownership, process.

Risk levels:

- `observe`: read-only verification or evidence gathering.
- `draft`: inactive plan/template/doc proposal.
- `controlled-change`: bounded source edit with direct validation.
- `high-risk-change`: active runtime config, secrets, deletion, tool install/update, external publish, forceful git, sandbox weakening.

High-risk changes require explicit user intent for that exact boundary.

## Remediation Workflow

1. Stabilize findings.
   - Build a `FINDING_MAP`.
   - Separate accepted, rejected, deferred, and unverified claims.
2. Create or update the parent Goal.
   - Use a bounded mission, included/excluded scope, priority order, acceptance criteria, evidence requirements, and stop condition.
3. Choose the first slice.
   - Start with false-success/completion-authority risks, secret/security defects, state drift, runtime ambiguity, smallest useful checks, or misuse-preventing docs.
4. Plan narrowly.
   - Define objective, affected surfaces, risk level, likely files/configs, acceptance checks, rollback/safe-stop, not-run risks, and out-of-scope work.
5. Execute narrowly.
   - Make only the bounded changes needed for the selected slice.
   - Preserve existing behavior unless the finding proves it is harmful.
6. Verify.
   - Run direct parser, compile, unit, smoke, fixture, secret scan, config parse, toolchain source, or health checks as appropriate.
   - Record checks not run with concrete reasons.
7. Finalize.
   - Report Goal status, finding decisions, changed surfaces, checks run, checks not run, residual risks, next slice, rollback notes, and status.

Avoid:

- rewriting the whole control plane;
- adding another policy layer to fix policy overload;
- turning every recommendation into an active hook;
- hiding runtime failures behind documentation;
- marking an unverified review claim as fixed.

## Output

Use `references/goal-remediation-template.md` when a structured remediation report is useful.

When no persisted Goal is used, include:

```text
GOAL_SPEC
name: harden-<system-or-repo-name>-from-technical-roast
mission: Convert the review findings into bounded, verified improvements without broad rewrites or hidden runtime risk.
scope:
  included:
  excluded:
priority_order:
  - P0 security/false-success/completion-authority issues
  - P1 reliability/reproducibility/state-drift issues
  - P2 DX/AX/onboarding/productivity issues
  - P3 polish/documentation clarity
acceptance_criteria:
  - Each accepted finding is confirmed, fixed, deferred with reason, or rejected with evidence.
  - Each changed surface has direct verification or a precise not-run reason.
  - High-risk runtime/security changes are isolated and explicitly authorized.
  - Rollback or safe-stop notes exist for every controlled or high-risk change.
  - Final report includes checks run, checks not run, residual risks, and next verification step.
stop_condition: Stop when the selected remediation slice passes direct checks and remaining findings are triaged into a durable backlog.
```

## Exit Criteria

The workflow is complete when:

- one parent remediation Goal is created/updated or a complete `GOAL_SPEC` is emitted;
- findings are triaged by priority and confidence;
- the first remediation slice is planned or executed;
- verification and not-run reasons are explicit;
- residual risks and next slice are recorded;
- `SKILL_EVIDENCE used` marker is present.
