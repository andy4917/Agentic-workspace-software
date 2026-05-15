# Windows Server Doctor And Workspace Stability Review

Date: 2026-05-15

## Scope

This review follows up Codex thread
`019e2961-126d-7873-9567-950837676378` and focuses on
Windows-native runtime reliability, doctor coverage, design boundary conflicts,
maintenance data capture, and workspace management.

The affected Codex home is `%USERPROFILE%\.codex`. Product repositories under
`%USERPROFILE%\code\Dev-Product` remain out of scope.

## Previous Session Handoff

- Parent repository commit `05de4f1` recorded the Memento MCP runtime repair
  routine and incident manual update.
- Memento source commit `2f33431` recorded the adaptive search adaptor disable
  switch and LinkStore schema fix.
- The confirmed failure mode was a shared Memento PostgreSQL runtime stuck
  state, not a thread-local timeout.
- The repaired runtime uses PostgreSQL on `127.0.0.1:55432` and Memento HTTP on
  `127.0.0.1:57332`.

## Source-Backed Server Notes

- Microsoft service guidance says services should be stoppable/restartable
  through Service Control Manager without requiring a reboot, and should define
  recovery/reset behavior for failures:
  https://learn.microsoft.com/en-us/windows/win32/rstmgr/guidelines-for-services
- PostgreSQL `pg_ctl` can register/unregister PostgreSQL as a Windows service,
  supports `-l` log output redirection, has explicit `smart`/`fast`/`immediate`
  stop modes, and its wait mode can time out while the operation continues in
  the background:
  https://www.postgresql.org/docs/current/app-pg-ctl.html
- Node.js documents that `SIGTERM` is not supported on Windows and that sending
  `SIGINT`, `SIGTERM`, or `SIGKILL` to another process on Windows causes
  unconditional termination. The local manager must not rely on POSIX signal
  behavior for graceful shutdown:
  https://nodejs.org/api/process.html
- Node.js `server.close()` stops accepting new connections and closes
  asynchronously after existing connections finish. This is useful inside a
  controllable Node server, but external Windows process management still needs
  PID, health, and timeout checks:
  https://nodejs.org/api/net.html
- Windows Automatic Maintenance tasks run opportunistically when the machine is
  idle and on AC power, so they are appropriate for report-only maintenance but
  not for urgent runtime recovery:
  https://learn.microsoft.com/en-us/windows/win32/taskschd/task-maintenence
- Microsoft Task Scheduler troubleshooting starts by testing the script
  directly, then checking task status/history and long-running process behavior:
  https://learn.microsoft.com/en-us/troubleshoot/windows-server/system-management-components/troubleshoot-scheduled-tasks-not-running

## Applied Changes

- `codex_agent_harness.py doctor --json` now includes `memento_runtime`.
  It runs `memento-mcp-runtime.ps1 status`, requires PostgreSQL readiness and
  HTTP health, checks the managed memory ceiling, verifies the managed ONNX and
  embedding defaults, and scans recent Memento/PostgreSQL logs for known
  Windows failure signatures.
- `codex-home-maintenance.ps1 -Mode Report` now degrades gracefully when
  `es.exe` exists but Everything IPC is unavailable. The report records the
  per-query error instead of aborting the full workspace management report.
- `codex-home-maintenance.ps1` no longer scans `.codex-global-state.json` or
  `session_index.jsonl` for active reference matches. Those files can contain
  prompt history or session metadata; maintenance reports should inspect
  policy/config surfaces, not raw conversation state.
- `MCP_RUNTIME_STATUS.md` now records doctor coverage for Memento runtime
  failures and recurrence-risk signatures.
- `WORKSTATION_MAINTENANCE.md` now includes doctor and report-only workstation
  maintenance commands in the default check set.

## Design Boundaries

- `memento` remains a Codex-global PM memory support service. It is not a
  completion authority and does not replace current instructions, repository
  files, tests, runtime output, or PM verification.
- `memento-mcp-runtime.ps1` owns start/stop/restart/repair/verify for the local
  Memento HTTP process and dedicated PostgreSQL data directory. Forced stop
  remains scoped to the Memento `pgdata` process tree.
- `codex_agent_harness.py doctor` owns fast health and recurrence-risk checks.
  It does not mutate runtime state.
- `codex-home-maintenance.ps1 -Mode Report` owns report-only workspace hygiene
  inventory. Cleanup remains separate and must keep archive/Recycle Bin
  semantics.
- A Windows service registration was not applied in this pass. It would be an
  active runtime and administrator-bound change. If always-on service behavior
  becomes required, the safer staged path is: direct script verification,
  explicit service design, `pg_ctl register` or a service wrapper with SCM
  recovery settings, then doctor/verify after reboot.

## Maintenance Data Capture

- Runtime health: `maintenance\scripts\memento-mcp-runtime.ps1 status` and
  `verify`.
- Fast aggregate health: `maintenance\scripts\codex_agent_harness.py doctor --json`
  and `reports\doctor.latest.json`.
- Workspace hygiene: `maintenance\scripts\codex-home-maintenance.ps1 -Mode Report`
  and `maintenance\reports\codex-home-maintenance.latest.json`.
- Failure history: `%USERPROFILE%\.codex\state\memento-mcp\logs\*.log`,
  `reports\verification.latest.json`, and `trajectories\runs.jsonl`.
- Recurring check: `automations\weekly-workstation-workflow-health-check` remains
  report-only and must not mutate local state automatically.

## Current Judgment

The best current operating model is not to immediately turn the Memento runtime
into a Windows service. The lower-risk fit for this workstation is a managed
Windows-native runtime script with direct readiness checks, doctor coverage, and
report-only scheduled maintenance. Service registration is a future option only
if the user wants boot-persistent always-on behavior and accepts the active
runtime/admin boundary.

## Verification

Run:

```powershell
%USERPROFILE%\.codex\toolchains\shims\python.cmd %USERPROFILE%\.codex\maintenance\scripts\codex_agent_harness.py doctor --json
powershell.exe -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.codex\maintenance\scripts\codex-home-maintenance.ps1 -Mode Report
powershell.exe -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.codex\maintenance\scripts\memento-mcp-runtime.ps1 verify
```

Expected result:

- doctor passes when the current runtime is healthy.
- doctor records historical pre-start Memento log risk patterns as warnings.
- codex-home-maintenance report completes even when Everything IPC is not
  running.
- Memento verify reports `status=pass`.

## Residual Risks

- Historical PostgreSQL shared-memory `error code 487` log lines remain in
  local logs. Doctor now exposes them as warning evidence unless they recur
  after the current managed runtime start.
- Everything CLI name auditing depends on the Everything service. When the
  service is not running, the workspace report now records degraded evidence
  instead of failing.
- Full always-on service recovery was intentionally not installed in this pass.
  That avoids an admin/runtime mutation but means recovery remains script-driven
  rather than SCM-driven.
