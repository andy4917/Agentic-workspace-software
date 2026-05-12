# Codex Workflow Configuration Interview [ARCHIVED / NOT ACTIVE CONFIG]

## Purpose

This document defines the user interview needed before turning the current
PM-led multi-agent workflow, skill routing, and lightweight hook behavior into
explicit numeric settings.

It is not active configuration. It is the decision worksheet for settings that
should not be guessed globally.

## Current Baseline

Current operating model:

- Main Codex session acts as PM.
- Subagents are used only when delegation improves the result.
- Skills are task-triggered workflows, not always-loaded context.
- Hooks inject reminders, observe evidence, and block only immediate high-risk actions.
- Completion requires changed behavior plus direct evidence, checks, not-run reasons, and remaining risks.

Current fixed local facts:

- `features.hooks = true`
- `features.multi_agent = true`
- `features.codex_hooks = true` in local `config.toml`
- `features.multi_agent = true` in local `config.toml`
- Hook state is local and ignored under `hooks/state/`.

## Interview Output

After the interview, produce one explicit configuration decision set:

- accepted defaults;
- rejected defaults;
- numeric thresholds;
- hook strictness level;
- validation matrix;
- subagent concurrency and reuse rules;
- Git workflow policy;
- capability pack adoption policy;
- remaining open decisions.

## Decision Levels

Use these levels when answering each section:

- `Default`: use the recommended value unless a task/repo overrides it.
- `Strict`: favor stronger checks and more explicit evidence.
- `Fast`: favor lower overhead and fewer automatic prompts.
- `Manual`: require explicit user instruction before the behavior is used.

## 1. Autonomy And Questions

What this controls:

- when Codex proceeds without asking;
- when Codex pauses for user choice;
- whether the user is treated as reviewer or operator.

Recommended default:

- Codex proceeds for ordinary implementation, inspection, cleanup, formatting, and validation.
- Codex asks only for irreversible, destructive, secret, legal/safety, conflicting, or scope-expanding decisions.

Interview questions:

1. Should Codex ask before creating new files?
   - Recommended: no, if inside the requested scope.
   - Strict: ask for new top-level files only.
   - Manual: always ask.

2. Should Codex ask before editing global `.codex` workflow/config files?
   - Recommended: no for requested workflow/config work.
   - Strict: ask before changing active hooks or config.
   - Manual: always ask.

3. Should Codex ask before using a new tool or MCP?
   - Recommended: no, if the tool directly fits the task.
   - Strict: ask for networked or external-side-effect tools.
   - Manual: always ask.

Decision fields:

```yaml
autonomy:
  create_files_inside_scope:
  edit_codex_workflow_files:
  use_new_tools_or_mcp:
  user_role:
```

## 2. Subagent Concurrency

What this controls:

- maximum parallel subagents;
- when to spawn;
- how deeply subagents may delegate;
- when to wait, reuse, or close.

Recommended default:

- Use subagents for independent exploration, review dimensions, verification, or non-overlapping implementation.
- Keep recursive subagent spawning disabled or one level deep.
- Prefer no subagents for tiny edits or simple answers.

Interview questions:

1. Maximum parallel subagents?
   - Recommended: `3`
   - High throughput: `5`
   - Conservative: `1`

2. Maximum subagent depth?
   - Recommended: `1`
   - Conservative: `0`
   - Experimental: `2`

3. Spawn threshold for code/config work?
   - Recommended: spawn only when touching `3+` surfaces, doing review/security/debug, or when work can proceed in parallel.
   - Strict: spawn for any multi-file behavior change.
   - Fast: spawn only when explicitly useful.

4. Reuse role sessions?
   - Recommended: reuse when objective, surface, risk class, and context remain compatible.
   - Strict: one task per role session.
   - Fast: reuse aggressively within the same project.

5. Close stale sessions after how long without use?
   - Recommended: end of task or when context becomes stale.
   - Numeric option: `30`, `60`, or `120` minutes.

Decision fields:

```yaml
subagents:
  max_parallel:
  max_depth:
  spawn_threshold:
  reuse_policy:
  stale_session_ttl_minutes:
  wait_policy:
```

## 3. Team Presets

What this controls:

- which PM-selected team patterns become default options;
- how file ownership and work tracks are assigned.

Recommended default:

- Keep presets available but not mandatory.
- Use team presets only when they reduce risk or latency.

Preset decisions:

| Preset | Recommended Trigger | User Decision |
|---|---|---|
| review | Risk review, PR review, architecture/security/test dimensions | |
| debug | Repeated failure, unknown root cause, competing hypotheses | |
| feature | Multi-surface feature with separable ownership | |
| full-stack | Frontend/backend/API/data changes together | |
| migration | Restructure, rename, upgrade, replacement | |
| research | External docs, current facts, API/library uncertainty | |
| security | Secrets, auth, permissions, data exposure, destructive ops | |

Interview questions:

1. Which presets should be enabled by default?
2. Which presets require explicit user approval?
3. Should file ownership be mandatory for parallel implementation?
4. Should PM produce a visible status board for all team preset runs?

Decision fields:

```yaml
team_presets:
  enabled:
  require_user_approval:
  file_ownership_required:
  status_board_required:
```

## 4. Work Size Thresholds

What this controls:

- when a task is considered tiny, normal, large, or high ceremony;
- when planning, status boards, or subagents become expected.

Recommended default:

- Do not hard-block on size.
- Use thresholds as reminders and reporting requirements.

Suggested thresholds:

| Category | Recommended Threshold | Behavior |
|---|---:|---|
| tiny edit | `1` file and under `30` changed lines | no plan needed |
| normal edit | `1-3` files or under `150` changed lines | short internal plan |
| large edit | `4+` files or `150+` changed lines | explicit plan/status recommended |
| broad change | `3+` surfaces | consider subagents/work tracks |
| risky change | auth/security/data/deps/schema/hooks | require stronger verification |

Interview questions:

1. What file count makes a change "large"?
2. What changed-line count makes a change "large"?
3. How many surfaces trigger team/work-track planning?
4. Should thresholds warn only, or block finalization until addressed?

Decision fields:

```yaml
work_size:
  tiny_files:
  tiny_changed_lines:
  large_files:
  large_changed_lines:
  multi_surface_threshold:
  threshold_behavior:
```

## 5. File And Module Size

What this controls:

- large-file warnings;
- module split recommendations;
- function/component size warnings.

Recommended default:

- Warn, do not block.
- Require short justification when adding to an already-large file.

Suggested thresholds:

| Item | Recommended Warning | Strict Warning |
|---|---:|---:|
| Markdown/doc file | `800` lines | `500` lines |
| source file | `500` lines | `300` lines |
| function/method | `80` lines | `50` lines |
| React component | `250` lines | `150` lines |
| generated/manifest file | no line threshold; size/hash only | same |

Interview questions:

1. Should file-size checks apply to docs?
2. Should generated files be exempt?
3. Should large-file warnings block final answers or only appear in risk notes?

Decision fields:

```yaml
size_limits:
  docs_file_lines:
  source_file_lines:
  function_lines:
  component_lines:
  generated_files_exempt:
  behavior:
```

## 6. Validation Matrix

What this controls:

- minimum checks by change type;
- how not-run reasons are reported.

Recommended default:

- Use repo-native commands when available.
- Do not invent validation commands.
- If a check cannot run, record why and run the closest direct check.

Suggested matrix:

| Change Type | Minimum Check |
|---|---|
| Markdown/doc only | file readback, link/path sanity where applicable |
| JSON/TOML/YAML config | parser check |
| PowerShell hook/script | sample invocation plus expected allow/deny case |
| JS/TS code | package script typecheck/lint/test/build when present |
| Python code | import/syntax/test/lint when present |
| Rust code | `cargo check/test/fmt` when present |
| dependency metadata | lockfile/sync validation or not-needed reason |
| schema/generated contract | regeneration or parser/static consistency check |
| UI/frontend | browser/runtime verification when practical |
| security/auth/permissions | security review plus explicit risk note |
| Git-only operation | `git status`, relevant log/diff verification |

Interview questions:

1. Which checks are mandatory for config/hook changes?
2. Should docs-only changes require any validation beyond readback?
3. Should UI changes require browser screenshots?
4. Should dependency changes block finalization without lockfile proof?

Decision fields:

```yaml
validation:
  docs:
  config:
  hooks:
  js_ts:
  python:
  rust:
  dependencies:
  schemas:
  ui:
  security:
  git:
```

## 7. Hook Strictness

What this controls:

- whether hooks inject, warn, soft-block, or hard-block.

Recommended default:

- Inject first.
- Warn second.
- Require evidence at finalization.
- Hard-block only actual risk.

Hook levels:

| Level | Meaning |
|---|---|
| observe | record only |
| inject | add context/reminder |
| warn | allow but add warning |
| not_ready | stop finalization until evidence/reason is supplied |
| hard_block | deny tool action |

Recommended policy:

| Condition | Recommended Level |
|---|---|
| session/prompt workflow reminder | inject |
| safe read-only inspection | observe |
| ordinary implementation | observe/warn |
| missing final evidence | not_ready |
| secret content access | hard_block |
| irreversible destructive action | hard_block unless explicitly requested |
| hook/multi-agent weakening | hard_block unless explicitly requested |
| fake-success insertion | hard_block |
| dependency/schema sync missing | not_ready |
| policy/fixture text with risky words | observe |

Interview questions:

1. Should missing final evidence be `warn` or `not_ready`?
2. Should fake-success scans be hard-blocking?
3. Should hook weakening always require explicit approval?
4. Should safe Git add/commit always remain allowed?

Decision fields:

```yaml
hooks:
  missing_final_evidence:
  fake_success:
  hook_weakening:
  safe_git:
  dependency_schema_sync_missing:
  policy_fixture_risky_text:
```

## 8. Contamination And Fake-Success Policy

What this controls:

- hardcoded pass;
- hidden fallback;
- evaluator manipulation;
- warning/error suppression.

Recommended default:

- Block product fake-success insertion.
- Allow policy, audit, and negative fixture text that describes fake-success patterns.

Interview questions:

1. Should fake-success scans include tests and fixtures?
2. Should audit/policy docs be exempt by default?
3. Should `exit 0` be a warning only, or a block in control scripts?
4. Should hidden fallback code be banned globally or only in product code?

Decision fields:

```yaml
contamination:
  scan_product_code:
  scan_tests:
  scan_fixtures:
  audit_policy_exempt:
  exit_zero_policy:
  hidden_fallback_policy:
```

## 9. Skill And Capability Pack Adoption

What this controls:

- whether new skills/agents/prompt recipes become global defaults;
- how external capability packs are distilled.

Recommended default:

- Adopt patterns, not whole marketplaces.
- Add a capability only when it has a clear trigger, bounded scope, and useful output shape.

Quality audit checklist:

- clear trigger;
- clear scope;
- short instructions;
- progressive references;
- no overlap with existing roles unless intentional;
- low token cost;
- useful output shape;
- checkpoint evidence;
- no hidden authority claim;
- no hard blocker behavior;
- no environment assumption that does not apply to Codex.

Interview questions:

1. Which capability packs should be considered global?
2. Which should remain reference-only?
3. Should new skills require a quality audit before use?
4. Should capability packs have owners/status?

Decision fields:

```yaml
capability_packs:
  global_candidates:
  reference_only:
  quality_audit_required:
  owner_status_required:
```

## 10. Documentation And Research Lookup

What this controls:

- when external docs are mandatory;
- when a local scan is required;
- how sources are recorded.

Recommended default:

- Use current documentation for external APIs, libraries, SDKs, cloud services, or version-sensitive behavior.
- Use checkout/full-tree scan for repository distillation claims.
- Do not claim full-tree evidence from representative files.

Interview questions:

1. Should current-doc lookup be mandatory for all external API/library work?
2. Should local checkout be mandatory before adopting patterns from a repository?
3. Should source citations be required in final answers for research tasks?

Decision fields:

```yaml
research:
  external_docs_required:
  checkout_required_for_repo_distillation:
  citations_required:
```

## 11. Git Workflow

What this controls:

- when Codex stages, commits, pushes, and opens PRs.

Recommended default:

- Status/diff/add/commit are safe when requested.
- Push/PR require explicit request.
- Destructive Git operations require explicit request.

Interview questions:

1. Should Codex commit automatically after requested config/doc changes?
2. Should Codex stage all current changes or only its own changes by default?
3. Should push require a separate explicit request?
4. Should PR creation default to draft?

Decision fields:

```yaml
git:
  auto_commit_when_requested:
  stage_scope:
  push_requires_explicit_request:
  pr_default:
  destructive_git_policy:
```

## 12. Status Board And Final Report

What this controls:

- how much progress/status is shown;
- final answer structure.

Recommended default:

- Use lightweight status only for multi-step, multi-agent, or risky work.
- Keep final answer short but include changed files, evidence, not-run checks, and risks.

Interview questions:

1. When should Codex maintain a visible status board?
2. Should every final answer list changed files?
3. Should final answers always include risk/not-run sections?
4. Should long evidence packs be separate docs instead of final prose?

Decision fields:

```yaml
reporting:
  status_board_trigger:
  changed_files_required:
  risks_required:
  not_run_required:
  evidence_pack_policy:
```

## 13. Security And Scope Boundaries

What this controls:

- secret handling;
- scope expansion;
- protected paths.

Recommended default:

- Do not read secret contents unless explicitly requested for that exact file.
- Metadata-only sensitive file detection is allowed.
- Scope expansion outside `.codex` requires explicit user instruction.

Interview questions:

1. Are there additional protected paths besides `.codex` secrets and `Dev-Product`?
2. Should metadata-only inspection of sensitive files always be allowed?
3. Should copying or archiving sensitive files be blocked by default?

Decision fields:

```yaml
security:
  protected_paths:
  metadata_only_allowed:
  copy_archive_sensitive_files:
  scope_expansion_policy:
```

## 14. Recommended Starter Profile

Use this if the user wants a practical default without tuning every field.

```yaml
profile: balanced_pm_workflow

autonomy:
  user_role: reviewer_not_operator
  create_files_inside_scope: allow
  edit_codex_workflow_files: allow_when_requested
  use_new_tools_or_mcp: allow_when_task_matches

subagents:
  max_parallel: 3
  max_depth: 1
  spawn_threshold: multi_surface_or_parallelizable
  reuse_policy: compatible_objective_surface_risk_context
  stale_session_ttl_minutes: 60

work_size:
  tiny_files: 1
  tiny_changed_lines: 30
  large_files: 4
  large_changed_lines: 150
  multi_surface_threshold: 3
  threshold_behavior: warn_and_report

size_limits:
  docs_file_lines: 800
  source_file_lines: 500
  function_lines: 80
  component_lines: 250
  generated_files_exempt: true
  behavior: warn_with_justification

hooks:
  missing_final_evidence: not_ready
  fake_success: hard_block_for_product_or_control_code
  hook_weakening: hard_block_unless_explicit
  safe_git: allow
  dependency_schema_sync_missing: not_ready
  policy_fixture_risky_text: observe

validation:
  docs: readback
  config: parse
  hooks: sample_allow_and_deny
  code: repo_native_smallest_relevant_check
  dependencies: lockfile_or_sync_reason
  schemas: regeneration_or_static_consistency
  ui: browser_when_practical
  security: explicit_risk_review

git:
  auto_commit_when_requested: true
  stage_scope: current_requested_changes
  push_requires_explicit_request: true
  pr_default: draft
  destructive_git_policy: explicit_request_required
```

## 15. Implementation Mapping

After the interview, apply decisions here:

| Decision Area | Target |
|---|---|
| stable operating policy | `AGENTS.md` |
| active feature flags | `%USERPROFILE%\.codex\config.toml` |
| hook lifecycle wiring | `hooks.json` |
| hook thresholds and strictness | `hooks/lightweight-codex-hook.ps1` or a future hook config file |
| ignored runtime state | `.gitignore` |
| capability pack docs | future focused docs or skills |

Recommended next implementation step:

1. Capture user answers in this document.
2. Create a small machine-readable settings file for thresholds if needed.
3. Update hook script to read that settings file.
4. Keep `AGENTS.md` high-level and avoid stuffing numeric details into the global contract.

## 16. Open Decisions Log

Use this table during the interview.

| Area | Decision | Value | Status |
|---|---|---|---|
| Autonomy | create files inside scope | | open |
| Subagents | max parallel | | open |
| Subagents | max depth | | open |
| Work size | large file count | | open |
| Work size | large changed-line count | | open |
| Hooks | missing final evidence behavior | | open |
| Hooks | fake-success behavior | | open |
| Validation | config/hook minimum checks | | open |
| Validation | dependency/schema sync policy | | open |
| Capability packs | global candidates | | open |
| Git | stage scope | | open |
| Git | push/PR policy | | open |
