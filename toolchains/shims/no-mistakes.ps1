$ErrorActionPreference = "Stop"

$env:NO_MISTAKES_TELEMETRY = "0"
$env:NO_MISTAKES_NO_UPDATE_CHECK = "1"

$NO_MISTAKES_EXE = Join-Path $env:LOCALAPPDATA "no-mistakes\no-mistakes.exe"
$CODEX_SHIM_DIR = Split-Path -Parent $PSCommandPath
$CODEX_HOME = if ([string]::IsNullOrWhiteSpace($env:CODEX_HOME)) { Join-Path $env:USERPROFILE ".codex" } else { $env:CODEX_HOME }
$NO_MISTAKES_HIDDEN_CODEX_AGENT = Join-Path $CODEX_HOME "toolchains\no-mistakes\codex-agent-hidden.exe"
$NO_MISTAKES_HIDDEN_CODEX_AGENT_BUILDER = Join-Path $CODEX_HOME "toolchains\no-mistakes\build-codex-agent-hidden.ps1"
$NM_ORIGINAL_PATH = [string]$env:PATH
$retainedPathEntries = New-Object System.Collections.Generic.List[string]

function Convert-ToComparablePathEntry {
    param([AllowNull()][string]$PathEntry)

    if ([string]::IsNullOrWhiteSpace($PathEntry)) {
        return ""
    }

    $expanded = [Environment]::ExpandEnvironmentVariables([string]$PathEntry)
    $expanded = $expanded.Trim().Trim('"')
    try {
        $expanded = [IO.Path]::GetFullPath($expanded)
    } catch {
    }
    return ($expanded -replace "/", "\").TrimEnd("\")
}

$normalizedShimDir = Convert-ToComparablePathEntry -PathEntry $CODEX_SHIM_DIR

function Resolve-CodexBundledTool {
    param([Parameter(Mandatory = $true)][string]$Name)

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
            Sort-Object LastWriteTimeUtc -Descending |
            Select-Object -First 1
        if ($null -ne $match) {
            return $match.FullName
        }
    }

    return $null
}

function Resolve-PwshExecutable {
    $candidates = @()
    $windowsAppsRoot = Join-Path $env:ProgramFiles "WindowsApps"
    if (Test-Path -LiteralPath $windowsAppsRoot -PathType Container) {
        $candidates += @(Get-ChildItem -LiteralPath $windowsAppsRoot -Directory -Filter "Microsoft.PowerShell_*__8wekyb3d8bbwe" -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending |
            ForEach-Object { Join-Path $_.FullName "pwsh.exe" })
    }
    $candidates += (Join-Path $env:ProgramFiles "PowerShell\7\pwsh.exe")
    $aliasStub = Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\pwsh.exe"
    $command = Get-Command pwsh.exe -CommandType Application -ErrorAction SilentlyContinue
    if ($null -ne $command -and -not [string]::IsNullOrWhiteSpace([string]$command.Source) -and [string]$command.Source -ne $aliasStub) {
        $candidates += [string]$command.Source
    }

    $selected = @($candidates | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) -and (Test-Path -LiteralPath ([string]$_) -PathType Leaf) } | Select-Object -First 1)
    if ($selected.Count -gt 0) {
        return [string]$selected[0]
    }
    return $null
}

function Add-PreferredPathDirectory {
    param([AllowNull()][string]$Directory)

    if ([string]::IsNullOrWhiteSpace($Directory) -or -not (Test-Path -LiteralPath $Directory -PathType Container)) {
        return
    }

    $normalizedDirectory = Convert-ToComparablePathEntry -PathEntry $Directory
    $hasDirectory = @($retainedPathEntries | Where-Object { (Convert-ToComparablePathEntry -PathEntry $_) -ieq $normalizedDirectory }).Count -gt 0
    if (-not $hasDirectory) {
        $retainedPathEntries.Insert(0, $Directory)
    }
}

function Test-RequiresCodexAgent {
    param([string[]]$Arguments)

    if (Test-NoMistakesHelpOrVersionInvocation -Arguments $Arguments) {
        return $false
    }

    if ($Arguments.Count -ge 2 -and [string]$Arguments[0] -ieq "axi" -and [string]$Arguments[1] -ieq "run") {
        return $true
    }
    if ($Arguments.Count -ge 2 -and [string]$Arguments[0] -ieq "axi" -and [string]$Arguments[1] -ieq "respond") {
        for ($index = 2; $index -lt $Arguments.Count; $index++) {
            $argument = [string]$Arguments[$index]
            if ($argument -ieq "--action" -and ($index + 1) -lt $Arguments.Count -and [string]$Arguments[$index + 1] -ieq "fix") {
                return $true
            }
            if ($argument -match "^(?i)--action=(.+)$" -and $Matches[1] -ieq "fix") {
                return $true
            }
        }
    }
    if ($Arguments.Count -ge 1 -and [string]$Arguments[0] -ieq "rerun") {
        return $true
    }
    return $false
}

function Test-NoMistakesHelpOrVersionInvocation {
    param([string[]]$Arguments)

    foreach ($argument in @($Arguments)) {
        if ([string]$argument -in @("help", "--help", "-h", "--version", "-v")) {
            return $true
        }
    }
    return $false
}

function Test-AdjacentArgumentPair {
    param(
        [string[]]$Arguments,
        [string]$Option,
        [string]$Value
    )

    for ($index = 0; $index -lt ($Arguments.Count - 1); $index++) {
        if ([string]$Arguments[$index] -ieq $Option -and [string]$Arguments[$index + 1] -eq $Value) {
            return $true
        }
    }
    return $false
}

function Convert-NoMistakesYamlScalar {
    param([AllowNull()][string]$Value)

    $trimmed = ([string]$Value).Trim()
    if ($trimmed.Length -ge 2) {
        if (($trimmed.StartsWith("'") -and $trimmed.EndsWith("'")) -or ($trimmed.StartsWith('"') -and $trimmed.EndsWith('"'))) {
            return $trimmed.Substring(1, $trimmed.Length - 2)
        }
    }
    return $trimmed
}

function Get-NoMistakesCodexAgentConfig {
    param([AllowNull()][string]$ConfigText)

    $agentPath = ""
    $agentArgs = New-Object System.Collections.Generic.List[string]
    $section = ""
    $insideCodexArgs = $false

    foreach ($line in (([string]$ConfigText) -split "\r?\n")) {
        if ($line -match '^\s*(#.*)?$') {
            continue
        }

        if ($line -match '^([A-Za-z0-9_-]+):\s*(?:#.*)?$') {
            $section = $Matches[1]
            $insideCodexArgs = $false
            continue
        }

        if ($section -eq "agent_path_override" -and $line -match '^\s{2}codex:\s*(.+?)\s*(?:#.*)?$') {
            $agentPath = Convert-NoMistakesYamlScalar -Value $Matches[1]
            continue
        }

        if ($section -eq "agent_args_override") {
            if ($line -match '^\s{2}([A-Za-z0-9_.:-]+):\s*(?:#.*)?$') {
                $insideCodexArgs = [string]$Matches[1] -ieq "codex"
                continue
            }
            if ($insideCodexArgs -and $line -match '^\s{4}-\s*(.+?)\s*(?:#.*)?$') {
                $agentArgs.Add((Convert-NoMistakesYamlScalar -Value $Matches[1])) | Out-Null
            }
        }
    }

    [pscustomobject]@{
        CodexPath = $agentPath
        CodexArgs = $agentArgs.ToArray()
    }
}

function Assert-HiddenCodexAgentReady {
    if (-not (Test-Path -LiteralPath $NO_MISTAKES_HIDDEN_CODEX_AGENT -PathType Leaf)) {
        if (Test-Path -LiteralPath $NO_MISTAKES_HIDDEN_CODEX_AGENT_BUILDER -PathType Leaf) {
            & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $NO_MISTAKES_HIDDEN_CODEX_AGENT_BUILDER -OutputPath $NO_MISTAKES_HIDDEN_CODEX_AGENT | Out-Null
        }
    }

    if (-not (Test-Path -LiteralPath $NO_MISTAKES_HIDDEN_CODEX_AGENT -PathType Leaf)) {
        Write-Error "no-mistakes hidden Codex agent launcher is missing at $NO_MISTAKES_HIDDEN_CODEX_AGENT"
        exit 1
    }

    $configPath = Join-Path $env:USERPROFILE ".no-mistakes\config.yaml"
    if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
        Write-Error "no-mistakes config.yaml is missing; expected agent_path_override.codex to point at $NO_MISTAKES_HIDDEN_CODEX_AGENT"
        exit 1
    }

    $configText = Get-Content -LiteralPath $configPath -Raw
    $codexAgentConfig = Get-NoMistakesCodexAgentConfig -ConfigText $configText
    $configuredAgentPath = Convert-ToComparablePathEntry -PathEntry $codexAgentConfig.CodexPath
    $expectedAgentPath = Convert-ToComparablePathEntry -PathEntry $NO_MISTAKES_HIDDEN_CODEX_AGENT
    if ($configuredAgentPath -ine $expectedAgentPath) {
        Write-Error "no-mistakes config.yaml must set agent_path_override.codex to $NO_MISTAKES_HIDDEN_CODEX_AGENT before running agent-backed gates."
        exit 1
    }

    $codexAgentArgs = @($codexAgentConfig.CodexArgs)
    if (-not (Test-AdjacentArgumentPair -Arguments $codexAgentArgs -Option "-c" -Value 'model_reasoning_effort="medium"')) {
        Write-Error 'no-mistakes config.yaml must set agent_args_override.codex to include -c model_reasoning_effort="medium" before running agent-backed gates.'
        exit 1
    }

    $missingAgentArgs = @()
    if (-not (Test-AdjacentArgumentPair -Arguments $codexAgentArgs -Option "--sandbox" -Value "danger-full-access")) {
        $missingAgentArgs += "--sandbox danger-full-access"
    }
    if (-not (Test-AdjacentArgumentPair -Arguments $codexAgentArgs -Option "--disable" -Value "plugins")) {
        $missingAgentArgs += "--disable plugins"
    }
    if ($codexAgentArgs -notcontains "--skip-git-repo-check") {
        $missingAgentArgs += "--skip-git-repo-check"
    }
    if ($missingAgentArgs.Count -gt 0) {
        Write-Error ("no-mistakes config.yaml must set agent_args_override.codex to include required Codex agent args: " + ($missingAgentArgs -join ", "))
        exit 1
    }
}

foreach ($entry in ($NM_ORIGINAL_PATH -split ";")) {
    if ([string]::IsNullOrWhiteSpace($entry)) {
        continue
    }
    $NM_PATH_ENTRY_ORIGINAL = $entry
    $NM_PATH_ENTRY_NORMALIZED = Convert-ToComparablePathEntry -PathEntry $NM_PATH_ENTRY_ORIGINAL
    if ($NM_PATH_ENTRY_NORMALIZED -ieq $normalizedShimDir) {
        continue
    }
    $retainedPathEntries.Add($NM_PATH_ENTRY_ORIGINAL) | Out-Null
}

$codexAgentTool = Resolve-CodexBundledTool -Name "codex"
if (-not [string]::IsNullOrWhiteSpace($codexAgentTool)) {
    $codexAgentDir = Split-Path -Parent $codexAgentTool
    Add-PreferredPathDirectory -Directory $codexAgentDir
}

$pwshAgentTool = Resolve-PwshExecutable
if (-not [string]::IsNullOrWhiteSpace($pwshAgentTool)) {
    Add-PreferredPathDirectory -Directory (Split-Path -Parent $pwshAgentTool)
}

$env:PATH = ($retainedPathEntries.ToArray() -join ";")

if (-not (Test-Path -LiteralPath $NO_MISTAKES_EXE -PathType Leaf)) {
    Write-Error "no-mistakes.exe not found at $NO_MISTAKES_EXE. Install the official kunchenguid/no-mistakes release first."
    exit 1
}

if (Test-RequiresCodexAgent -Arguments $args) {
    Assert-HiddenCodexAgentReady
}

& $NO_MISTAKES_EXE @args
exit $LASTEXITCODE
