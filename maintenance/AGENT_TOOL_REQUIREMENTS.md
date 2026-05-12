# Agent Tool Requirements

This file describes tools the agent should use even when the user does not name
them explicitly. It is operational guidance for `%USERPROFILE%\.codex`.

## Default Resolution

Use `%USERPROFILE%\.codex\toolchains\shims` by explicit path, or use a
process-local PATH only for a bounded task. Do not add this directory to
persistent User or Machine PATH.

Source selection rule:

1. If Codex Desktop officially bundles the tool, use the official bundle through
   the `.codex` wrapper or the bundle path. Current bundled command-line tools
   are `node`, `node_repl`, `rg`, and `codex`.
   App workspace dependencies are also official Codex-provided runtime assets;
   keep `features.workspace_dependencies = true` unless a task explicitly needs
   a project-local replacement.
2. If Codex does not bundle the capability, use the local toolchain or local MCP
   server with an explicit wrapper or absolute command path.
3. Do not call bare commands when both a bundled tool and a local install exist.
4. Broken package-manager shims must be quarantined or marked unused; they must
   not remain the first resolved command.

Quick check:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.codex\maintenance\scripts\check-toolchain-sources.ps1
```

## Workstation Managed Changes

When a user asks to install, configure, enable, disable, upgrade, remove, or
repair a workstation-level capability, follow
`maintenance/WORKSTATION_MAINTENANCE.md`.

Do not leave a new tool as an implicit side effect. Record the source class,
exact active path, owning config, dependency chain, scope, verification command,
rollback or quarantine route, and handoff update.

If the tool is unrelated to the active task, mark it out of scope. If it is
related, tie it to the exact dependency chain that will use it, for example:

- MCP stdio package -> `.codex\toolchains\shims\npx.cmd` -> bundled Node.
- Python maintenance script -> `.codex\toolchains\shims\python.cmd` or official
  workspace runtime Python.
- Browser/plugin runtime -> patched marketplace path plus original official
  bundle source.

## Core Stacks

### Python

- Use `uv` for project environment creation, lock/sync, and fast package tasks
  when a project has `pyproject.toml` or `uv.lock`.
- Use `python`, `pip`, and `pipx` through the `.codex` shims for global checks.
- Use `ruff`, `pytest`, `mypy`, `black`, `poetry`, `pdm`, `pre-commit`, `tox`,
  `nox`, and `semgrep` when the repo config or task calls for them.

### JavaScript / TypeScript

- Use the repo's lockfile/package manager first.
- Use `node`, `npm`, `npx`, `pnpm`, `bun`, and `deno` through `.codex` shims.
- Use `tsc`, `tsx`, `eslint`, `prettier`, `biome`, `pyright`, `yarn`, and `zx`
  when repo scripts or task validation call for them.

### Rust

- Use `cargo`, `rustc`, `rustfmt`, `cargo-clippy`, `cargo-nextest`, `cargo-insta`,
  `just`, and `rust-analyzer` through `.codex` shims.
- Prefer `cargo test` or `cargo nextest run` according to the repo's existing
  pattern.

### C / C++

- Use `cmake` and `zig` through `.codex` shims when present.
- Use MSVC shims `cl`, `nmake`, `link`, `lib`, `dumpbin`, and `rc`; each shim
  loads `vcvars64.bat` before invoking the tool.
- Use `msvc-x64-shell` when an interactive MSVC developer shell is needed.

## MCP Use Policy

MCP servers are only usable in a session after they are enabled in config and the
app has restarted or otherwise reloaded tool definitions. If a server is enabled
but no `mcp__...` tools appear in the active tool list, record that as a runtime
load issue, not as proof the tool is unnecessary.

Global MCP server definitions belong in `%USERPROFILE%\.codex\config.toml` when
the user intent is cross-workspace use. Use project-local MCP config only for a
repository-specific command, credential source, or policy boundary.

- Use OpenAI Developer Docs MCP for current OpenAI API, model, Codex, plugin,
  app-server, and ChatGPT Apps documentation.
- Use Context7 only when `CONTEXT7_API_KEY` is available and current third-party
  library, framework, SDK, CLI, or cloud-service documentation is needed.
- Use Sequential Thinking for high-ambiguity debugging or planning, not for
  routine edits.
- Use Windows PowerShell MCP when a persistent PowerShell console is useful for
  Windows diagnostics or command execution. Its `invoke_expression` tool is
  broad, so keep approval prompting and do not describe this server as read-only.
- Use `node_repl` as a Codex Desktop bundled tool, not as a user-configured
  `[mcp_servers.*]` entry. Discover it with `tool_search` when needed, then call
  `mcp__node_repl__js` for JavaScript execution or browser-plugin setup code.

## Reasoning Effort Policy

Do not hard-code `xhigh` as the default. Keep the persistent config at a
placeholder default (`medium`) and escalate per task/session only when complexity,
ambiguity, or validation risk justifies it.

## Runtime Contamination Guard

The plugin feature may stay enabled, but active source paths must not point at
`.tmp`, `tmp`, `vendor_imports`, `bundled-marketplaces`, `plugins\cache`, or
`plugins\plugins`.

Do not use sentinel files to block `.tmp`, `tmp`, or `plugins\cache`. Codex uses
`.tmp/marketplaces` for marketplace registration/loading and `plugins\cache` for
installed plugin runtime material. Guard these paths by checking that they are
not active config sources and that their contents stay bounded. Sentinel
blockers are allowed only for confirmed non-runtime roots such as
`vendor_imports` and `plugins\plugins`.
