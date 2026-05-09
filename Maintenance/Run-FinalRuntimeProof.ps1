param(
  [string]$Root = ''
)

$ErrorActionPreference = 'Stop'
$Utf8NoBom = New-Object System.Text.UTF8Encoding -ArgumentList $false
[Console]::OutputEncoding = $Utf8NoBom
$OutputEncoding = $Utf8NoBom

if ([string]::IsNullOrWhiteSpace($Root)) {
  $Root = Split-Path -Parent $PSScriptRoot
}

$writer = Join-Path $Root 'Maintenance\Write-FinalRuntimeProofReport.ps1'
if (-not (Test-Path -LiteralPath $writer -PathType Leaf)) {
  throw "Missing final runtime proof writer: $writer"
}

& powershell -NoProfile -ExecutionPolicy Bypass -File $writer -Root $Root
exit $LASTEXITCODE
