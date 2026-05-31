# Codex App Close Lifecycle Hotfix

Date: 2026-05-31

## User-Visible Failure

The expected behavior is that closing the Codex app ends the work owned by that
app session. Electron/Chromium can legitimately show multiple `Codex.exe`
processes while the app is open, but app-owned MCP roots, app-server helpers,
and native helper processes should not remain as unmanaged residue after the
Codex owner window is closed.

## Current Evidence

- Computer Use connected to Windows and captured Task Manager directly.
- Task Manager showed a live `Codex(10)` group while this session was open.
- Live Codex owner PID: `19168`.
- Live app-server PID: `14456`, parent PID `19168`.
- Live cleanup watcher PID: `14024`.
- Live watcher guards:
  - `StopAppServerOnOwnerExit=true`
  - `StopAppServerOnOwnerNoVisibleWindow=true`
  - `OwnerNoVisibleWindowGraceSeconds=5`
- Live managed roots are singleton:
  - `chrome-devtools`
  - `context7`
  - `node_repl`
  - `serena`
- `managed_orphans=[]`.
- `duplicate_keys=[]`.
- `validate-codex-scaffold.ps1 -CodexHome C:\Users\anise\.codex -Json`:
  `overall_status=pass`, `fail_count=0`.
- Memento HTTP health was restored:
  `http://127.0.0.1:57332/health` returned HTTP 200 healthy.
- `config.d/00-policy.toml` was reconciled with the generated `config.toml`
  `default-service-tier = "priority"` line.

## Root Cause

There were three lifecycle gaps:

1. Historical watcher instances crashed on app-server exit because older cleanup
   code used PowerShell's reserved `$PID` variable as a loop variable in the
   `KnownRootPids` cleanup path. The current cleanup script already contains the
   `$knownRootPid` fix.
2. The compact hook must re-run `ensure-watch` on `SessionStart` and
   `UserPromptSubmit`; otherwise a new app-server session can run without a
   cleanup watcher after reboot or app restart.
3. The prior watcher only treated app-server exit or owner-process exit as the
   terminal signal. If the Codex close button leaves the owner process alive but
   removes the visible owner window, the watcher did not treat that as
   `close = terminate work`, so the app-server tree could remain alive.

## Fix

- Extended `codex-runtime-process-cleanup.ps1` with a visible-window lifecycle
  guard:
  `-StopAppServerOnOwnerNoVisibleWindow`.
- The watcher now enumerates visible top-level Windows windows through Win32,
  ignores the Computer Use overlay window, and treats the absence of any visible
  Codex owner window for 5 seconds as an owner-close signal.
- On that signal, the watcher stops the Codex owner process tree, which includes
  the app-server and app-owned MCP/helper descendants.
- Updated `compact-codex-hook.ps1` so `SessionStart` and `UserPromptSubmit`
  call:
  `codex-runtime-process-cleanup.ps1 -Mode ensure-watch -StopAppServerOnOwnerExit -StopAppServerOnOwnerNoVisibleWindow`.
- Updated `validate-codex-scaffold.ps1` so a live app-server requires a watcher
  with both owner-exit and owner-no-visible-window guards.
- Repaired live `.codex` runtime copies of the cleanup script, validator, and
  compact hook.
- Restored memento runtime and reconciled `config.d/00-policy.toml`.

## Validation

- Computer Use Task Manager snapshot: live `Codex(10)` group observed.
- Win32 visible-window scan while app was open:
  - PID `19168`, title `Codex`.
  - Computer Use overlay ignored by the close lifecycle guard.
- PowerShell parser:
  - `maintenance/scripts/codex-runtime-process-cleanup.ps1`: pass.
  - `maintenance/scripts/validate-codex-scaffold.ps1`: pass.
  - `hooks/compact-codex-hook.ps1`: pass.
- Live and managed script hashes matched after sync.
- `codex-runtime-process-cleanup.ps1 -Mode status`:
  - app-server PID `14456`.
  - watcher PID `14024`.
  - no managed orphans.
  - no duplicate keys.
  - watcher has owner-exit and owner-no-visible-window guards.
- `validate-codex-scaffold.ps1 -CodexHome C:\Users\anise\.codex -Json`:
  `overall_status=pass`, `fail_count=0`.

## Root Layout Status

- `C:\Users\anise\.codex` is the live Codex runtime root and `CODEX_HOME`.
- `C:\Users\anise\Documents\Codex` is the managed source repository.
- `C:\Users\anise\Documents\Codex\.codex` is a tracked source subdirectory, not
  the live runtime root. Its tracked files are limited to project environment
  setup source.
- The live and managed `AGENTS.md` files intentionally differ by scope. The live
  one is the compact bootstrap; the managed one is the longer policy source.

## Not Run

- A destructive end-to-end click of the active Codex window close button was not
  run inside this live thread because it would terminate the active session.
  The direct proof available in-session is the new watcher state, current visible
  owner-window detection while open, and validator enforcement that the watcher
  now carries the no-visible-window close guard.
