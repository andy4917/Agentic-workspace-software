# 2026-05-31 Expanded P0 Integrity Cleanup

## Scope

- Live runtime root: `C:\Users\anise\.codex`
- Managed source repo: `C:\Users\anise\Documents\Codex`
- App package: `OpenAI.Codex_26.527.3686.0_x64__2p2nqsd0c76g0`
- Goal: remove stale Codex runtime/toolchain residue, fix the root process cleanup logic, and restore zero-known-warning validation.

## Confirmed Root Causes

1. Stale duplicate Codex installs were reachable from the local environment:
   - `.codex\packages\standalone`
   - `scoop\apps\codex\current`
   - `scoop\shims\codex.exe`
2. The runtime cleanup script under-matched lifecycle correctness:
   - managed-root detection was too broad for arbitrary command lines;
   - child cleanup skipped descendants when the root process had already exited;
   - cleanup used a PowerShell `$pid` loop variable name that conflicts with `$PID`;
   - a second cleanup loop over known root PIDs still used the same `$pid` collision pattern;
   - watcher orphan cleanup could run before confirming the watched app-server was still alive;
   - cleanup for a dead app-server PID could kill the new app-server's active MCP roots.
3. Scaffold validation did not fail on orphan managed MCP roots.
4. Stale generated live manifests could preserve a false historical status after repair.

## Changes Applied

- Removed the standalone/Scoop Codex duplicate path from the active shim route.
- Tightened `codex-runtime-process-cleanup.ps1` root classification to known shims/processes only.
- Added managed orphan reporting and orphan cleanup with app-server liveness guards.
- Removed all remaining `$pid` loop-variable collision patterns from runtime cleanup.
- Updated `validate-codex-scaffold.ps1` to require `managed_orphans` reporting and zero orphan roots.
- Expanded toolchain source checks for `codex`, `node`, and `rg` first-command provenance.
- Synced changed runtime scripts and `codex.cmd` from managed source into `.codex`.
- Refreshed live validation manifests under `.codex\maintenance\manifests`.
- Normalized changed PowerShell and CMD files to repository line-ending policy.

## Verification Evidence

- `validate-codex-scaffold.ps1 -CodexHome C:\Users\anise\.codex -Json`: pass, `fail_count=0`.
- `check-toolchain-sources.ps1 -Json`: pass, `failures=0`, `warnings=0`.
- `codex-runtime-process-cleanup.ps1 -Action status -Json`:
  - one app-server: PID `33808`;
  - managed roots: `chrome-devtools`, `context7`, `node_repl`, `serena`;
  - `managed_orphans=[]`;
  - `duplicate_keys=[]`.
- `codex doctor --json`: `overallStatus=ok`.
- `scoop update`: completed successfully.
- `scoop status`: `Scoop is up to date. Everything is ok!`
- `scoop checkup`: `No problems identified!`
- `git diff --check`: no output, exit code 0.
- Dead app-server regression check: `cleanup-all -AppServerPid 13548` did not stop the active app-server PID `33808` or its managed roots.
- Computer Use connection check: Windows helper reachable; app inventory returned successfully.
- MCP smoke checks:
  - Serena project activation succeeded for `C:\Users\anise\Documents\Codex`;
  - Context7 resolved PowerShell docs;
  - Memento context call succeeded;
  - Node REPL path was exercised by Computer Use bootstrap.

## Rollback / Quarantine Notes

- Stale Codex duplicate installs and broken Scoop bucket state were removed or moved to the Recycle Bin during cleanup rather than hard-deleted where risk existed.
- Current active Codex command route is the `.codex` shim followed by OpenAI Codex App package resources, not Scoop or `.codex\packages\standalone`.

## Residual Risk

- Codex Desktop UI automation was not performed: the Computer Use safety policy forbids automating the Codex desktop app UI itself. The Windows helper was still used for direct app-environment confirmation.
- `codex doctor` reports the desktop app-server daemon as not running, with mode `ephemeral`; this is treated as expected for the Desktop app-server model because all other doctor checks are `ok`.
