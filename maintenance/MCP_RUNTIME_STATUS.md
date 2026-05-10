# MCP Runtime Status

Generated for the current maintenance pass.

## Why MCP Was Not Used

- MCP tools are exposed to an agent session only after the Codex app loads enabled
  MCP server definitions.
- The active config previously had MCP servers present but `enabled = false`, so
  no `mcp__...` tools were expected to appear.
- The active session also started before the latest config changes, so newly
  enabled MCP servers are not guaranteed to appear until the app/session reloads.
- Plugins and MCP are separate surfaces: disabling plugins does not make MCP tools
  available, and enabling plugins does not replace MCP server startup.

## Current MCP Intent

- `openaiDeveloperDocs`: enabled. Use for OpenAI API/model/plugin docs.
- `context7`: enabled because `CONTEXT7_API_KEY` is present. Use for current
  library/framework documentation.
- `sequential_thinking`: enabled. Use only for high-ambiguity planning/debugging.
- `windows_powershell`: enabled with read-only `Show-TextFiles` only.

## Required Agent Behavior

When a task matches one of the MCP purposes above:

1. Check whether the corresponding `mcp__...` tools are actually exposed in the
   active tool list.
2. If exposed, use them before web or ad hoc shell fallbacks.
3. If not exposed, record that the current session did not load the MCP server,
   use the best available fallback, and recommend/rely on app reload for the next
   session.

## Current Limitation

This file and `config.toml` can prepare MCP startup, but they cannot inject new
MCP tools into an already-running agent session.
