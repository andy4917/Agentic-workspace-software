$ErrorActionPreference = "Stop"

$tool = "C:\Program Files\GitHub CLI\gh.exe"
if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) {
    $command = Get-Command gh.exe -ErrorAction SilentlyContinue
    if ($null -ne $command -and -not [string]::IsNullOrWhiteSpace([string]$command.Source)) {
        $tool = [string]$command.Source
    }
}

if ([string]::IsNullOrWhiteSpace($tool) -or -not (Test-Path -LiteralPath $tool -PathType Leaf)) {
    Write-Error "gh.exe not found. Install GitHub CLI or repair the Codex GitHub shim."
    exit 1
}

& $tool @args
exit $LASTEXITCODE
