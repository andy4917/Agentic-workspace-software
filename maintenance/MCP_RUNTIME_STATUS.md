# MCP Runtime Status

Updated for the 2026-05-13 maintenance handoff.

## Current Finding

MCP tool loading is working in the current Codex Desktop session after tool
discovery. The earlier failure was not a broken package install. The confirmed
causes were path/filter fragility and already-running session tool schemas that
had not refreshed.

`node_repl` is a separate Codex Desktop bundled execution tool, not a user
`[mcp_servers.*]` entry in `config.toml`. It is surfaced through tool discovery
as the `mcp__node_repl__` namespace and runs from the Codex app bundle
(`%LOCALAPPDATA%\OpenAI\Codex\bin\node_repl.exe` plus the bundled Node runtime).

## Global MCP Scope

The configured MCP servers live in `%USERPROFILE%\.codex\config.toml`, so their
intended scope is user-global across trusted Codex workspaces. Do not duplicate
these servers in project-local config unless a repository needs a genuinely
different command, credential source, or policy boundary.

## Current MCP Intent

- `openaiDeveloperDocs`: global, streamable HTTP. Use for current OpenAI API,
  model, Codex, plugin, and app-server documentation. Search first, then fetch
  the exact doc page before quoting or relying on details.
- `context7`: global, stdio via `npx -y @upstash/context7-mcp`, with
  `CONTEXT7_API_KEY`. The configured command is the local-chain wrapper
  `%USERPROFILE%\.codex\toolchains\shims\npx.cmd`, which prepends the official
  Codex bundled Node runtime before invoking the local npm package command. Use
  for current third-party library, framework, SDK, CLI, and cloud-service
  documentation. Resolve the library id before querying.
- `sequential_thinking`: global, stdio via
  `%USERPROFILE%\.codex\toolchains\shims\npx.cmd -y
  @modelcontextprotocol/server-sequential-thinking`. Use only for ambiguous
  multi-step planning/debugging where revision or branching adds value.
- `windows_powershell`: global, stdio via the installed
  `PowerShell.MCP.Proxy.exe`. Use for persistent PowerShell diagnostics and
  Windows command execution when its stateful console is useful. It exposes
  `start_console`, `get_current_location`, `invoke_expression`, and
  `wait_for_completion`; because `invoke_expression` is broad, keep approval
  prompting and avoid treating it as a narrow read-only server.
- `node_repl`: bundled Codex tool, discovered rather than configured. Use when a
  skill or prompt says `node_repl`, for JavaScript execution, browser-plugin
  setup code, package import checks, and app-bundled Node runtime diagnostics.

## Toolchain Source Rule

Codex-bundled command-line tools are `node`, `node_repl`, `rg`, and `codex`.
Use those from the official bundle. Local duplicates are removed when broken, or
left installed but marked unused by Codex wrappers when another local package
chain still depends on them.

`features.workspace_dependencies = true` is intentional. Workspace dependency
runtime paths come from the Codex app bundle and should not be treated as local
toolchain contamination.

Use local-chain tools for non-bundled capabilities such as npm packages, Python,
Rust, JVM, Git, PowerShell modules, and stdio MCP packages. Local-chain commands
must use explicit wrappers or absolute paths so PATH order cannot silently pick a
different runtime.

Run this check after shim or MCP command changes:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.codex\maintenance\scripts\check-toolchain-sources.ps1
```

## Required Agent Behavior

When a task matches one of the purposes above:

1. Use `tool_search` if a configured MCP namespace is not already visible in the
   active tool list.
2. If the namespace is exposed, call the MCP tool directly and cite the tool
   result as evidence.
3. If config says enabled but the namespace remains absent, record a runtime-load
   issue, inspect `codex mcp list/get`, and use the best available fallback.
4. For `enabled_tools`, verify the allow-list against the server's actual
   `tools/list` names before concluding the install is broken.

## Delete/Reinstall Guidance

Do not delete and reinstall first for the known symptom "configured MCP is
enabled but absent from a session." Prefer this order:

1. Verify global config with `codex mcp list` and `codex mcp get <name>`.
2. Replace fragile `~` or `%VAR%` command/cwd values with absolute paths.
3. Align `enabled_tools` with actual server tool names.
4. Reload the app/session or use Codex app-server MCP reload when available.
5. Reinstall only when the command binary/package is missing, corrupted, or
   fails a direct `initialize`/`tools/list` probe after the config is known good.
