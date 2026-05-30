# Codex App Close Lifecycle Hotfix

Date: 2026-05-31

## User-Visible Failure

The expected behavior is that closing the Codex app also ends the work owned by
that app session. Electron/Chromium may show multiple `Codex.exe` processes while
the app is open, but app-owned MCP roots, app-server helpers, and Chrome native
host helpers should not remain as unmanaged residue after the app closes.

## Current Evidence

- Live app-server PID: `32184`.
- Live managed roots are singleton:
  - `chrome-devtools`
  - `context7`
  - `node_repl`
  - `serena`
- `managed_orphans=[]`.
- `duplicate_keys=[]`.
- Initial validator failure in this turn:
  - `runtime_cleanup_watcher_active=fail`
  - `watchers=[]`
- After repair:
  - `runtime_cleanup_watcher_active=pass`
  - watcher PID `18216`
  - watcher has `StopAppServerOnOwnerExit=true`

## Root Cause

There were two lifecycle gaps:

1. Historical watcher instances crashed on app-server exit because older cleanup
   code used PowerShell's reserved `$PID` variable as a loop variable in the
   `KnownRootPids` cleanup path. The current cleanup script already contains the
   `$knownRootPid` fix, and the live and managed cleanup script hashes match.
2. The live compact hook did not re-run `ensure-watch` on new sessions or prompt
   turns. After the previous watcher exited with the prior app-server, the new
   app-server session could run without a cleanup watcher.

## Fix

- Started the live cleanup watcher for the current app-server.
- Updated live `C:\Users\anise\.codex\hooks\compact-codex-hook.ps1` so
  `SessionStart` and `UserPromptSubmit` call:
  `codex-runtime-process-cleanup.ps1 -Mode ensure-watch -StopAppServerOnOwnerExit`.
- Added the same hook source at `hooks/compact-codex-hook.ps1` so the live hook
  is reviewable from the managed source repository.

## Validation

- Parsed live and managed compact hook scripts with PowerShell parser: pass.
- Ran synthetic `UserPromptSubmit`: pass; hook ledger recorded
  `runtime_cleanup_watch.status=ok`.
- Ran synthetic `SessionStart`: pass; hook returned updated context and ledger
  recorded `runtime_cleanup_watch.status=ok`.
- `codex-runtime-process-cleanup.ps1 -Mode status`: one watcher, no managed
  orphans, no duplicate keys.
- `validate-codex-scaffold.ps1 -CodexHome C:\Users\anise\.codex -Json`:
  `overall_status=pass`, `fail_count=0`.
- `check-toolchain-sources.ps1 -Json`: `status=pass`, `failures=0`,
  `warnings=0`.

## Root Layout Status

- `C:\Users\anise\.codex` is the live Codex runtime root and `CODEX_HOME`.
- `C:\Users\anise\Documents\Codex` is the managed source repository.
- `C:\Users\anise\Documents\Codex\.codex` is a tracked source subdirectory, not
  the live runtime root. Its tracked files are limited to project environment
  setup source.
- The live and managed `AGENTS.md` files intentionally differ by scope. The live
  one is the compact bootstrap; the managed one is the longer policy source.

## Not Run

- Full end-to-end proof of clicking the Codex window close button was not run in
  this live thread because it would terminate the active session. The current
  direct proof is the lifecycle watcher route that will run when the app-server
  or owner process exits.
