[CmdletBinding()]
param(
  [ValidateSet('ci', 'quality', 'release')]
  [string]$Gate = 'ci'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$bench = Join-Path $PSScriptRoot 'Invoke-PatchBench.ps1'
& $bench -Gate $Gate
exit $LASTEXITCODE
