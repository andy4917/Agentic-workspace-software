# Verification Contract

## Required Direct Checks

| Check | Required? | Evidence | Not-Run Reason |
|---|---:|---|---|
| Inspect changed surfaces | yes |  | n/a |
| Inspect worktree status or equivalent changed-state summary | yes |  | n/a |
| Run relevant parser, lint, test, build, or harness checks | yes |  |  |
| Review subagent evidence against current filesystem/runtime state | when delegated |  |  |

## Evidence Standard

- Commands must include command name, target path or scope, result, and artifact path when useful.
- Not-run checks must include a specific reason and the nearest practical substitute.
- Subagent reports are evidence candidates until PM rechecks critical claims.
- Stale or contradicted evidence must be marked explicitly.

## Completion Requirement

Do not mark the parent goal complete until `FINAL_GOAL_AUDIT.md` records checked items, not-run reasons, residual risks, and PM independent verification.
