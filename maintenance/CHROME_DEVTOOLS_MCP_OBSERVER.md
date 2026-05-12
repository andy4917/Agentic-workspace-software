# Chrome DevTools MCP Observer

This is the managed record for the frontend-only Chrome DevTools MCP observer.

## Purpose

Use Chrome DevTools MCP as a real browser observation role for frontend work:
rendered screenshots, browser state inspection, page interaction, and deeper
DevTools checks when needed.

This MCP is intentionally not part of the always-on global server set. It can
increase active tool noise, runtime load, and accidental browser exposure if it
is left enabled during non-frontend work.

## Managed Capability

- `name`: `chrome_devtools_observe`
- `source_class`: `local-chain`
- `owner`: Codex user-global MCP config while ON; absent from config while OFF
- `exact_path`: `%USERPROFILE%\.codex\toolchains\shims\npx.cmd`
- `config_surface`: `%USERPROFILE%\.codex\config.toml`, managed only through
  `codex mcp add/remove`
- `dependency_chain`: official Codex bundled Node selected by
  `.codex\toolchains\shims\npx.cmd` -> local npm package resolution ->
  `chrome-devtools-mcp@latest` -> Chrome stable
- `scope`: Codex-global only during confirmed frontend work
- `default_args`: `-y chrome-devtools-mcp@latest --slim --headless --isolated
  --no-usage-statistics --no-performance-crux`
- `default_env`: `CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS=1`,
  `CHROME_DEVTOOLS_MCP_NO_UPDATE_CHECKS=1`, `SystemRoot`, `PROGRAMFILES`
- `rollback`: run the OFF command; pre-change config backups are written under
  ignored local state at `%USERPROFILE%\.codex\state\mcp-toggle-backups`

## Commands

Status:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.codex\maintenance\scripts\chrome-devtools-mcp-toggle.ps1 status
```

Turn ON for confirmed frontend work:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.codex\maintenance\scripts\chrome-devtools-mcp-toggle.ps1 on
```

Turn OFF after the frontend observation pass:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.codex\maintenance\scripts\chrome-devtools-mcp-toggle.ps1 off
```

Probe the npm package and supported flags:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.codex\maintenance\scripts\chrome-devtools-mcp-toggle.ps1 verify-package
```

## Required Workflow

1. Confirm the task is frontend UI, browser behavior, layout, or visual
   verification work.
2. Run the ON command.
3. Reload or restart Codex if `mcp__chrome_devtools_observe__...` tools do not
   appear in the active session.
4. Verify tool exposure with tool discovery.
5. Use the MCP for a small safe rendered observation before relying on it.
6. Perform the actual frontend observation.
7. Run the OFF command.
8. Confirm `status` reports `state=off`.

## Options

Use `-Visible` only when the task requires a visible isolated Chrome window.
Default headless mode is preferred for low-noise observation.

Use `-Full` only when the slim tool surface cannot answer the verification
question. Examples include performance, network, accessibility snapshot, or
other non-slim DevTools categories.

Do not connect this MCP to the user's normal Chrome profile or logged-in
sensitive pages unless the user explicitly asks for that risk boundary.

## Evidence From Setup

- Official package documentation lists Codex setup via `codex mcp add`.
- Official package documentation lists `--slim`, `--headless`,
  `--isolated`, `--no-usage-statistics`, and `--no-performance-crux`.
- Official package documentation states usage statistics are enabled by default
  and can be disabled by flag or `CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS`.
- Local probe on 2026-05-13:
  `chrome-devtools-mcp@latest --help` succeeded through the `.codex` npx
  wrapper and listed the required flags.
- Local toggle loop on 2026-05-13: ON added the server with the desired command
  and env, OFF removed it, and final `status` reported `state=off`.
