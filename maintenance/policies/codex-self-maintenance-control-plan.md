# Codex Self-Maintenance Control Plane

## 0. Mission

Build and operate a Codex-managed maintenance loop for the developer environment, Codex app workflow, local agent-control-plane, MCP/toolchain state, workspace skills, and imported orchestration repositories.

The agent owns investigation, planning, implementation, validation, session organization, thread/worktree hygiene, and evidence capture. The human reviewer should primarily review diffs, evidence, residual risks, and final acceptance reports.

Do not rely on ambiguous human intervention during execution. When a task is allowed, execute it end-to-end inside the defined risk boundary. When a task crosses a gated boundary, stop at a dry-run, plan, or explicit approval request.

## 1. Authority Order

Use this authority order for every maintenance task:

1. Current user instruction.
2. Current live command output, direct file contents, git diff, runtime state, tests, and logs.
3. Repository-local instructions, skills, hooks, runbooks, manifests, and configuration.
4. Official release notes, changelogs, upstream documentation, and upstream issue/PR evidence.
5. Prior summaries, memory, old reports, and historical manifests.

Historical markdown is evidence, not completion authority. A previous "pass" is not proof that the current state still passes.

## 2. Non-Negotiable Root-Cause Gate

Before any modification, produce a root-cause gate record:

- Observed symptom:
- Source trace:
- Strongest supported root cause:
- Exact change location:
- Fix goal:
- Minimal change scope:
- Original failure mode to verify:
- Uncertainty:
- Stop condition:

Do not apply broad rewrites, speculative fixes, deletion-first cleanups, or symptom-level workarounds before this record exists.

A valid fix must satisfy:

- The target is connected to the verified cause.
- The goal is explicit and testable.
- The scope is minimal and justified.
- Verification checks the original failure mode.
- Remaining uncertainty is stated explicitly.

## 3. Maintenance Surfaces

Classify every task across these surfaces:

- developer-environment
- toolchain
- agent-control-plane
- Codex-app-workflow
- runtime-state
- MCP-state
- project-codebase
- imported-orchestration-repos
- security-boundary
- product-ops

Classify every possible change as:

- observe
- draft
- controlled-change
- high-risk-change

Default to observe or draft when evidence is incomplete.

## 4. High-Risk Gates

Do not mutate these surfaces unless the current user instruction explicitly opens the boundary:

- shell profile
- PATH
- version manager
- wrapper/shim/global install route
- active MCP server registration
- hook enablement
- trust settings
- automation schedule
- raw secrets
- credential rotation
- token scopes
- deploy/publish permissions
- destructive filesystem actions
- migration
- browser/native host state outside the requested target
- Codex desktop UI automation itself, unless a safe supported interface is explicitly available

For high-risk work:

- prefer readback first
- prefer dry-run before mutation
- keep scope narrow
- record rollback or safe-stop instructions
- require post-change diff and live validation evidence

## 5. External Patch Intake Chain

When any external patch, package update, app update, CLI update, repository import, MCP update, or release log arrives, run this chain:

1. Detect the change source.
   - Identify vendor/project, version, date, channel, affected package/app/repo, and installation route.

2. Acquire release evidence.
   - Read official release notes or changelog first.
   - Read upstream commits, issues, PRs, migration notes, and security advisories when relevant.
   - Record exact source links or local file paths.

3. Classify the delta.
   - bugfix
   - new feature
   - breaking change
   - security fix
   - behavior change
   - diagnostic improvement
   - documentation-only
   - unknown or under-specified

4. Map impact.
   - app workflow
   - CLI behavior
   - threads/search/session inventory
   - worktree semantics
   - MCP lifecycle
   - process cleanup
   - toolchain provenance
   - validation scripts
   - skills/automations
   - imported orchestration repos
   - user-facing workflow

5. Decide the action.
   - no-op with ledger entry
   - documentation update
   - validation update
   - skill update
   - automation update
   - controlled source change
   - runtime repair
   - rollback/quarantine
   - human review only

6. Produce an application design.
   - Explain how the new feature or bugfix changes the maintenance model.
   - Specify which threads, worktrees, manifests, scripts, skills, or checks need updates.
   - Specify acceptance criteria before any implementation.

7. Execute only the smallest bounded slice.
   - Prefer managed source changes before active runtime changes.
   - Prefer worktree isolation for repo changes.
   - Prefer dry-run for runtime/toolchain changes.

8. Validate.
   - Validate the exact original failure mode.
   - Validate the intended new behavior.
   - Validate no unrelated drift.
   - Capture diff and command evidence.

9. Close the loop.
   - Update release ledger.
   - Update session/thread index.
   - Update manifest.
   - Pin active control threads, and close or remove stale thread surfaces only
     when current retention rules authorize cleanup.
   - Record residual risks and next slice.
   - Present final diff/evidence for human review.

## 6. Thread and Worktree Topology

Maintain one pinned control thread per workspace:

- `MAINTENANCE_CONTROL::<workspace-name>`

This thread owns:

- release intake summary
- active maintenance queue
- pinned P0/P1 incidents
- thread index
- worktree index
- validation manifest index
- current residual risks
- next review trigger

Before creating a new thread, search existing threads by:

- release version
- package/app name
- branch name
- affected file path
- incident ID
- failure signature
- MCP/server name
- validation command
- imported repo name

Continue an existing thread when the root cause and affected surface match. Create a new thread when the work is independent, risky, parallelizable, or needs a separate worktree.

Use explicit thread classes:

- `release-intake/<source>/<version>`
- `impact-design/<surface>/<date>`
- `p0-incident/<failure-signature>`
- `runtime-repair/<component>`
- `toolchain-provenance/<component>`
- `mcp-lifecycle/<server-name>`
- `skill-hardening/<skill-name>`
- `sandcastle-orchestration/<task>`
- `verification/<date>/<scope>`
- `postmortem/<incident-id>`

Pin only:

- the control thread
- active P0/P1 incident threads
- active release-intake threads
- active verification threads blocking closure

Archive threads when:

- the diff is merged or intentionally abandoned
- validation evidence is recorded
- residual risk is assigned to a new thread or backlog item
- no open decision remains

## 7. Thread Header Contract

Every maintenance thread must start with this header:

- Parent control thread:
- Workspace:
- Source event:
- Release/update version:
- Surfaces:
- Risk level:
- Allowed write surface:
- Excluded surface:
- Branch/worktree:
- Related files/folders:
- Related skills:
- Related MCP/toolchain components:
- Root-cause gate required: yes/no
- Acceptance criteria:
- Verification commands:
- Stop condition:
- Rollback/safe-stop:
- Human review artifact:

Do not start implementation until this header is complete.

## 8. Folder and Manifest Model

Maintain a repository-local maintenance area. Use the actual repository’s naming conventions, but preserve these logical records:

```text
.maintenance/
  control/
    maintenance-control.md
    active-queue.md
    residual-risks.md

  releases/
    <date>-<source>-<version>.md

  incidents/
    p0/
    p1/

  reviews/
    workstation-workflow-review/
    postmortems/

  manifests/
    runtime-status.json
    toolchain-provenance.json
    thread-index.json
    worktree-index.json
    validation-ledger.json

  designs/
    impact-designs/
    hardening-designs/

  verification/
    <date>-<scope>.md
