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
- `shadcn`: global, stdio via
  `%USERPROFILE%\.codex\toolchains\shims\npx.cmd -y shadcn@latest mcp`. Use for
  frontend work that needs shadcn/ui registry browsing, searching, component
  docs, or install planning. It is configured from the official Codex MCP
  instructions, but active-session usability still requires tool injection and a
  safe read-only MCP call after the app/session reloads. If MCP tools are not
  injected, use the shadcn CLI fallback through the same `npx.cmd` wrapper.
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
- `chrome_devtools_observe`: frontend-only stdio MCP, intentionally OFF by
  default. It remains registered in config with `enabled = false` so Codex app
  settings show the capability without loading the tool outside frontend
  observation work. It is toggled with
  `maintenance\scripts\chrome-devtools-mcp-toggle.ps1`, not by hand-editing
  `config.toml`. Use only after a task is confirmed to require rendered browser
  observation. Default command is the local-chain wrapper
  `%USERPROFILE%\.codex\toolchains\shims\npx.cmd -y
  chrome-devtools-mcp@latest --slim --headless --isolated
  --no-usage-statistics --no-performance-crux`, with usage statistics and update
  checks disabled by environment variables. Turn it OFF after the frontend task
  and verify `state=off` with the server still registered as disabled.
- `memento`: global, streamable HTTP at `http://127.0.0.1:57332/mcp`, bearer
  token sourced from `MEMENTO_ACCESS_KEY`. Use for PM memory support only:
  `context` at session start, `get_skill_guide` when behavior is unclear,
  `recall` before hook/MCP/toolchain/prior-state work, `remember` only through
  the PM durable-write gate, `reflect` for final durable handoff, and
  `tool_feedback` after recall. It is not completion authority and must not
  override current user instructions, scoped `AGENTS.md`, files, tests, runtime
  output, or direct PM verification. Active source is
  `%USERPROFILE%\.codex\tools\memento-mcp`; active state is
  `%USERPROFILE%\.codex\state\memento-mcp`; PostgreSQL listens on local port
  `55432`; Memento HTTP listens on local port `57332`. Manage and verify with
  `maintenance\scripts\memento-mcp-runtime.ps1`.

## Frontend Browser Observation Toggle

Chrome DevTools MCP is not part of the always-on global MCP set. Its scope is
Codex-global only while a frontend task needs real rendered observation.

Activation sequence:

1. Confirm the task touches visible frontend UI or browser behavior.
2. Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.codex\maintenance\scripts\chrome-devtools-mcp-toggle.ps1 on
```

3. Reload or restart the Codex app/session before expecting new
   `mcp__chrome_devtools_observe__...` tools to appear.
4. Verify active tool exposure with tool discovery, then perform a small browser
   observation such as navigation plus screenshot or equivalent safe read.
5. After the frontend verification pass, run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.codex\maintenance\scripts\chrome-devtools-mcp-toggle.ps1 off
```

6. Confirm:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.codex\maintenance\scripts\chrome-devtools-mcp-toggle.ps1 status
```

Expected final state is `state=off`.

Use `-Visible` only when the task specifically requires a visible isolated Chrome
window. Use `-Full` only when the slim tool surface is insufficient, for example
when performance, network, accessibility snapshot, or deeper DevTools categories
are required. Do not connect this MCP to a user's normal Chrome profile or
logged-in sensitive pages unless the user explicitly asks for that risk boundary.

## Memento PM Memory Runtime

Memento MCP was installed as a clean Windows-native local-chain runtime. It does
not use WSL, Docker, the old temp clone, old memory DB paths, or legacy
`memsearch` as fallback.

- `source_class`: `local-chain`.
- `active_source`: `%USERPROFILE%\.codex\tools\memento-mcp`.
- `state_root`: `%USERPROFILE%\.codex\state\memento-mcp`.
- `postgres_data`: `%USERPROFILE%\.codex\state\memento-mcp\pgdata`.
- `postgres_port`: `55432`.
- `memento_url`: `http://127.0.0.1:57332/mcp`.
- `codex_mcp_name`: `memento`.
- `credential_source`: user environment variable `MEMENTO_ACCESS_KEY` and the
  ignored local `.env`; do not print either value.
- `dependency_chain`: Codex official bundled Node -> local Memento checkout ->
  Scoop PostgreSQL 18 -> pgvector `0.8.2` -> dedicated `memento_pm` database.
- `managed_memory_policy`: the Codex-managed runtime starts Memento with
  `MEMENTO_INPROCESS_ONNX_ENABLED=false` and
  `MEMENTO_MANAGED_EMBEDDING_PROVIDER=none` unless explicitly overridden. This
  keeps Reranker, NLI, and local transformers embedding models from loading into
  the long-lived MCP process while preserving the required PM memory tools for
  support-only context, topic/keyword recall, durable writes, and feedback. The
  runtime verifier reports `memento_working_set_mb` and fails above the managed
  default `MEMENTO_MAX_WORKING_SET_MB=512`.
- `verification`: run
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.codex\maintenance\scripts\memento-mcp-runtime.ps1 verify`.
- `restart`: run the same script with `restart` to recycle the Memento HTTP
  process without stopping PostgreSQL. Use `stop` only when intentionally
  taking down both Memento HTTP and the dedicated PostgreSQL runtime.
- `session_reload_note`: current Codex sessions may not expose new
  `mcp__memento__...` tools until the app/session reloads. Until then, direct
  HTTP JSON-RPC probes are acceptable runtime evidence and must be reported as
  fallback verification, not as a hidden tool substitution.
- `rollback`: run the runtime script with `stop`; restore the saved config backup
  from `%USERPROFILE%\.codex\state\memento-mcp\config-backups` or remove the
  `memento` MCP entry only after an explicit user request. Preserve state unless
  destructive cleanup is explicitly requested.

Legacy Memory/RAG surfaces are contamination boundaries:

- `toolchains\shims\memsearch.*` is retired and must not be used as active
  fallback.
- `maintenance\scripts\check-memory-rag-status.ps1` is retired and points to the
  Memento runtime verifier.
- `memories\raw_memories.md` is historical data only unless the user explicitly
  asks for a reviewed import or migration into Memento.

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
