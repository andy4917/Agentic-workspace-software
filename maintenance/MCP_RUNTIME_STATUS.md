# MCP Runtime Status

Updated for the 2026-06-11 PowerShell-native shim and context7 uninstall
baseline.

## Current Finding

The workstation MCP baseline is intentionally small:

- `openaiDeveloperDocs`: enabled, required false, prompt approval.
- `chrome-devtools`: optional and configured OFF by default.

`context7` must be absent from live config. `memento` and `serena` must be
absent or disabled in live config, and none of these runtimes should be started
or verified as part of normal scaffold health. `node_repl` remains useful, but
as a Codex Desktop bundled execution primitive, not as a user-authored
`[mcp_servers.*]` entry.

## Global MCP Scope

The active runtime truth is `%USERPROFILE%\.codex\config.toml`, generated from
reviewable fragments under `config.d`. Update the managed-source fragment first,
copy it to `%USERPROFILE%\.codex\config.d`, then regenerate `config.toml`.
Project-local MCP config is reserved for a repository-specific command,
credential source, or policy boundary.

## Current MCP Intent

- `openaiDeveloperDocs`: use for current OpenAI API, model, Codex, plugin,
  app-server, and ChatGPT Apps documentation. Prefer it over web search for
  OpenAI product facts.
- `chrome-devtools`: use only as a temporary browser-observation role. It stays
  disabled by default, runs through the `.codex\toolchains\shims\npx.cmd`
  wrapper when enabled, exposes the full Chrome DevTools MCP tool surface by
  default, and should be disabled again after the bounded check.
- `node_repl`: use as a discovered bundled execution tool for JavaScript,
  JSON/package checks, and browser-plugin setup code. Do not configure it as a
  user MCP server.

## Retired MCPs

- `context7`: uninstalled from the global MCP baseline. Use official project
  documentation, an installed task-specific documentation MCP, or web search for
  current third-party library, framework, SDK, CLI, and cloud-service facts.
- `memento`: retired as active PM memory. Do not use memory reads/writes as
  workflow support unless a future current user instruction reopens that
  boundary. Historical reports and patches are maintenance evidence, not active
  runtime authority.
- `serena`: retired as active symbolic editing/search. Use file reads, `rg`,
  tests, and scoped edits unless a future current user instruction reopens that
  boundary.

Retirement is a policy and validation baseline change, not a claim that old
historical documents never mention these tools. Historical reports may retain
their original evidence, but active instructions, validators, harness checks,
and config fragments must not require retired MCP health.

## Validation

Use these checks after MCP baseline changes:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.codex\maintenance\scripts\validate-codex-scaffold.ps1 -Json
powershell.exe -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.codex\toolchains\shims\codex.ps1 mcp list --json
powershell.exe -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.codex\toolchains\shims\codex.ps1 doctor --json
```

Expected scaffold validation:

- `mcp_plan_baseline: pass`
- `openaiDeveloperDocs` configured and enabled
- `context7` absent
- `memento` and `serena` absent or disabled
- `chrome-devtools` absent or disabled by default
- `node_repl` absent from user-authored MCP config

## Runtime Load Note

Already-running Codex sessions can retain tool namespaces or child MCP processes
from the old config until the app/session reloads or the processes are cleaned
up. Treat that as runtime state to report and retire, not as proof the old
baseline is still desired.
