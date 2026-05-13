# 2026-05-13 Driver Store Safe Repair

## Scope

User asked to continue driver handling with a safety-first policy:

- use `pnputil` for driver-store work where possible;
- repair confirmed repairable system issues;
- prefer leaving a package in place when removal is riskier than retention.

## Diagnostic Root

Local-only evidence was written under:

`%USERPROFILE%\.codex\maintenance\diagnostics\20260513-214922-driverstore-safe-repair`

The diagnostics directory is intentionally ignored by Git because it contains
machine-local logs and exported driver packages.

## Repair Actions

- Attempted to create a System Restore point before driver cleanup.
  - Result: not created.
  - Reason: Windows reported the required service path was disabled or no
    enabled device was associated with it.
  - Safety response: continued only with exported driver backups and
    conservative `pnputil` deletion, without `/force` and without `/uninstall`.
- Ran `DISM /Online /Cleanup-Image /RestoreHealth`.
  - Exit code: 0.
  - Result: operation completed successfully.
- Ran `sfc /scannow`.
  - Exit code: 0.
  - CBS evidence: `[SR] Repairing 0 components` and `[SR] Repair complete`.

## Driver Cleanup Policy

Deletion was allowed only when all of these were true:

- package was an inactive duplicate;
- an active same-device or same-original replacement was already installed;
- package was exported successfully before deletion;
- deletion could succeed through plain `pnputil /delete-driver <oem>.inf`;
- no `/force` and no broad `/uninstall` were used.

Packages were left in place when they were system, extension, display-rank,
network rollback, or otherwise ambiguous packages.

## Deleted Driver Packages

The following packages were exported first, then deleted successfully through
plain `pnputil /delete-driver`:

- `oem220.inf`
  - reason: inactive duplicate Lenovo monitor HDR package; active same-version
    `oem37.inf` is installed.
- `oem26.inf`
  - reason: inactive older Realtek camera IR package; active newer `oem1.inf`
    is installed.
- `oem49.inf`
- `oem174.inf`
- `oem141.inf`
- `oem114.inf`
- `oem151.inf`
- `oem27.inf`
- `oem110.inf`
- `oem149.inf`
- `oem58.inf`
  - reason for all Intel Bluetooth packages above: inactive duplicate
    `ibtusb.inf` packages; active same-version `oem154.inf` is installed.

Driver package count changed from 229 to 218.

## Deferred Driver Packages

The following duplicate groups were intentionally left in place:

- `bertreader.inf`
  - reason: no active replacement was proven in the current device set.
- `elevocapo64ext.inf`
  - reason: audio extension package; no active replacement was proven.
- `iclsclient.inf`
  - reason: Intel software component package; no active replacement was proven.
- `iigd_dch.inf`
  - reason: newer `oem143.inf` exists, but active `oem213.inf` has the better
    exact subsystem rank for `PCI\VEN_8086&DEV_64A0&SUBSYS_3DAE17AA`.
    Forcing the newer generic match would be less safe.
- `intcdmicext_e.inf`
  - reason: audio/microphone extension package; no active replacement was
    proven.
- `ipf_acpi.inf`
- `ipf_cpu.inf`
  - reason: Intel Innovation Platform Framework system packages; older inactive
    duplicates exist, but this surface affects platform power/thermal behavior.
    Retention is safer than cleanup.
- `netwtw08.inf`
  - reason: inactive Wi-Fi package family, while active Wi-Fi uses
    `netwtw6e.inf`. Keeping rollback packages is safer than cleanup.
- `udccomponent.inf`
  - reason: Lenovo software component duplicate exists, but version/date order
    is ambiguous. Retention is safer.

## Direct Checks Run

- `pnputil /enum-drivers` before cleanup:
  - total parsed packages: 229.
  - duplicate groups: 12.
  - duplicate packages: 32.
- `pnputil /export-driver <inf> <backup-path>` for every deletion candidate:
  - all selected packages exported successfully before deletion.
- `pnputil /delete-driver <inf>` for selected candidates:
  - all 11 selected packages deleted successfully.
  - no `/force`.
  - no `/uninstall`.
- `pnputil /enum-drivers` after cleanup:
  - total parsed packages: 218.
  - duplicate groups: 9.
  - duplicate packages: 18.
- `pnputil /enum-devices /problem` after cleanup:
  - no problem devices found.
- `Get-PnpDevice -Class Bluetooth,Camera,Monitor,Display,Net` after cleanup:
  - relevant devices returned `OK`, including Intel Bluetooth, integrated
    camera, integrated IR camera, DisplayHDR monitor, Intel Arc 130V GPU, and
    Intel Wi-Fi 7 BE201.
- `pnputil /enum-devices /class Display /drivers`:
  - active GPU package `oem213.inf` is best-ranked and installed due exact
    subsystem match.
  - newer `oem143.inf` is present but outranked as a more generic match.
- `pnputil /enum-devices /class Net /drivers`:
  - active Wi-Fi package is `oem197.inf` / `netwtw6e.inf`.
- `IntelConnectService` check:
  - service remains stopped and disabled.
  - no `IntelConnect.exe` process is running.
- `powercfg /GETACTIVESCHEME`:
  - active scheme remains `8aac44fc-cf84-42b8-8caa-42d1f26973c6`
    (`best performance` / Ultimate Performance).

## Not Run

- No `pnputil /delete-driver /force` was run.
  - reason: higher risk and not needed for the selected inactive duplicates.
- No broad `pnputil /delete-driver /uninstall` was run.
  - reason: user asked for safety-first handling; selected packages were not
    active device bindings.
- No forced GPU driver update was run.
  - reason: the newer Intel GPU package is present but outranked by the active
    exact subsystem match.
- No reboot was forced.
  - reason: the cleanup completed without problem devices and without requests
    for restart.

## Rollback Notes

Exported copies of deleted packages are under:

`%USERPROFILE%\.codex\maintenance\diagnostics\20260513-214922-driverstore-safe-repair\driver-export-before-delete`

If a deleted package must be restored, use a package-specific exported INF with:

`pnputil /add-driver <exported-inf-path> /install`

Prefer restoring only the affected package rather than bulk-restoring all
exports.

## Residual Risks

- System Restore point creation failed because the relevant Windows service path
  is disabled or unavailable. The compensating control is per-package driver
  export before deletion.
- Remaining duplicate packages are intentionally retained because deletion is
  not clearly safer than leaving them in place.
- A reboot was not performed, so this pass verifies live device state before
  reboot only. If a boot-only issue recurs, collect a new dump and compare
  driver load order.
- Historical Kernel-Boot 247 and the earlier 0x13A crash remain monitoring
  items; this pass did not prove a single root-cause driver.

## PM Independent Verification

The PM independently checked the deletion result using a fresh
`pnputil /enum-drivers` pass, problem-device enumeration, live PnP class status,
IntelConnect service/process state, and active power scheme state. Deleted
packages were selected from the refreshed duplicate list rather than copied
blindly from the previous report.

## Status

`complete` for the safety-first driver-store cleanup and system repair pass.
