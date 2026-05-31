---
name: repo-audit
description: Use when auditing a repository or worktree for structure, ownership boundaries, stale artifacts, generated-output drift, hidden fallback, verification readiness, or cleanup risk before broad remediation.
---

# Repo Audit

## Workflow

1. Read the nearest `AGENTS.md` or project instructions before judging the tree.
2. Inventory only the surfaces needed for the audit: `git status --short`, `rg --files`, package/build manifests, test entry points, generated outputs, ignored runtime state, and project docs.
3. Classify suspicious files before acting: active source, generated output, source template, runtime output, historical evidence, quarantine candidate, or contamination candidate.
4. Lead with findings. Tie each issue to a path, command result, or missing proof; do not turn a cleanup preference into a bug without evidence.
5. If asked to fix, make the smallest behavior-preserving cleanup and rerun the same proof that exposed the issue.

## Review Checks

- Instruction chain and repo ownership are clear.
- Build/test/verification commands are discoverable or missing with a precise reason.
- Untracked and ignored state are classified, not blindly deleted.
- Duplicate code, dead code, hardcoding, fallback behavior, and stale docs are supported by direct file evidence.
- Secrets and credentials are not opened unless the user explicitly targets them.

## Exit Evidence

Report findings by severity with file references, commands run, commands not run, accepted assumptions, rejected assumptions, and residual risk.
