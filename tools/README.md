# Workstation Utility Tools

This directory contains small, task-specific utilities that are versioned with
the managed Codex workstation source but are not global shell shims.

## Android Camera Shutter Toggle

`android-camera-shutter-toggle.ps1` reads or changes Samsung Android's system
setting for forced camera shutter sound through ADB.

Usage:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\android-camera-shutter-toggle.ps1 Status
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\android-camera-shutter-toggle.ps1 Off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\android-camera-shutter-toggle.ps1 On
powershell.exe -NoProfile -ExecutionPolicy Bypass -File tools\android-camera-shutter-toggle.ps1 Toggle
```

Options:

- `-Serial <device>` selects one authorized ADB device when multiple devices are
  connected.
- `-NoForceStop` skips restarting `com.sec.android.app.camera` after a change.

ADB resolution order:

1. `ADB` environment variable.
2. `adb` on `PATH`.
3. Android SDK platform-tools under `ANDROID_HOME`, `ANDROID_SDK_ROOT`,
   `%LOCALAPPDATA%\Android\Sdk`, `%USERPROFILE%\AppData\Local\Android\Sdk`, or
   `C:\platform-tools`.

The script expects exactly one authorized ADB device unless `-Serial` is passed.
It reports the ADB path, previous value, current value, interpreted shutter
state, and whether the camera app was restarted.
