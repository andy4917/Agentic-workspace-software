# RG Shim Resolution - 2026-05-13

## Goal

Diagnose persistent `rg` shim failures, separate shell/PATH/session causes from
wrapper argument-forwarding defects, apply a durable workstation fix, and prove
the result with direct checks.

## Root Cause

The direct failing path was not a missing `rg.exe`, cwd issue, stale Scoop shim,
or permission problem. `rg.cmd` used batch `%*` forwarding:

```cmd
"%CODEX_TOOL%" %*
```

When PowerShell invoked `rg.cmd` with unescaped cmd metacharacters such as `|`,
cmd.exe reparsed the argument boundary and treated part of the search pattern as
a command. `rg.cmd --version` passed, so the previous smoke check missed the
real failing class.

## Design Fix

- Keep Codex bundled `rg.exe` as the source of truth.
- Keep the managed shim root out of persistent User/Machine PATH.
- Add `toolchains/shims/rg.ps1` as the PowerShell-safe shim.
- Keep `toolchains/shims/rg.cmd` as a cmd.exe compatibility shim for simple
  arguments and escaped cmd metacharacters.
- Add `maintenance/scripts/check-rg-resolution.ps1` and wire it into
  `check-toolchain-sources.ps1`, harness `verify`, and
  `evals/rg-resolution-smoke.json`.
- Update `maintenance/AGENT_TOOL_REQUIREMENTS.md` and `toolchains/README.md`
  with the `rg.ps1` vs `rg.cmd` rule.
- Register `agents/observer.toml` in `config.toml`.
- Replace deprecated `[features].codex_hooks = true` with
  `[features].hooks = true`.

## Evidence

Passing direct checks:

- `maintenance/scripts/check-rg-resolution.ps1`: pass, failures 0, warnings 0.
- `maintenance/scripts/check-toolchain-sources.ps1`: pass, failures 0,
  warnings 0.
- `codex_agent_harness.py doctor --json`: pass.
- `codex_agent_harness.py self-test`: pass.
- `codex_agent_harness.py benchmark --eval-id rg-resolution-smoke`: pass.
- `codex_agent_harness.py verify`: pass, including `rg_resolution_smoke`.
- `codex_agent_harness.py eval`: pass for latest eval batch.
- `codex exec --sandbox danger-full-access`: ran `rg --version` and returned
  `ripgrep 15.1.0 (rev af60c2de9d)`.

Important negative evidence:

- `rg.cmd` direct from PowerShell with unescaped `|` remains unsupported by
  design; the check records this explicitly and requires `rg.ps1`, bare `rg`,
  or bundled `rg.exe` for PowerShell metacharacter patterns.
- `codex exec --sandbox read-only` failed before `rg` with
  `CreateProcessAsUserW failed: 5`, which is a Windows sandbox runner issue,
  not an `rg` resolver issue.

## Residual Risks

- A fully restarted Codex Desktop session was not performed in this pass.
- `codex exec` read-only sandbox still needs separate Windows sandbox
  diagnostics if that mode must execute shell commands. Until a Codex update or
  confirmed local runtime fix resolves `CreateProcessAsUserW failed: 5`, do not
  use read-only sandbox exec as required verification on this workstation.
- Generated hook/plugin warnings observed during `codex exec` are separate
  runtime hygiene items and were not broadened into this fix.

## Rollback

- Restore `toolchains/shims/rg.cmd` to its previous content if the compatibility
  change regresses cmd.exe callers.
- Remove `toolchains/shims/rg.ps1`, `maintenance/scripts/check-rg-resolution.ps1`,
  and `evals/rg-resolution-smoke.json` if reverting the rg healthcheck feature.
- Revert `config.toml` agent registry and `[features].hooks` changes only if a
  runtime regression is confirmed.
