# Codex Native Alignment Report

Date: 2026-05-19

Superseded note: this report is a historical record of the 2026-05-19 state.
As of 2026-05-20, `check-codex-native-alignment.ps1` validates only enabled
configured official bundled plugin paths. The disabled, unconfigured official
Store manifest `latex` entry is no longer treated as local `.codex` drift or a
current warning.

## Scope

Checked whether the recent removal of local fallback and patched official copies
left intended workspace functionality missing. Added a normal-structure
contract and a recurring native alignment automation for `%USERPROFILE%\.codex`.

## Accepted Evidence

- `OpenAI.Codex` Store app is installed and healthy at
  `C:\Program Files\WindowsApps\OpenAI.Codex_26.513.4821.0_x64__2p2nqsd0c76g0`.
- Microsoft Store `winget upgrade --source msstore` reported no matching Codex
  upgrade candidate.
- `features.workspace_dependencies = true` is present in `config.toml`.
- Workspace runtime plugins `documents`, `presentations`, and `spreadsheets`
  exist under `%USERPROFILE%\.cache\codex-runtimes\codex-primary-runtime` and
  share runtime version `26.518.11428`.
- Removed local fallback/patched paths are absent:
  `plugins\patched`, `vendor_imports`, `plugins\plugins`,
  `plugins\cache\openai-bundled\browser-use`,
  `plugins\cache\openai-primary-runtime`, `.tmp\bundled-marketplaces`,
  `.tmp\plugins`, and `plugins\local-marketplaces`.
- `codex.cmd` now resolves the current Store app resource first; `codex
  --version` matches the official app resource at `codex-cli 0.131.0-alpha.9`.
- `.codex-global-state.json.bak` reappeared during runtime and was moved to the
  Windows Recycle Bin after path validation under `.codex`.
- Automation `codex-native-alignment-check` was created with schedule
  `FREQ=DAILY;INTERVAL=2;BYHOUR=9;BYMINUTE=0;BYSECOND=0`.

## Historical Residual Warning

At the time of this report, the official `openai-bundled` marketplace manifest advertised plugin `latex`,
but the installed Store app package does not contain
`app\resources\plugins\openai-bundled\plugins\latex`. This plugin is not enabled
in `config.toml`, so current configured workspace functionality is not missing.
Do not recreate a local patched official copy for this. The current checker now
keeps disabled/unconfigured manifest-only entries out of local warning status.

## Changed Surfaces

- `maintenance\CODEX_HOME_STRUCTURE_CONTRACT.md`
- `maintenance\scripts\check-codex-native-alignment.ps1`
- `toolchains\shims\codex.cmd`
- `AGENTS.md`
- `maintenance\WORKSTATION_MAINTENANCE.md`
- `maintenance\AGENT_TOOL_REQUIREMENTS.md`
- `maintenance\NAMING_CONVENTION.md`
- `automations\codex-native-alignment-check\automation.toml`

## Verification

- `check-codex-native-alignment.ps1 -Json -WriteReport -CheckStoreUpgrade`:
  `status=warn`, `failures=0`, `warnings=1` for the official disabled `latex`
  manifest path. This was the 2026-05-19 result and is superseded by the
  2026-05-20 enabled-only path check.
- `check-toolchain-sources.ps1`: `status=pass`.
- `codex_agent_harness.py doctor --tier core --json`: `status=pass`.
- `codex_agent_harness.py benchmark`: refreshed benchmark digest for current
  harness state.
- `codex_agent_harness.py verify`: all checks pass.
- `codex_agent_harness.py audit`: score `100.0`, status `pass`.
- `memento-mcp-runtime.ps1 verify`: `status=pass`.
- `git diff --check`: exit `0`; only Git CRLF/LF conversion warnings were
  printed.
