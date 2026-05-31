# SpecOps Operating Model

This document redesigns `codex_vibe_spec_ops_pack.zip` for this workstation.
The zip is treated as source material, not as an installable package to copy
wholesale.

## Decision

Do not add the zip's `.agents`, `.codex`, or `.github` trees directly to this
global workstation repository. Instead, preserve the operating pattern as a
capability pack:

- product intent belongs in feature specs;
- architecture decisions belong in contracts and ADRs;
- Codex implementation is verified against those documents;
- the user reviews product fit, architecture risk, acceptance evidence, and
  remaining decisions rather than line-by-line code.

## Where It Applies

Use SpecOps for product repositories and durable project artifacts, especially
when a request is a vague product idea, a non-trivial feature, a data/auth/API
change, or a workflow where human code review would be the bottleneck.

Do not force SpecOps onto tiny edits, obvious build fixes, or workstation
control-plane maintenance where existing runbooks and validators are the better
contract.

## Repository Mapping

For a product repository, scaffold the smallest relevant subset:

- `docs/product/vision.md`
- `docs/features/_template.md`
- `docs/features/<feature>.md`
- `docs/architecture/architecture-contract.md`
- `docs/architecture/adr/_template.md`
- `docs/reports/spec-code-drift/_template.md`

For this workstation repository, use:

- `maintenance\CODEX_SELF_MANAGEMENT_LOOP.md` for Codex operations intent;
- `maintenance\CODEX_STATE_MANAGEMENT.md` for live/runtime state;
- `maintenance\reports\*.md` for evidence packets;
- `maintenance\templates\specops\*.md` as product-repo templates.

## Skill Mapping

The zip's skills are represented as workflow roles until the user explicitly
asks to install new active skills:

- `idea-to-spec-interviewer`: create or update a feature spec before build.
- `architecture-governor`: decide scale tier, boundaries, data ownership, and
  ADR needs before implementation.
- `spec-code-drift-auditor`: compare code to spec/architecture after build.
- `vibe-delivery-orchestrator`: coordinate the full loop and produce a review
  packet for the user.

Active user skills remain governed by `config.toml`. Adding these as installed
skills is a separate change because it expands implicit trigger behavior.

## Human Review Packet

Do not end SpecOps work with "review the code." Report:

- feature spec used or created;
- acceptance criteria pass/fail;
- architecture decisions and ADRs;
- scale risks at 100, 1,000, and 10,000 users;
- checks run and checks not run;
- remaining human product or architecture decisions;
- recommended next Codex task.

## Drift Handling

If implementation and spec disagree:

1. Identify whether the spec is stale or the code is wrong.
2. Report the mismatch explicitly.
3. Propose a spec patch or implementation patch.
4. Do not silently reinterpret the user's intent.

## CI And Automation

The zip's GitHub Action is a template only. Before enabling it in a repository,
verify the current `openai/codex-action` interface from official documentation
or an existing working workflow, then adapt the prompt and permissions to the
target repository.

Scheduled SpecOps audits should start as report-only. They may write drift
reports and update open loops, but should not push, publish, deploy, or broaden
permissions without explicit user intent.

