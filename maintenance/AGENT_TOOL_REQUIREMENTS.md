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

`rg` has an extra Windows rule: prefer bare `rg` only when `Get-Command rg -All`
shows a Codex-owned `rg.exe` first, or call the bundled `rg.exe`/`rg.ps1` shim
explicitly. Do not call `rg.cmd` from PowerShell for search patterns or paths
that may contain cmd metacharacters such as `|`, `&`, `<`, or `>`; use
`toolchains\shims\rg.ps1` or the bundled `rg.exe` instead. `rg.cmd` remains a
cmd.exe compatibility shim for simple arguments and escaped cmd metacharacters.

Quick check:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.codex\maintenance\scripts\check-toolchain-sources.ps1
```

## Temporary Windows Sandbox Restriction

Until a Codex update or a confirmed local runtime fix resolves the Windows
read-only sandbox runner error `CreateProcessAsUserW failed: 5`, do not use
`codex exec --sandbox read-only` as a required verification path on this
workstation. It fails before the requested command starts, so it is not evidence
for or against the tool being tested.

For Codex-internal command smoke tests, use the active session shell or an
ephemeral `codex exec --sandbox danger-full-access --disable plugins` command
with an explicit no-mutation prompt, then record that read-only sandbox
verification was not run because of the runner error.

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

## Project Workflow Chain

Before changing a project repository or durable project artifact, classify the
project workflow chain using `maintenance/PROJECT_WORKFLOW_CHAIN.md`. This is a
global rule, not a frontend-only rule.

If the chain is missing or mismatched for the requested work, scaffold the
smallest durable project-local chain before implementation unless the user
explicitly requested read-only analysis or forbids project edits. A tool being
installed, an MCP being registered, or a skill being available is not enough;
the project must have usable instructions, commands, contracts, and verification
paths for the work being performed.

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
- Use LLVM/MSYS2 UCRT64 shims `clang`, `clang++`, `gcc`, `g++`, `lld`,
  `lld-link`, `llvm-config`, `pkg-config`, `make`, `mingw32-make`, and `gdb`
  for GNU/Clang UCRT builds. These wrappers prepend `C:\msys64\ucrt64\bin` for
  required runtime DLLs.
- Use `clang-cl` when an MSVC ABI Clang compile is required; it loads
  `vcvars64.bat` before invoking the LLVM Windows `clang-cl.exe`.

### Debugger Tools

Debugger availability must be reported separately from debugging procedure.
Presence of a shim is not enough to claim a debugger is usable or was used.

- Use `gdb` through `.codex\toolchains\shims\gdb.cmd` for GNU/UCRT C, C++,
  and Rust GNU ABI work. Verification command: `gdb.cmd --version`.
- Use `cdb`, `dumpchk`, and `symchk` through `.codex\toolchains\shims` for
  Windows crash dump, symbol, and MSVC-native investigations. Verification
  command: `cdb.cmd -version`.
- Python has the built-in `pdb` debugger through the managed Python shim.
  `debugpy` is not a managed installed debugger unless a project environment
  explicitly provides it; verify with `python.cmd -c "import importlib.util; ..."`
  before claiming IDE/attach debugging support.
- `rust-gdb` and `rust-lldb` wrappers are conditional Rustup entry points. On
  the active `stable-x86_64-pc-windows-msvc` toolchain they currently report
  `not applicable`; do not present them as active debuggers for MSVC Rust work.
  Use `cdb`/Windows debugging tools for MSVC-native evidence, or deliberately
  install/select a Rust GNU or LLDB-capable toolchain before claiming those
  wrappers are usable.
- Final reports for toolchain-sensitive work must say one of:
  `debugger used: <tool> <command evidence>`, `debugger available but not used:
  <reason>`, or `debugger unavailable/conditional: <tool> <reason>`.

## MCP Use Policy

MCP servers are only usable in a session after they are enabled in config and the
app has restarted or otherwise reloaded tool definitions. If a server is enabled
but no `mcp__...` tools appear in the active tool list, record that as a runtime
load issue, not as proof the tool is unnecessary.

Global MCP server definitions belong in `%USERPROFILE%\.codex\config.toml` when
the user intent is cross-workspace use. Use project-local MCP config only for a
repository-specific command, credential source, or policy boundary.

- Actively choose an MCP when the task matches its evidence surface; do not wait
  for the user to name it. If a namespace is not already exposed, use
  `tool_search` first, then call the MCP directly when exposed.
- Use OpenAI Developer Docs MCP for current OpenAI API, model, Codex, plugin,
  app-server, and ChatGPT Apps documentation. Prefer it over web search for
  OpenAI product facts.
- Use Context7 when `CONTEXT7_API_KEY` is available and current third-party
  library, framework, SDK, CLI, or cloud-service documentation is needed.
  Prefer it over web search for library documentation; resolve the library id
  before fetching focused docs.
- Use shadcn MCP for frontend work that depends on shadcn/ui registry,
  component, block, or `components.json` knowledge. The global config exposes
  `shadcn` through `%USERPROFILE%\.codex\toolchains\shims\npx.cmd -y
  shadcn@latest mcp` and should stay enabled for future frontend sessions. Do
  not treat config as capability: after app/session reload, make a safe
  read-only MCP call before claiming `MCP_CONFIRMED`. If tools are not injected,
  use shadcn CLI fallback through the same wrapper, including `docs`, `view`,
  `search --help`, and dry-run add commands as appropriate for the project.
- Use Sequential Thinking for high-ambiguity debugging or planning, not for
  routine edits.
- Use Windows PowerShell MCP when a persistent PowerShell console is useful for
  Windows diagnostics or command execution. Its `invoke_expression` tool is
  broad, so keep approval prompting and do not describe this server as read-only.
- Use `node_repl` as a Codex Desktop bundled tool, not as a user-configured
  `[mcp_servers.*]` entry. Discover it with `tool_search` when needed, then call
  `mcp__node_repl__js` for JavaScript execution or browser-plugin setup code.
- Use Chrome DevTools MCP only as a frontend browser-observation role. Keep it
  registered but OFF by default, and toggle it with
  `maintenance\scripts\chrome-devtools-mcp-toggle.ps1`; do not hand-edit
  `config.toml` to enable or disable it. After turning it ON, reload/restart the
  app if the tool namespace is not visible, verify exposure with tool discovery,
  use it for the rendered observation, then turn it OFF and confirm `state=off`.
  Default mode is slim, headless, isolated, telemetry-off, performance CrUX off,
  and npm-backed through `.codex\toolchains\shims\npx.cmd`. OFF must leave the
  server visible in app settings as `enabled = false`.

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
