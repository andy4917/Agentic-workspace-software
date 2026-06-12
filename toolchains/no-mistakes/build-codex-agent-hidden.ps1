param(
    [string]$OutputPath = (Join-Path $env:USERPROFILE ".codex\toolchains\no-mistakes\codex-agent-hidden.exe")
)

$ErrorActionPreference = "Stop"

$sourcePath = Join-Path $PSScriptRoot "CodexAgentHiddenLauncher.cs"
if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
    throw "Missing source file: $sourcePath"
}

$compilerCandidates = @(
    (Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319\csc.exe"),
    (Join-Path $env:WINDIR "Microsoft.NET\Framework\v4.0.30319\csc.exe")
)
$compiler = @($compilerCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1)
if ($compiler.Count -eq 0) {
    throw "Windows .NET Framework csc.exe was not found."
}

$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

& ($compiler[0]) /nologo /target:winexe /optimize+ /out:$OutputPath $sourcePath
if ($LASTEXITCODE -ne 0) {
    throw "csc.exe failed with exit code $LASTEXITCODE"
}

if (-not (Test-Path -LiteralPath $OutputPath -PathType Leaf)) {
    throw "Build completed without expected output: $OutputPath"
}

Get-Item -LiteralPath $OutputPath
