# Codex Runtime Root Cause Remediation

Date: 2026-05-29

## Summary

The failures were not one bug. They were a control-plane drift cluster:

- runtime state drift: stale plugin cache links, stale MCP roots, stale watcher assumptions;
- validation false pass: checks accepted configuration names without proving the effective runtime;
- path/source hardcoding: bundle hash paths, bare PATH routing, volatile marketplace sources;
- lifecycle ownership gap: app-server, MCP roots, and Chrome native host had separate lifetimes;
- policy inventory drift: active skill directories and validation policy disagreed.

The remediation moved the system from cleanup-after-failure toward dynamic resolution, explicit health checks, and owner-exit cleanup.

## Root Causes And Fixes

| Defect | Type | Root cause | Fix |
|---|---|---|---|
| Chrome plugin install failed with access denied | State failure / lifecycle failure | `extension-host.exe` held a mutable plugin-cache path while install tried to back up cache state. The native host manifest depended on `chrome\latest`, which was missing or stale. | Added `repair-chrome-plugin-runtime.ps1` to verify and repair `latest`, native host manifest, host binary, and `extension-host-config.json`. Repair refuses mutable path changes when a broken state and live host process overlap. |
| `codex plugin list` could look successful while Chrome native host was broken | Validation failure / false success | The success check looked at plugin registration and manifest name/origin, but not whether the manifest path target and host config existed. | Validator now includes `chrome_plugin_runtime_valid` and checks `latest`, native host executable, config paths, and manifest path alignment. |
| Multiple MCP processes and stale roots recurred | Lifecycle failure | Watcher accepted any old process matching script name and parent PID, then aggressive cleanup treated short startup overlap as stale. | Watcher now compares script path, `CodexHome`, owner-exit flag, poll, grace, and confirmation settings. Duplicate cleanup requires grace plus repeated confirmations. |
| App close could leave processes behind | Ownership boundary failure | The watcher watched app-server PID but not the owner process or Chrome native host tree. | Watcher now supports owner-exit cleanup and includes Chrome native host cleanup when app-server/owner exits. |
| PID cleanup could kill the wrong process | Safety failure | Stop logic used stale PID snapshots and did not revalidate identity or ancestry before `Stop-Process`. | `Stop-ProcessTree` re-reads each process before stopping and checks creation time, root identity, and current ancestry. |
| Validator reported failures with exit code 0 | Validation failure / false pass | The script printed status but did not make status authoritative in process exit. | Validator now emits `overall_status` and exits nonzero on failed checks unless `-ReportOnly` is explicitly used. |
| MCP roots missing while MCP config passed | Validation failure | Config name checks did not prove live process-backed roots existed. | Validator now checks expected live root keys under the current app-server and fails missing roots. |
| Hardcoded Codex bundle hash paths | Drift-prone hardcoding | `node_repl`, `node`, and `codex` paths pointed to app bundle hash directories. | Added `node_repl.cmd`; MCP config now routes through stable shims and resolves current bundle tools at runtime. |
| Volatile `.tmp` marketplace source | Reproducibility failure | Runtime config pointed at `.codex\.tmp\bundled-marketplaces`, which can disappear or be regenerated. | Added `ensure-openai-bundled-marketplace.ps1`; config now points at a stable junction under `plugins\marketplaces\openai-bundled` targeting the current app bundle. |
| Active skill inventory drift | Policy drift | Config approved one set while active skill dirs drifted. | Validator derives expected skills from config. The active `pdf` skill is now represented in `config.toml` instead of being treated as an unconfigured extra. |
| Live runtime top-level check failed on valid live files | Validation design failure | Offline baseline and live runtime hygiene were conflated. | Split into `offline_baseline_minimal` and `live_runtime_hygiene`. |
| Memento runtime script drift | Source/runtime drift | Live script had `HOST` support; tracked script did not. | Synced `HOST`/client-host support into tracked and live script. |

## Runtime State Actions

Previously moved to Windows Recycle Bin during cleanup:

- `C:\Users\anise\.codex\.tmp\bundled-marketplaces`
- `C:\Users\anise\.codex\.tmp\marketplaces`
- `C:\Users\anise\.codex\skills-disabled\20260529-unconfigured-user-skills\playwright`

Current retained state:

- `C:\Users\anise\.codex\plugins\marketplaces\openai-bundled`: current stable marketplace junction.
- `C:\Users\anise\.codex\plugins\cache\openai-bundled\chrome\latest`: current valid plugin runtime junction.
- `C:\Users\anise\.codex\plugins\cache\openai-bundled\chrome\26.527.31326`: current installed Chrome plugin cache.
- `C:\Users\anise\.codex\skills\pdf`: active approved skill.
- active runtime processes: app-server child MCP roots are singleton and watched by cleanup watcher.

## Latest Verification

- `validate-codex-scaffold.ps1 -ReportOnly -Json`: `overall_status=pass`, `fail_count=0`.
- `C:\Users\anise\.codex\maintenance\scripts\validate-codex-scaffold.ps1 -ReportOnly -Json`: `overall_status=pass`, `fail_count=0`.
- `memento-mcp-runtime.ps1 -Action status`: `postgres_ready=True`, `memento_health=True`.
- `repair-chrome-plugin-runtime.ps1 -Mode status`: `ok=true`, no problems.
- Runtime cleanup status: duplicate MCP root keys empty; one owner-exit cleanup watcher active.

## Residual Risk

The owner-exit cleanup path is implemented and the watcher is active, but a full user-visible "close Codex Desktop and observe every child/native-host exit" proof was not run inside this live session because it would interrupt the current thread. That remains the end-to-end lifecycle proof.
