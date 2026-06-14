function Resolve-CodexBundledTool {
    param([Parameter(Mandatory = $true)][string]$Name)

    $binRoot = [IO.Path]::Combine($env:LOCALAPPDATA, "OpenAI\Codex\bin")
    $direct = [IO.Path]::Combine($binRoot, ($Name + ".exe"))
    if (Test-Path -LiteralPath $direct -PathType Leaf) {
        return $direct
    }

    if (Test-Path -LiteralPath $binRoot -PathType Container) {
        $match = Get-ChildItem -LiteralPath $binRoot -Directory -ErrorAction SilentlyContinue |
            ForEach-Object {
                $candidate = [IO.Path]::Combine($_.FullName, ($Name + ".exe"))
                if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                    Get-Item -LiteralPath $candidate
                }
            } |
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First 1
        if ($null -ne $match) {
            return $match.FullName
        }
    }

    return $null
}

function Resolve-CodexBundledExe {
    param([Parameter(Mandatory = $true)][string]$Name)

    return (Resolve-CodexBundledTool -Name $Name)
}
