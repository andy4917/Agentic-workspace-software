# Verify: Workstation Workflow Compact Control Plane

Run the narrowest relevant checks after each slice:

```powershell
git -C $env:USERPROFILE\.codex diff --check
```

```powershell
@'
import pathlib, tomllib
tomllib.loads(pathlib.Path(r"C:\Users\anise\.codex\config.toml").read_text(encoding="utf-8"))
'@ | python -
```

```powershell
Get-Content $env:USERPROFILE\.codex\maintenance\CODEX_HOME_STRUCTURE_STATE.json -Raw | ConvertFrom-Json | Out-Null
```

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $env:USERPROFILE\.codex\maintenance\scripts\check-naming-conventions.ps1 -Json
```

Optional broader checks when the edited surface justifies them:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $env:USERPROFILE\.codex\maintenance\scripts\check-codex-native-alignment.ps1 -Json -WriteReport
```

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File $env:USERPROFILE\.codex\maintenance\scripts\memento-mcp-runtime.ps1 verify
```
