Sandcastle Integration Policy

Use Sandcastle https://github.com/mattpocock/sandcastle.git for isolated multi-agent orchestration when a task is parallelizable, AFK-capable, or benefits from sandboxed branch execution.

Use it for:

release impact exploration
independent repo review tasks
parallel vulnerability/finding scans
documentation and skill hardening drafts
isolated prototype fixes
review pipelines

Do not use it as a blind mutation layer for active runtime state, PATH, global shims, secrets, or live MCP registration unless the boundary is explicitly authorized.

Default strategy:

use isolated providers for speculative or parallel work
use worktree/branch isolation for repo changes
use no-sandbox only when already inside a trusted isolated environment or when host execution is explicitly intended
require deterministic branch names
require completion-signal handling
require captured commits, diff, logs, and session output before merge
10. Change Accumulation Review Trigger

Run the workstation workflow review skill when any trigger fires:

any P0 or P1 occurs
a validation script gives a false pass
runtime/toolchain provenance changes
Codex app, Codex CLI, MCP, or orchestration repo receives a meaningful update
five or more maintenance commits accumulate
three or more warnings recur
two or more manual interventions repeat
any high-risk surface is touched
session/thread/worktree inventory drifts from manifests
release notes introduce new automation, thread, worktree, permissions, or diagnostic capability
a stale manifest or stale summary conflicts with live evidence

The review output must include:

evidence ledger
surface map
finding map
workflow shortlist
goal spec
slice report
checks run
checks not run
rollback notes
residual risks
next slice
11. Diff-Based Closure Contract

No maintenance task is complete until the loop closes through diff and verification.

Closure requires:

Clean working tree explanation.
If dirty, explain every changed file.
If clean, state that no source mutation occurred.
Diff review.
Show changed files.
Explain why each change maps to the root cause.
Identify unrelated drift, if any.
Validation ladder.
Formatting/static checks.
Unit/integration checks where applicable.
Environment/toolchain checks where applicable.
Codex doctor or equivalent diagnostics where applicable.
MCP smoke checks where applicable.
Original failure regression check.
Manifest refresh.
Refresh only after checks pass.
Do not preserve stale pass/fail status.
Record generation time and source commands.
Review artifact.
Produce a final report that a human can review without manually reconstructing the chain.
12. P0 Integrity Regression Invariants

For Codex runtime/toolchain maintenance, always protect these invariants:

Active Codex command route must be unambiguous.
Stale duplicate installs must not be reachable through the active route.
First-command provenance for codex/node/rg or equivalent core tools must be checked.
Runtime root classification must not match arbitrary command lines.
Process cleanup must handle descendants even if a root process has already exited.
Cleanup must not use variable names that collide with shell-reserved process identifiers.
Watcher cleanup must verify watched app-server liveness before orphan cleanup.
Cleanup for a dead app-server PID must not kill the new app-server’s active managed MCP roots.
Scaffold validation must fail on managed MCP orphan roots.
Generated live manifests must not preserve false historical status after repair.
Dead-app-server regression must be tested after cleanup logic changes.
13. Human Review Role

The human reviewer should review:

final diff
evidence ledger
root-cause gate
validation output
residual risk
rollback/safe-stop notes
next-slice proposal

The human should not be required to manually repair ambiguous intermediate state. If manual intervention is needed, the agent must convert it into a bounded, reviewable, explicit decision.