$ErrorActionPreference = "Stop"

$tool = "C:\Program Files\Git\cmd\git.exe"
if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) {
    $command = Get-Command git.exe -ErrorAction SilentlyContinue
    if ($null -ne $command -and -not [string]::IsNullOrWhiteSpace([string]$command.Source)) {
        $tool = [string]$command.Source
    }
}

if ([string]::IsNullOrWhiteSpace($tool) -or -not (Test-Path -LiteralPath $tool -PathType Leaf)) {
    Write-Error "git.exe not found. Install Git for Windows or repair the Codex Git shim."
    exit 1
}

& $tool @args
exit $LASTEXITCODE
