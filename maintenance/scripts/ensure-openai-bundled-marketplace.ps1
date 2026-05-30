param(
    [ValidateSet("status", "repair")]
    [string]$Mode = "status",
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE ".codex" }),
    [switch]$Json
)

$ErrorActionPreference = "Stop"

function Join-PathStrict {
    param(
        [Parameter(Mandatory = $true)][string]$Base,
        [Parameter(Mandatory = $true)][string]$Child
    )
    return [IO.Path]::Combine($Base, $Child)
}

function Get-CurrentBundledMarketplace {
    $windowsApps = Join-PathStrict $env:ProgramFiles "WindowsApps"
    if (-not (Test-Path -LiteralPath $windowsApps -PathType Container)) {
        return $null
    }

    $candidates = @(Get-ChildItem -LiteralPath $windowsApps -Directory -Filter "OpenAI.Codex_*" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending |
        ForEach-Object {
            $marketplace = Join-PathStrict $_.FullName "app\resources\plugins\openai-bundled"
            $chrome = Join-PathStrict $marketplace "plugins\chrome"
            $browser = Join-PathStrict $marketplace "plugins\browser"
            if ((Test-Path -LiteralPath $chrome -PathType Container) -and
                (Test-Path -LiteralPath $browser -PathType Container)) {
                [pscustomobject]@{
                    app_root = $_.FullName
                    marketplace = $marketplace
                    last_write_utc = $_.LastWriteTimeUtc.ToString("o")
                }
            }
        })

    return @($candidates | Select-Object -First 1)[0]
}

function Get-LinkTarget {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $item = Get-Item -LiteralPath $Path -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        $target = @($item.Target | Select-Object -First 1)[0]
        if (-not [string]::IsNullOrWhiteSpace($target)) {
            return [IO.Path]::GetFullPath($target)
        }
    }
    return [IO.Path]::GetFullPath($item.FullName)
}

function Set-Junction {
    param(
        [string]$Path,
        [string]$Target
    )

    $targetFull = [IO.Path]::GetFullPath($Target)
    $currentTarget = Get-LinkTarget -Path $Path
    if ($null -ne $currentTarget -and $currentTarget.TrimEnd("\") -ieq $targetFull.TrimEnd("\")) {
        return "marketplace-link-already-correct"
    }

    if (Test-Path -LiteralPath $Path) {
        $item = Get-Item -LiteralPath $Path -Force
        if (-not ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Refusing to replace non-reparse marketplace source: $Path"
        }
        Remove-Item -LiteralPath $Path -Force
    }

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
    New-Item -ItemType Junction -Path $Path -Target $targetFull | Out-Null
    return "marketplace-link-updated"
}

$stablePath = Join-PathStrict $CodexHome "plugins\marketplaces\openai-bundled"
$current = Get-CurrentBundledMarketplace
$actions = New-Object System.Collections.Generic.List[string]

if ($Mode -eq "repair") {
    if ($null -eq $current) {
        throw "Current OpenAI Codex bundled marketplace was not found under WindowsApps."
    }
    $actions.Add((Set-Junction -Path $stablePath -Target $current.marketplace)) | Out-Null
}

$linkTarget = Get-LinkTarget -Path $stablePath
$ok = ($null -ne $current -and $null -ne $linkTarget -and
    $linkTarget.TrimEnd("\") -ieq ([IO.Path]::GetFullPath($current.marketplace)).TrimEnd("\"))

$result = [ordered]@{
    generated_utc = (Get-Date).ToUniversalTime().ToString("o")
    mode = $Mode
    ok = $ok
    stable_path = $stablePath
    current_marketplace = $current
    link_target = $linkTarget
    actions = @($actions.ToArray())
}

if ($Json) {
    $result | ConvertTo-Json -Depth 12
} else {
    "ok={0}" -f $ok
    "stable_path=$stablePath"
    "link_target=$linkTarget"
    if ($null -ne $current) { "current_marketplace=$($current.marketplace)" }
    foreach ($action in $actions) { "action=$action" }
}

if (-not $ok) {
    exit 1
}
