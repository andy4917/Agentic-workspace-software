---
name: codex-scaffold-validation
description: Use when validating or changing this workstation's Codex scaffold, CODEX_HOME, managed source mirror, config.d/config.toml reconciliation, hooks, MCP baseline, skills, shims, or runtime cleanup state.
---

# Codex Scaffold Validation

## Baseline

Use the latest user plan and current files as authority. For the PLAN FOR WORK baseline:

- `openaiDeveloperDocs` is the only always-on MCP server.
- `chrome-devtools` is optional and disabled by default unless the active task enables it.
- `memento` and `serena` are retired and must be absent or disabled.
- `node_repl` is a Codex Desktop bundled execution primitive, not a user-authored MCP entry.

## Workflow

1. Inspect managed source under `C:\Users\anise\Documents\Codex` and live state under `C:\Users\anise\.codex` without reading secrets.
2. When changing config, edit the managed `config.d` fragment first, sync it to live `config.d`, and regenerate live `config.toml`.
3. Run direct checks:
   - `codex mcp list --json`
   - `codex doctor --json`
   - `maintenance/scripts/validate-codex-scaffold.ps1 -Json`
   - `maintenance/scripts/codex-p0-integrity-loop.ps1 -Json`
4. Check managed/live sync for public-safe scripts and fragments named by the validator.
5. Check `no_mistakes_gate_ready` in the scaffold validator output. When the
   validator is running inside a no-mistakes gate worktree, the real CLI/daemon
   probe is intentionally skipped to avoid recursive no-mistakes calls; use the
   wrapper/config/fake-binary probe fields as local evidence.
6. Treat stale reports, old session state, and historical docs as evidence candidates only.

Use P0 `-ReportOnly` only for read-only audits or dirty worktree midpoint
checks. Final publication evidence should run the full loop so dead app-server
cleanup and Scoop health are directly checked.

## Exit Evidence

Report the active MCP set, scaffold validation status, `no_mistakes_gate_ready`
status, P0 loop status, managed/live sync status, files changed, checks not run,
and rollback path.
