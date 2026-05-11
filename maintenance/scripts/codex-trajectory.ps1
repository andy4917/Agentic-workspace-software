param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Args)
$ErrorActionPreference = 'Stop'
$Script = Join-Path $PSScriptRoot 'codex_agent_harness.py'
python $Script trajectory @Args
