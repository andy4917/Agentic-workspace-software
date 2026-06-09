param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Args)
$ErrorActionPreference = 'Stop'
$Script = Join-Path $PSScriptRoot 'codex_agent_harness.py'
$DefaultRoot = Join-Path $env:USERPROFILE 'Documents\Codex'
$RootArgs = @()
if (Test-Path -LiteralPath $DefaultRoot -PathType Container) {
    $RootArgs = @('--root', $DefaultRoot)
}
python $Script @RootArgs repair @Args
exit $LASTEXITCODE
