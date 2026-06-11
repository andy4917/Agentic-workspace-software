$ErrorActionPreference = "Stop"

$candidates = @(
    (Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\pwsh.exe"),
    (Join-Path $env:ProgramFiles "PowerShell\7\pwsh.exe")
)

$command = Get-Command pwsh.exe -ErrorAction SilentlyContinue
if ($null -ne $command -and -not [string]::IsNullOrWhiteSpace([string]$command.Source)) {
    $candidates += [string]$command.Source
}

$tool = @($candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1)
if ($tool.Count -eq 0) {
    Write-Error "pwsh.exe not found. Install PowerShell 7 or repair the Codex pwsh shim."
    exit 1
}

& $tool[0] @args
exit $LASTEXITCODE
