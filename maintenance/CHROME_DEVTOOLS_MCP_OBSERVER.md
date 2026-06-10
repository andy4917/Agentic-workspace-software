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

- `name`: `chrome-devtools`
- `source_class`: `local-chain`
- `owner`: Codex user-global MCP config; enabled only for confirmed frontend
  work and otherwise kept disabled for app UI visibility
- `exact_path`: `%USERPROFILE%\.codex\toolchains\shims\npx.cmd`
- `config_surface`: `%USERPROFILE%\.codex\config.toml`, registered through
  `codex mcp add/remove` and toggled with the supported `enabled` flag
- `dependency_chain`: official Codex bundled Node selected by
  `.codex\toolchains\shims\npx.cmd` -> local npm package resolution ->
  `chrome-devtools-mcp@latest` -> Chrome stable
- `scope`: visible in Codex-global MCP settings, active only during confirmed
  frontend work
- `default_args`: `-y chrome-devtools-mcp@latest --slim --headless --isolated
  --no-usage-statistics --no-performance-crux`
- `default_env`: `CHROME_DEVTOOLS_MCP_NO_USAGE_STATISTICS=1`,
  `CHROME_DEVTOOLS_MCP_NO_UPDATE_CHECKS=1`, `SystemRoot`, `PROGRAMFILES`
- `rollback`: run the OFF command; any pre-change config copy made by the
  toggle script is a transient `%TEMP%\codex-mcp-config-{guid}.toml` file that
  is deleted after success or rollback handling, not retained runtime fallback
  state

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
3. Reload or restart Codex if `mcp__chrome_devtools__...` tools do not
   appear in the active session.
4. Verify tool exposure with tool discovery.
5. Use the MCP for a small safe rendered observation before relying on it.
6. Perform the actual frontend observation.
7. Run the OFF command.
8. Confirm `status` reports `state=off` and that the server remains registered
   with `enabled = false`.

Observation success must include target identity. A successful DevTools command
against `about:blank`, a diagnostic helper page, an extension URL page, or the
wrong browser context is not proof of the user's intended UI. Record the
observed URL/title/root and keep `ERR_BLOCKED_BY_CLIENT`, missing side-panel targets,
profile/session gaps, or data-auth gaps as blockers instead of downgrading them
to plugin health warnings.

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
  and env; OFF now preserves the server entry with `enabled = false` so app
  settings do not imply the frontend observer is missing.

## UI Visibility Fix

On 2026-05-13, the OFF behavior was changed from removing
`chrome-devtools` to preserving the MCP entry with `enabled = false`.
This keeps the frontend observer visible in Codex app MCP settings while
preventing it from loading as an active tool outside frontend work.

Verification:

- `chrome-devtools-mcp-toggle.ps1 off` registered the server disabled.
- `chrome-devtools-mcp-toggle.ps1 status` reported `state=off` and returned
  `enabled=false`.
- `codex mcp list` showed `chrome-devtools` with `Status disabled`.
- `chrome-devtools-mcp-toggle.ps1 on; status; off; status` successfully toggled
  `enabled=true` and then restored `enabled=false`.

Rollback:

- To remove the settings entry completely, run
  `codex mcp remove chrome-devtools`.
- Pre-change config copies, when created by the toggle script, are transient
  `%TEMP%\codex-mcp-config-{guid}.toml` files and are deleted after success or
  rollback handling.
