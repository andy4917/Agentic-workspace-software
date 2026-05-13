param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Args)

$ErrorActionPreference = "Stop"

$tool = Join-Path $env:LOCALAPPDATA "OpenAI\Codex\bin\rg.exe"
if (-not (Test-Path -LiteralPath $tool)) {
    Write-Error "Codex bundled rg.exe not found. Restart or update Codex Desktop."
    exit 1
}

& $tool @Args
exit $LASTEXITCODE
