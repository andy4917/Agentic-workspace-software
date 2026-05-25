$ErrorActionPreference = "Stop"

function Resolve-CodexBundledTool {
    param([Parameter(Mandatory = $true)][string] $Name)

    $binRoot = Join-Path $env:LOCALAPPDATA "OpenAI\Codex\bin"
    $direct = Join-Path $binRoot ($Name + ".exe")
    if (Test-Path -LiteralPath $direct -PathType Leaf) {
        return $direct
    }

    if (Test-Path -LiteralPath $binRoot -PathType Container) {
        $match = Get-ChildItem -LiteralPath $binRoot -Directory -ErrorAction SilentlyContinue |
            ForEach-Object {
                $candidate = Join-Path $_.FullName ($Name + ".exe")
                if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                    Get-Item -LiteralPath $candidate
                }
            } |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($null -ne $match) {
            return $match.FullName
        }
    }

    return $null
}

$tool = Resolve-CodexBundledTool -Name "rg"
if ([string]::IsNullOrWhiteSpace($tool) -or -not (Test-Path -LiteralPath $tool -PathType Leaf)) {
    Write-Error "Codex bundled rg.exe not found. Restart or update Codex Desktop."
    exit 1
}

& $tool @args
exit $LASTEXITCODE
