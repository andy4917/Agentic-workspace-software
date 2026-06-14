$ErrorActionPreference = "Stop"

$aliasStub = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\pwsh.exe"
$candidates = @()

$windowsAppsRoot = Join-Path $env:ProgramFiles "WindowsApps"
if (Test-Path -LiteralPath $windowsAppsRoot) {
    $candidates += @(Get-ChildItem -LiteralPath $windowsAppsRoot -Directory -Filter "Microsoft.PowerShell_*__8wekyb3d8bbwe" -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        ForEach-Object { Join-Path $_.FullName "pwsh.exe" })
}

$candidates += (Join-Path $env:ProgramFiles "PowerShell\7\pwsh.exe")
$candidates += (Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe")

$command = Get-Command pwsh.exe -ErrorAction SilentlyContinue
if ($null -ne $command -and -not [string]::IsNullOrWhiteSpace([string]$command.Source)) {
    if ([string]$command.Source -ne $aliasStub) {
        $candidates += [string]$command.Source
    }
}

$tool = @($candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1)
if ($tool.Count -eq 0) {
    Write-Error "PowerShell executable not found. Install PowerShell 7 or repair the Codex pwsh shim."
    exit 1
}

& $tool[0] @args
exit $LASTEXITCODE
