# Notebook Hardware and Driver Maintenance - 2026-05-13

## Scope

- Host: `LENOVO 83JQ`, Yoga 7 2-in-1 14ILL10, Windows 11 Home build `26200`.
- User request: refresh managed toolchain records, verify shim usage, inspect
  laptop hardware health, pending updates, unused drivers/download packages,
  driver fit/latestness, duplicate files, and performance settings.
- Risk class: workstation maintenance. Changes were limited to reversible user
  file cleanup, package-manager cache cleanup, AC power configuration, and
  documentation.

## Toolchain Control

- Source class: local wrappers in `%USERPROFILE%\.codex\toolchains\shims`.
- Verification command:
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.codex\maintenance\scripts\check-toolchain-sources.ps1`
- Result: `status=pass; failures=0; warnings=0`.
- Explicit shim use was confirmed for package-manager and toolchain commands
  including `winget`, `scoop`, `npm`, `pnpm`, `python`, `uv`, `cargo`,
  `rustup`, `bun`, `deno`, `dotnet`, `next`, `vite`, `fastapi`, and compiler
  shims.

## Updates Applied or Confirmed

- `winget upgrade --include-unknown --accept-source-agreements`: no remaining
  installed-package upgrades after remediation.
- Confirmed versions:
  - `Logitech.OptionsPlus` `2.3.879545`
  - `Microsoft.VisualStudio.BuildTools` `18.6.0`
  - `Google.Chrome.EXE` `148.0.7778.168`
  - `Microsoft.DotNet.DesktopRuntime.9` `9.0.16`
  - `astral-sh.uv` `0.11.13`
  - `Warp.Warp` `v0.2026.05.06.15.42.stable_05`
  - `Microsoft.Teams` `26093.415.4620.1935`
- Windows Update COM search:
  - `IsInstalled=0`: `0`
  - `IsInstalled=0 and Type='Driver'`: `0`
- `scoop status`: `Scoop is up to date. Everything is ok!`

## Cleanup

- Downloads cleanup:
  - 35 obvious installer/driver package files moved to Windows Recycle Bin.
  - Approximate moved size: `3266.3 MB`.
  - Remaining package-like downloads: `606.4 MB`, mostly recent app installers,
    fonts, and project/archive files left untouched because they may be user
    artifacts.
  - Duplicate hash scan in `Downloads` for files larger than 1 MB: `0` duplicate
    groups across `14` scanned files.
- Package cache cleanup:
  - `npm cache clean --force` completed; `npm cache verify` reports no content
    entries.
  - `pnpm store prune` completed.
  - `scoop cache rm *` completed; post-check `C:\Users\anise\scoop\cache` is
    `0.0 MB`.
  - `scoop cleanup *` completed; post-check `C:\Users\anise\scoop\apps` is
    `1889.0 MB`.
- User temp cleanup:
  - Not run. Recursive deletion under `%LOCALAPPDATA%\Temp` was blocked by the
    local PreToolUse hook as an irreversible destructive action.

## Hardware Inventory

- CPU: `Intel(R) Core(TM) Ultra 5 228V`, 8 cores / 8 logical processors.
- RAM: `32 GB` LPDDR5x visible as eight Samsung 4 GB banks, configured clock
  `8533`.
- Storage: `SKHynix_HFS001TEM4X182N`, NVMe SSD, `Healthy`, operational status
  `OK`; C: free space was over `817 GB` during inspection.
- GPU: `Intel(R) Arc(TM) 130V GPU (16GB)`.
- BIOS: `QPCN21WW`, release date `2026-01-06`.
- Battery: `L23M4PF3`, charge `96%`; battery report shows design capacity
  `70,000 mWh`, full charge capacity `69,910 mWh`, cycle count `40`.
- Display panel EDID: Lenovo `LEN8AC3`, manufactured `2024`.

## Driver Fit and Latestness

- Active problem devices:
  - `pnputil /enum-devices /problem`: no devices found.
- Disconnected devices:
  - Several disconnected entries remain, including prior Lenovo DisplayHDR,
    Realtek USB GbE, Logitech Bluetooth HID, and standard Microsoft media/VHD
    components. These are device history entries, not active failures.
  - No driver packages were removed because reconnect behavior could break and
    driver-store removal requires elevated privileges.
- Lenovo System Update:
  - Installed: `Lenovo.SystemUpdate 5.08.03.59`.
  - Driver-only CLI run using Lenovo System Update filters returned exit code
    `1`, but log `C:\ProgramData\Lenovo\SystemUpdate\logs\tvsu_260513200045.log`
    recorded `Update count0`, `Packages not found`, and reboot suppressed.
  - Official Lenovo System Update command-line docs state package filters for
    applications/drivers/BIOS/firmware and warn that some reboot types can force
    prompts or reboot behavior, so BIOS/firmware automation was not forced.
- Key active driver comparison:
  - Lenovo graphics package in System Update repo: `32.0.101.8132`,
    release `2026-04-08`; active GPU driver: `32.0.101.8132`.
  - Lenovo WLAN package in repo: `23.160.0.4/6102.24.108.349/25.30.3.59`,
    release `2026-04-27`; active Intel Wi-Fi 7 BE201 driver: `24.30.1.1`.
  - Lenovo Bluetooth package in repo:
    `23.160.0.9/18.4029.2411.1917/25.30.3.59`, release `2026-04-08`; active
    Intel Bluetooth driver: `24.30.1.1`.
  - Lenovo NPU repo package: `32.0.100.4512`, release `2026-04-27`; active
    Intel AI Boost driver: `32.0.100.4723`.
  - Lenovo MEI repo package: `2517.8.1.0`; active MEI driver: `2517.8.1.0`.
  - Lenovo audio repo package: `6.0.9879.1`; active Realtek SST driver:
    `6.0.9879.1`.
- Driver-store duplicates/older candidates:
  - Intel Bluetooth driver store contains several `ibtusb.inf` packages at the
    same `24.30.1.1` version, including two marked `Legacy Preprod`.
  - Display store contains active Lenovo-ranked `oem213.inf` version
    `32.0.101.8132` and an outranked `oem143.inf` version `32.0.101.8629`.
  - These were not removed because active ranking and rollback behavior are
    controlled by Plug and Play, and `pnputil /delete-driver` needs elevation.

## Notable Health Findings

- WHEA / restart:
  - System log has a WHEA hardware error at `2026-05-13 18:13:39 +09:00`,
    followed by Kernel-Power 41 and bugcheck `0x0000013a`.
  - Minidump and LiveKernelReports access was denied without elevation, so the
    precise failing component was not decoded.
- Intel Connectivity Performance Suite:
  - `IntelConnect.exe` crash count in the last 7 days: `60`.
  - Active component: `Intel(R) Connectivity Performance Suite`
    `50.26.220.212`, signed by Microsoft Windows Hardware Compatibility
    Publisher, status `OK`.
  - Related services are running:
    `Intel Connectivity Network Service`, `IntelConnectService`,
    `Intel Analytics Service`, and `Intel Provider Data Helper Service`.
  - No Lenovo or Windows driver update was available for this component during
    this pass, so it remains a residual risk rather than a completed repair.

## Performance Configuration

- Previous active plan: Balanced, AC processor min `5%`, AC max `100%`, DC min
  `5%`, DC max `100%`.
- Applied:
  - `powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 100`
  - `powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMAX 100`
  - `powercfg /setactive SCHEME_CURRENT`
- Verified:
  - AC processor min: `100%`
  - AC processor max: `100%`
  - DC processor min remains `5%`
  - DC processor max remains `100%`
- RAM:
  - Installed memory is running at configured `8533`.
  - Page file exists at `C:\pagefile.sys`, allocated `2048 MB`; no change was
    made because this is stability policy, not a direct performance bottleneck.
- Virtualization:
  - `systeminfo` reports a hypervisor is detected and VBS is running.
  - `Win32_Processor` reports firmware virtualization fields as `False`; this
    may be masked by the active hypervisor/VBS state, but BIOS-level
    virtualization could not be changed from this session.

## Checks Not Run / Blocked

- Admin-only checks blocked by non-elevated session:
  - `powercfg /energy /duration 30`
  - `dism.exe /Online /Cleanup-Image /AnalyzeComponentStore`
  - `sfc /verifyonly`
  - `chkdsk C: /scan`
  - minidump / live kernel dump reads under `C:\Windows`
  - driver package deletion with `pnputil /delete-driver`
- Not forced:
  - BIOS/firmware update automation, because Lenovo documents reboot types that
    may force prompts or restarts even when other reboot suppression flags are
    present.
  - Intel Driver & Support Assistant installation, because Lenovo System Update
    and Windows Update reported no applicable driver updates and adding another
    resident scanner would expand workstation surface area.

## Rollback Notes

- Downloads files were sent to Windows Recycle Bin, not permanently deleted.
- AC performance change can be rolled back with:
  `powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN 5`
  followed by `powercfg /setactive SCHEME_CURRENT`.
- Cache cleanup rollback is package-manager regeneration only; old Scoop app
  versions and cache archives are not retained after cleanup.
- No driver packages were removed and no BIOS/firmware update was forced.

## Status

- General app and Windows update state: complete for non-elevated checks.
- Downloads/package cache cleanup: complete for safe/reversible scope.
- Driver latestness: complete for Lenovo/Windows Update evidence; no applicable
  driver update found.
- Driver removal: intentionally not performed; no active problem device and
  driver-store deletion needs elevation.
- Hardware health: continue/needs elevated follow-up because WHEA bugcheck and
  IntelConnect crash loop remain unresolved.
