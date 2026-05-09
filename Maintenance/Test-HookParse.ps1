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

$hookPath = Join-Path $Root 'Settings\Dev_Codex_HOOKS\codex-ssot-hook.ps1'
if (-not (Test-Path -LiteralPath $hookPath -PathType Leaf)) {
  throw "Missing hook runner: $hookPath"
}

$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($hookPath, [ref]$tokens, [ref]$errors)
$functionCount = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)).Count

$result = [ordered]@{
  schema_version = 'hook_parse_check.v1'
  hook_path = $hookPath
  parsed = ($errors.Count -eq 0)
  parse_error_count = $errors.Count
  token_count = $tokens.Count
  function_count = $functionCount
}

if ($errors.Count -gt 0) {
  $result.errors = @($errors | ForEach-Object {
    [ordered]@{
      message = $_.Message
      line = $_.Extent.StartLineNumber
      column = $_.Extent.StartColumnNumber
    }
  })
}

$result | ConvertTo-Json -Depth 5
if ($errors.Count -gt 0) { exit 1 }
