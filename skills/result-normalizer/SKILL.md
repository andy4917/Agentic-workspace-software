---
name: result-normalizer
description: Normalize worker outputs and watcher reports into compact evidence-first packets before PM merge.
version: 0.1.0
tags: [subagents, handoff, verification]
---

# Result Normalizer

Convert worker output into `NORMALIZED_WORKER_PACKET` before the PM decides whether it is a merge candidate.

## Preserve

- Claims tied to concrete evidence.
- Claims Rejected Or Unsupported.
- Changed surfaces and ownership boundaries.
- Commands run, command results, and validation artifacts.
- Commands not run, not-run reasons, and risk impact.
- Watcher findings and unresolved defects.
- Unsupported claims that require PM recheck.

## Remove Or Downgrade

- Reassurance without evidence.
- Unsupported confidence or completion language.
- Raw reasoning that does not help PM verification.
- Duplicate logs and stale output.
- Hidden fallback, skipped checks, and inaccessible files presented as success.

## Output Rule

If required evidence is missing, mark status as `partial`, `blocked`, or `suspect`. Do not upgrade a worker claim, watcher report, clean verdict, or passing check into completion authority.
