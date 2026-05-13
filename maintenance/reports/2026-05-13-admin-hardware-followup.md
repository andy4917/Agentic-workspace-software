# 2026-05-13 Admin Hardware Follow-up

## Scope

User authorized elevated diagnostics for DISM, SFC, CHKDSK, `powercfg /energy`,
minidump analysis, driver-store review, performance tuning, BIOS/firmware
staleness review, and IntelConnect crash handling.

## Changed Surfaces

- Installed Windows Debugging Tools through winget package
  `Microsoft.WindowsSDK.10.0.26100` using the Windows SDK installer override
  `/features OptionId.WindowsDesktopDebuggers /quiet /norestart`.
- Added explicit wrappers:
  - `%USERPROFILE%\.codex\toolchains\shims\cdb.cmd`
  - `%USERPROFILE%\.codex\toolchains\shims\dumpchk.cmd`
  - `%USERPROFILE%\.codex\toolchains\shims\symchk.cmd`
- Updated `%USERPROFILE%\.codex\toolchains\README.md` to record Windows
  debugging wrappers.
- Added `.gitignore` entry for `maintenance/diagnostics/` because the folder
  contains local dumps, symbols, and machine diagnostics that should not be
  published.
- Disabled `IntelConnectService`.
- Set active power scheme to `8aac44fc-cf84-42b8-8caa-42d1f26973c6`
  (`Ultimate Performance` / Korean UI `best performance`).
- Set AC and DC power values for maximum performance:
  - processor minimum state: 100
  - processor maximum state: 100
  - processor energy performance preference: 0
  - processor performance boost mode: 2
  - system cooling policy: active
  - wireless power saving: maximum performance
  - PCIe link state power management: off
  - disk idle timeout: 0
  - sleep timeout: 0
  - display timeout: 0
- Updated Defender signatures; pending Windows Update count is now zero.

## Local Evidence Root

Diagnostics were written under:

`%USERPROFILE%\.codex\maintenance\diagnostics\20260513-204420-admin-hardware`

This directory is local-only and intentionally ignored by Git.

## Direct Checks Run

- `DISM /Online /Cleanup-Image /CheckHealth`
  - exit code: 0
  - result: no component store corruption detected
- `DISM /Online /Cleanup-Image /ScanHealth`
  - exit code: 0
  - result: no component store corruption detected
- `DISM /Online /Cleanup-Image /AnalyzeComponentStore`
  - exit code: 0
  - component store cleanup recommended: no
- `sfc /verifyonly`
  - exit code: 0
  - CBS `[SR]` tail shows verify transactions completed
- `chkdsk C: /scan`
  - exit code: 0
  - result: file system scanned, no problems, no bad sectors
- `powercfg /energy /duration 60`
  - exit code: 0
  - report: `energy-report.html`
  - result: 4 errors, 5 warnings, 33 information items
  - notable items: high CPU utilization during trace, long display/sleep
    timeouts, USB selective-suspend related entries
- `powercfg /energy /duration 60` after maximum-performance changes
  - exit code: 0
  - report: `energy-report-after-maxperf.html`
  - result: 14 errors, 1 warning, 33 information items
  - notable items: disabled display/sleep/disk idle timeouts, processor
    minimum state 100 percent on AC and DC, wireless maximum performance,
    PCIe ASPM off, active plan `8aac44fc-cf84-42b8-8caa-42d1f26973c6`
- `cdb -z 051326-12109-01.dmp -c "!analyze -v; .bugcheck; kv; lmtn; q"`
  - bugcheck: `0x13A KERNEL_MODE_HEAP_CORRUPTION`
  - parameters: `17 ffffac0bc9100340 ffffac0bd0e1fd20 0`
  - process: `System`
  - failure bucket: `0x13a_17_nt!RtlpHeapHandleError`
  - system uptime at crash: 17 seconds
- `cdb -z 051326-12109-01.dmp -c "!blackboxpnp; !blackboxntfs; !blackboxbsd; !whea; q"`
  - PnP problem code: 24 on `SWD\SGDEVAPI\...`
  - NTFS blackbox: 0 slow I/O timeout records and 0 oplock timeout records
  - WHEA extension in dump: 0 error sources
- WHEA event extraction from System log:
  - one WHEA-Logger event in the last 14 days, at 2026-05-13 18:13:39 KST
  - CPER header severity: 1
  - section type GUID observed: `81212a96-09ed-4996-9471-8d729c8e69ed`
- `Get-WinEvent` for Kernel-Boot 247:
  - repeated events in the last 14 days
  - event data: `Status=0`, `FailureReason=4`
  - message: Windows firmware could not be loaded/applied
- Windows Update COM search:
  - pending updates: 0 after Defender update
  - pending driver updates: 0
- Lenovo System Update repository inspection:
  - BIOS catalog package: `qpcn21ww`
  - package version: `QPCN21WW`
  - package release date: 2026-04-14
  - installed SMBIOS version: `QPCN21WW`
  - installed BIOS release date reported by SMBIOS: 2026-01-06
- Device health:
  - `pnputil /enum-devices /problem`: no devices found
- Storage health:
  - physical disk: healthy
  - CHKDSK: no problems, zero bad sectors
  - storage reliability counter: temperature 45 C, wear 0
- Security/firmware state:
  - Secure Boot: true
  - BitLocker on C: fully decrypted, protection off
  - TPM present/ready/enabled/activated/owned
- IntelConnect:
  - Application log 7-day count:
    - 60 `Application Error` events for `IntelConnect.exe`
    - 104 Windows Error Reporting events mentioning IntelConnect
    - 204 IntelConnectService log entries
  - crash signature: `BEX64`, exception `0xc0000409`, offset `0x235635`
  - executable: `C:\WINDOWS\System32\drivers\Intel\ICPS\IntelConnect.exe`
  - file version: `5.0.220.212`
  - signed by Microsoft Windows Hardware Compatibility Publisher
  - related driver package: `oem182.inf`, original `icpscomponent.inf`,
    driver version `02/19/2026 50.26.220.212`
- Driver-store duplicate candidate review:
  - total parsed driver packages: 229
  - duplicate original INF names: 12
  - non-active older duplicate candidates: 17
  - candidates exported successfully to local diagnostics backup
  - no driver-store packages were deleted because safe DriverStore removal uses
    `pnputil`, not Recycle Bin

## Interpretation

- The 2026-05-13 crash is a kernel heap corruption bugcheck during early boot.
  The minidump does not identify a single third-party driver as the corrupting
  writer. The available evidence points to an early boot driver/firmware path
  rather than user-mode application code.
- WHEA is present as a fatal CPER record after the bugcheck window, but it does
  not decode locally to a conventional corrected CPU, memory, PCIe, or disk
  error. It is best treated as firmware-path evidence, not proof of a failing
  CPU/RAM/SSD.
- BIOS does not appear version-stale. Current SMBIOS version and Lenovo catalog
  version are both `QPCN21WW`. The date mismatch is package metadata/release
  timing, not a newer BIOS version being missed.
- Repeated Kernel-Boot 247 events remain a residual firmware/Windows firmware
  handoff signal. They predate and postdate the crash and should be watched
  after the next reboot/update cycle.
- IntelConnect is objectively noisy and unstable on this machine. Disabling only
  `IntelConnectService` is the least risky corrective action because core
  Wi-Fi/Bluetooth drivers remain separate and active.
- Direct driver-store deletion was not performed because the user required
  Recycle Bin movement only. Directly moving DriverStore directories to Recycle
  Bin would risk breaking DriverStore metadata. If deletion is later accepted,
  use `pnputil /delete-driver <oem.inf> /uninstall` after confirming each
  candidate and keeping the exported backup.

## Rollback Notes

- Re-enable IntelConnect:
  - `Set-Service -Name IntelConnectService -StartupType Manual`
  - `Start-Service -Name IntelConnectService`
- Restore previous-style balanced plan:
  - `powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e`
  - processor AC/DC minimum values may need to be reset manually if desired
- Debugging Tools:
  - uninstall `Microsoft.WindowsSDK.10.0.26100` or remove the Debugging Tools
    feature through the Windows SDK installer if a smaller footprint is needed
- Driver candidates:
  - exported copies are under the diagnostics root
  - no system driver-store deletion was performed

## Residual Risks

- The 0x13A crash has no single driver culprit in the mini kernel dump.
  Recurrence requires collecting a kernel or complete memory dump and then
  enabling targeted Driver Verifier only if a repeat pattern appears.
- `IntelConnectService` is disabled, not removed. If another ICPS service
  starts it through a different path later, uninstalling `oem182.inf` may be
  considered, but that is not Recycle Bin reversible.
- Kernel-Boot 247 firmware handoff events are still present historically.
  There is no pending Lenovo BIOS/firmware update, so the immediate action is
  monitoring plus future Lenovo/Windows firmware updates.
- Maximum-performance power settings on DC will materially reduce battery life
  and raise heat/fan activity.

## Status

`complete` for the authorized non-reboot elevated follow-up.
