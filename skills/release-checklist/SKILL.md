---
name: release-checklist
description: Use before merging, releasing, deploying, handing off, or declaring a change stable; checks diff scope, tests, build, docs, config, security, rollback, and unresolved risk.
---

# Release Checklist

## Workflow

1. Confirm the intended release scope and compare it with `git status --short` and the relevant diff.
2. Verify instructions, acceptance criteria, and user-requested constraints are satisfied.
3. Run the smallest credible test/build/lint/typecheck/config parse/runtime checks for the changed surfaces.
4. Review security, secrets, permissions, destructive actions, migrations, dependencies, docs, and rollback notes.
5. Use `code-review-and-quality` for code changes and `clean-all-slop` when AI-generated slop, false pass, hidden fallback, or stale state is plausible.

## Blockers

Do not mark ready when direct verification is missing for a high-risk path, a test failure is unexplained, a required doc/config sync is stale, or success depends on unsupported claims.

## Exit Evidence

Report release scope, changed files, checks passed, checks not run with reasons, known risks, rollback notes, and final ready/blocked/continue status.
