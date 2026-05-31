param(
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE ".codex" })
)

$ErrorActionPreference = "Stop"

$fragmentDir = Join-Path $CodexHome "config.d"
$target = Join-Path $CodexHome "config.toml"
$required = @("00-policy.toml", "10-mcp.toml", "20-hooks.toml", "30-skills.toml")
$utf8NoBom = [Text.UTF8Encoding]::new($false)

foreach ($name in $required) {
    $path = Join-Path $fragmentDir $name
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Missing config fragment: $path"
    }
}

$content = New-Object System.Collections.Generic.List[string]
$content.Add("# Generated from config.d fragments. Do not manually diverge.")
$content.Add("# Generated UTC: $((Get-Date).ToUniversalTime().ToString("o"))")
$content.Add("")

foreach ($name in $required) {
    $path = Join-Path $fragmentDir $name
    $content.Add("# BEGIN $name")
    $content.Add([IO.File]::ReadAllText($path, $utf8NoBom))
    $content.Add("# END $name")
    $content.Add("")
}

$tmp = "$target.tmp"
[IO.File]::WriteAllText($tmp, ($content -join [Environment]::NewLine), $utf8NoBom)
Move-Item -Force -LiteralPath $tmp -Destination $target
Get-FileHash -Algorithm SHA256 -LiteralPath $target
