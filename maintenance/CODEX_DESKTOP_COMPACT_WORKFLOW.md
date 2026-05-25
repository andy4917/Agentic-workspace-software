# Codex Desktop Compact Workflow

This runbook is the detailed operating surface behind the compact root
`AGENTS.md`. It is managed source, not runtime configuration and not completion
authority.

## Source Basis

This file reconciles the current `.codex` state with these user-provided review
documents:

- `C:\Users\anise\Downloads\workstation-workflow-full-review.md`
- `C:\Users\anise\Downloads\codex_desktop_workspace_optimization_proposal.md`

The imported direction is:

- keep `AGENTS.md` compact and move procedural detail here;
- keep hooks lightweight and non-authoritative;
- keep Memento support-only;
- use bounded subagents as evidence producers, not completion authority;
- make `ROAST_REVIEW -> WORKFLOW_SHORTLIST -> GOAL_SPEC -> verified slice` the
  workstation review path;
- keep `clean-all-slop` separate from the roast workflow.

## Authority Map

Use this map before changing workflow, hook, MCP, skill, toolchain, or memory
surfaces:

| Topic | Canonical source | Active/runtime source | Verification |
|---|---|---|---|
| Root operating contract | `AGENTS.md` | loaded scoped instructions | read current file |
| Detailed compact workflow | this file | none | Markdown review plus targeted checks |
| Runtime features and agents | `config.toml` | active Codex session | config parse plus tool exposure |
| Hook event map | `hooks.json` | `config.toml [hooks.state]` | hook smoke or targeted script |
| Hook policy | `hooks/policy.compact.json` | `hooks/compact-codex-hook.ps1` | JSON parse and smoke |
| Structure baseline | `maintenance/CODEX_HOME_STRUCTURE_STATE.json` | filesystem | native-alignment check |
| Project workflow chain | `maintenance/PROJECT_WORKFLOW_CHAIN.md` | project files/tests | project-specific checks |
| Goal integrity | `maintenance/GOAL_INTEGRITY_GATE.md` | current goal state | final goal audit |
| Worker/watcher handoff | `maintenance/WORKER_WATCHER_NORMALIZED_HANDOFF.md` | subagent outputs | PM merge review |
| Memory policy | `maintenance/WORKSTATION_MAINTENANCE.md` | exposed Memento tools | `memento-mcp-runtime.ps1 verify` |

If two surfaces conflict, prefer the canonical source, update references instead
of duplicating policy, and record the not-updated surface as historical,
deferred, or out of scope.

## Current Active Settings Target

The desired active posture for this workstation is:

- `[features].hooks = true`
- `[features].multi_agent = true`
- `[features].goals = true`
- `[features].child_agents_md = true`
- `[features].tool_search = true`
- `[features].tool_suggest = true`
- `[features].skill_mcp_dependency_install = true`
- `[features].workspace_dependencies = true`
- `[features].memories = false` for retired raw-memory behavior
- `[agents].max_threads = 8`
- `[agents].max_depth = 1`
- persistent `model_reasoning_effort = "medium"` unless a live task escalates it
- compact hooks v3 active events: `SessionStart`, `UserPromptSubmit`,
  `PreToolUse`, `PostToolUse`, and `Stop`; `PermissionRequest` stays excluded
- Memento MCP configured as support memory, but active-session tool exposure must
  still be verified before use
- `.tmp\marketplaces` and `.tmp\bundled-marketplaces` are bounded app-generated
  runtime temp, not user-authored source; `.tmp\plugins`, `.tmp\plugins.sha`,
  `vendor_imports`, and incomplete `.tmp\plugins-clone-*` directories remain
  cleanup targets

Do not treat this target as proof. Verify `config.toml`, `hooks.state`,
tool-search exposure, and any relevant script output in the live session.

## Parent Goal Spec

```text
GOAL_SPEC
name: workstation-workflow-compact-control-plane
mission: Keep Codex Desktop active, PM-led, evidence-first, and subagent-capable
  while compressing duplicated workflow policy into a compact root contract plus
  one detailed runbook.
scope:
  included:
    - .codex AGENTS compact contract
    - compact workflow runbook
    - active settings alignment for features, subagents, hooks, and reasoning
    - harness-managed skill index posture and roast/clean-all-slop separation
    - durable goal handoff for compaction/resume
  excluded:
    - secret contents, auth files, browser state, SQLite raw contents
    - broad log cleanup or destructive filesystem cleanup
    - public publishing, Git history rewrite, package installs
    - product repositories outside %USERPROFILE%\.codex unless explicitly named
priority_order:
  - P0 false-success/completion-authority or secret-boundary issues
  - P1 active runtime or state-drift issues
  - P2 workflow, agent, skill, and onboarding drag
  - P3 naming/report clarity
acceptance_criteria:
  - Root AGENTS is compact and points to this runbook.
  - The compact runbook records goal, active settings target, workflow, checks,
    and rollback notes.
  - clean-all-slop remains separate.
  - roast-related active `SKILL.md` packages are retired; workstation roast
    review routes through this integrated runbook instead of adding another
    policy layer.
  - Every changed surface has a parser/static check or precise not-run reason.
  - Subagent evidence is accepted, rejected, or marked residual risk by the PM.
  - `skills/SKILL_INDEX.md` remains harness-managed; use directory inspection for
    full live skill inventory when needed.
stop_condition: Stop after the selected slice passes direct checks and remaining
  findings are triaged as accepted, rejected, deferred, or needs-evidence.
```

## Default Work Loop

1. Define: goal, boundary, surfaces, assumptions, acceptance checks.
2. Plan: smallest verifiable slice, checks, rollback or safe-stop.
3. Build: patch only the selected surface.
4. Verify: run direct parser, smoke, unit, config, or runtime checks.
5. Review: inspect diffs and challenge unsupported claims.
6. Ship: report changed surfaces, checks run, checks not run, residual risks,
   rollback notes, and status.

For bugs or behavior changes, prefer a test-driven or prove-it loop. For
multi-file changes, use incremental implementation. For reviews, lead with
findings and file/line evidence. For external APIs or current tool docs, use
source-backed documentation lookup.

## Workstation Surface Routing

Use `maintenance/WORKSTATION_CONTROL_RUNBOOK.md` for full definitions.

| Surface | Examples | Default risk |
|---|---|---|
| `managed-source` | runbooks, templates, skill docs, prompt recipes | draft or controlled-change |
| `active-runtime` | `config.toml`, hook enabled state, MCP registration | high-risk-change |
| `toolchain` | shims, CLI wrappers, runtime selectors | high-risk-change |
| `security-boundary` | auth, secrets, credentials, sandbox, publishing | high-risk-change |
| `runtime-state` | logs, SQLite, caches, browser state, memory DB | observe or high-risk-change |
| `project-repository` | product code outside `.codex` | project-specific |

High-risk changes are allowed only when current user intent covers that boundary.
When allowed, keep the edit narrow and include rollback notes.

## Subagent Pattern

Use bounded sidecars when they reduce PM uncertainty and do not block the next
local step.

Minimum charter:

```text
Role:
Goal:
Purpose:
PM Context:
Owned Surface:
Out Of Scope:
Expected Evidence:
Anti-Reward-Hacking Rules:
Exit Criteria:
Not Checked:
```

Subagents must not claim parent-goal completion. The PM must independently
verify material claims. For non-trivial worker output, normalize the packet and
use a watcher or record `WATCHER_NOT_USED`.

## Roast Integration

For workstation and workflow work, the roast path is integrated here:

1. `ROAST_REVIEW`: evidence-backed findings only.
2. `FINDING_MAP`: P0-P3, affected surface, confidence, verification path.
3. `WORKFLOW_SHORTLIST`: skill, subagent, automation, runbook, extend existing,
   or skip.
4. `GOAL_SPEC`: bounded parent goal and selected slice.
5. `SLICE_REPORT`: changes, checks, not-run reasons, rollback, residual risk.

The former `technical-system-roast-review` and
`roast-feedback-to-goal-hardening` skill packages are retired from the active
skill root. Their workstation/control-plane procedure is represented by this
runbook and the `workstation-workflow-full-review` source, not by separate
active `SKILL.md` entries or a new policy layer.

## Clean-All-Slop Separation

`clean-all-slop` remains separate and should be invoked for adversarial audit or
cleanup of:

- unsupported success or final prose overclaiming;
- hidden fallback, broad catch, stale output, or fake verification;
- hardcoded values, legacy residue, duplicate code, needless abstractions;
- ignored instructions, bypass behavior, reward hacking, or stale state.

Use audit mode unless the user asked to fix or cleanup. If a failure is found,
preserve a failure capsule instead of smoothing it into reassurance.

## Skill Pack Compression Status

The uploaded optimization proposal's seven focused skill packs are the target
architecture for a public/product repository skill rail. In live `CODEX_HOME`,
do not bulk-retire operational skills until each installed skill has an owner,
replacement route, rollback path, and direct verification. Installed skills are
capability, not evidence of use.

Current implemented compression:

- `clean-all-slop` stays separate by explicit user instruction.
- Roast review no longer has active `SKILL.md` packages under
  `%USERPROFILE%\.codex\skills`; it routes through this runbook and the uploaded
  `workstation-workflow-full-review` source.
- The active top-level `%USERPROFILE%\.codex\skills` root is capped at seven
  operational skill directories:
  `agent-harness-construction`, `clean-all-slop`, `dont-even-try`,
  `git-easy-korean`, `iterative-retrieval`, `result-normalizer`, and
  `verification-loop`.
- Broader optional packs are preserved as archived source under
  `maintenance/archive/skills/compact-skill-retirement-20260525/` and are no
  longer active top-level skill entries.
- `skills/SKILL_INDEX.md` remains the harness-managed compact routing subset;
  use directory inspection for the full active skill root.

## Verification Menu

Use the narrowest relevant checks:

| Changed surface | Check |
|---|---|
| Markdown/runbook | read back relevant lines, `git diff --check` |
| JSON | `ConvertFrom-Json` parse |
| TOML | Python `tomllib` parse or Codex config command if available |
| Hook script | PowerShell parse and targeted hook smoke |
| Skill index | compare directories to listed names |
| Toolchain/source ambiguity | `maintenance/scripts/check-toolchain-sources.ps1` |
| Naming | `maintenance/scripts/check-naming-conventions.ps1 -Json` |
| Native alignment | `maintenance/scripts/check-codex-native-alignment.ps1 -Json -WriteReport` |
| Memento | `maintenance/scripts/memento-mcp-runtime.ps1 verify` |

If a broad check is too expensive or out of scope, run the closest direct check
and state the limitation.

## Final Handoff Shape

Keep final handoff concise but evidence-based:

```text
Outcome:
Changed surfaces:
Checks run:
Checks not run:
Accepted subagent evidence:
Rejected/suspect evidence:
Residual risks:
Rollback:
Status:
SUBAGENT_CALL used|not_used:
SKILL_EVIDENCE used:
```

## Rollback Notes

- `AGENTS.md`: restore from Git or the prior version in repository history.
- New runbook/goal files: remove only if the compact workflow track is abandoned.
- `config.toml`: restore the previous value from Git diff or backup before
  restarting Codex.
- Skill docs/index: revert the changed files; do not delete skill directories
  unless the user explicitly asks for skill removal.
