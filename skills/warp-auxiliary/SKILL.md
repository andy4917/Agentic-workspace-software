---
name: warp-auxiliary
description: Launch and inspect Warp as an auxiliary local terminal surface without stealing focus. Use when the user explicitly asks to use Warp alongside Codex, open a minimized Warp helper window, or check the local Warp auxiliary status.
---

# Warp Auxiliary

Use this skill only when the user explicitly asks for Warp or when a task already depends on the local Warp auxiliary helper.

## Safety

- Do not launch Warp for ordinary shell work.
- Do not use Warp as a hidden fallback for Codex shell commands.
- Do not change Warp settings from this skill.
- Run status checks before launching when the task is about availability or configuration.

## Script

The helper script is in `scripts/Start-WarpAuxiliary.ps1`.

To inspect status:

```powershell
. "$env:USERPROFILE\.codex\skills\warp-auxiliary\scripts\Start-WarpAuxiliary.ps1"
Get-WarpAuxiliaryStatus
```

To launch minimized and restore the previous foreground window:

```powershell
. "$env:USERPROFILE\.codex\skills\warp-auxiliary\scripts\Start-WarpAuxiliary.ps1"
Start-WarpAuxiliary -WorkingDirectory "C:\path\to\repo"
```
