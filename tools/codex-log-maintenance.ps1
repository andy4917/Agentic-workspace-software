param(
    [Parameter(Position = 0)]
    [string]$Command = "help",

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

$ErrorActionPreference = "Stop"

function Get-CodexHomePath {
    if (-not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
        return $env:CODEX_HOME
    }
    return (Join-Path ([Environment]::GetFolderPath("UserProfile")) ".codex")
}

$codexHome = Get-CodexHomePath
$helper = Join-Path $codexHome "tools\codex-log-db.py"
if (-not (Test-Path -LiteralPath $helper)) {
    throw "Missing helper: $helper"
}

$python = Join-Path $codexHome "toolchains\shims\python.cmd"
if (-not (Test-Path -LiteralPath $python)) {
    $python = "python"
}

if ($Command -eq "help") {
    & $python $helper --help
    exit $LASTEXITCODE
}

& $python $helper $Command @RemainingArgs
exit $LASTEXITCODE
