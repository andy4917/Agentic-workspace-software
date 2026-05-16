# PowerShell Compile Candidate Triage - 2026-05-17

## Status

Applied as parser-compilation coverage, not native executable compilation.
PowerShell scripts remain source scripts. The safe compile step is
`System.Management.Automation.Language.Parser.ParseFile` through
`maintenance/scripts/codex_agent_harness.py repo-verify`.

## Candidate Classes

1. High risk: `maintenance/scripts/memento-mcp-runtime.ps1`.
   Reason: recent non-elevated bridge work, process launch logic, runtime health
   parsing, and user-token/elevation branching.

2. High risk: `hooks/*.ps1` and `hooks/lib/*.ps1`.
   Reason: workflow routing, Stop-hook reminders, task-level escalation, and
   final evidence prompts are sensitive to syntax drift.

3. High risk: `maintenance/scripts/check-rg-resolution.ps1` and
   `maintenance/scripts/check-toolchain-sources.ps1`.
   Reason: PowerShell command quoting and rg shim routing have already produced
   a live mismatch in this turn.

4. Medium risk: `maintenance/scripts/chrome-devtools-mcp-toggle.ps1`,
   `maintenance/scripts/codex-home-maintenance.ps1`, and the sensitive-diff
   scanners.
   Reason: these touch MCP/toolchain state or pre-commit safety checks.

5. Medium risk: `profile.d/*.ps1`, `toolchains/shims/rg.ps1`,
   `tools/*.ps1`, and `skills/*/scripts/*.ps1`.
   Reason: these are active local wrapper or skill entry points but were outside
   the previous repo-verify PowerShell parser scope.

6. Low risk: tiny `maintenance/scripts/codex-*.ps1` wrappers.
   Reason: simple wrappers, but parse coverage is cheap and prevents broken
   command entry points.

## Applied Change

`repo-verify` now parser-compiles PowerShell scripts from:

- `maintenance/scripts`
- `hooks`
- `profile.d`
- `toolchains/shims`
- direct `tools/*.ps1` and `tools/*.psm1` files
- `skills`

The check excludes:

- `tools/memento-mcp`
- `node_modules`
- `plugins/cache`
- `.tmp`

This keeps the current workspace repository separate from the forked memento
repository and avoids parsing package-manager generated shims.

## Verification Expectations

- `py_compile` must pass for the harness change.
- `repo-verify` must report `powershell_parser: pass`.
- Worktree and staged sensitive scans must pass before commit.
- No original `JinHo-von-Choi/memento-mcp` remote operation is part of this
  change.

## Rollback

Revert `maintenance/scripts/codex_agent_harness_workflows.py`, revert the
success criteria text in `maintenance/scripts/codex_agent_harness_base.py`, and
remove this report. No external runtime state rollback is required.
