param(
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE ".codex" }),
    [switch]$Json,
    [switch]$ReportOnly
)

$ErrorActionPreference = "Stop"

if ($PSVersionTable.PSEdition -ne "Core" -and -not $env:CODEX_AUTOMATION_HEALTH_PWSH_REEXEC -and -not [string]::IsNullOrWhiteSpace($PSCommandPath)) {
    $pwshShim = [IO.Path]::Combine($CodexHome, "toolchains\shims\pwsh.cmd")
    if (Test-Path -LiteralPath $pwshShim -PathType Leaf) {
        $env:CODEX_AUTOMATION_HEALTH_PWSH_REEXEC = "1"
        $arguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $PSCommandPath, "-CodexHome", $CodexHome)
        if ($Json) { $arguments += "-Json" }
        if ($ReportOnly) { $arguments += "-ReportOnly" }
        & $pwshShim @arguments
        exit $LASTEXITCODE
    }
}

function Join-PathStrict {
    param(
        [Parameter(Mandatory = $true)][string]$Base,
        [Parameter(Mandatory = $true)][string]$Child
    )
    return [IO.Path]::Combine($Base, $Child)
}

function Resolve-CodexBundledExe {
    param([Parameter(Mandatory = $true)][string]$Name)

    $binRoot = Join-PathStrict $env:LOCALAPPDATA "OpenAI\Codex\bin"
    $direct = Join-PathStrict $binRoot ($Name + ".exe")
    if (Test-Path -LiteralPath $direct -PathType Leaf) {
        return $direct
    }
    if (Test-Path -LiteralPath $binRoot -PathType Container) {
        $candidate = @(Get-ChildItem -LiteralPath $binRoot -Directory -ErrorAction SilentlyContinue |
            Sort-Object LastWriteTimeUtc -Descending |
            ForEach-Object {
                $path = Join-PathStrict $_.FullName ($Name + ".exe")
                if (Test-Path -LiteralPath $path -PathType Leaf) { $path }
            } |
            Select-Object -First 1)
        if ($candidate.Count -gt 0) {
            return [string]$candidate[0]
        }
    }
    return $null
}

function Add-Check {
    param(
        [System.Collections.Generic.List[object]]$Checks,
        [string]$Name,
        [string]$Status,
        [object]$Details
    )
    $Checks.Add([ordered]@{ name = $Name; status = $Status; details = $Details }) | Out-Null
}

function Limit-Text {
    param(
        [AllowNull()][string]$Text,
        [int]$MaxLength = 1200
    )

    if ([string]::IsNullOrEmpty($Text) -or $Text.Length -le $MaxLength) {
        return $Text
    }
    return $Text.Substring(0, $MaxLength) + "...<truncated>"
}

function Get-PluginRoot {
    param(
        [string]$CacheRoot,
        [string[]]$RequiredRelativePaths = @()
    )

    $latest = Join-PathStrict $CacheRoot "latest"
    if (Test-Path -LiteralPath $latest -PathType Container) {
        $missingFromLatest = @($RequiredRelativePaths | Where-Object {
                -not (Test-Path -LiteralPath (Join-PathStrict $latest $_))
            })
        if ($missingFromLatest.Count -eq 0) {
            return (Get-Item -LiteralPath $latest).FullName
        }
    }

    $versions = @()
    if (Test-Path -LiteralPath $CacheRoot -PathType Container) {
        $versions = @(Get-ChildItem -LiteralPath $CacheRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne "latest" } |
            Where-Object {
                $root = $_.FullName
                @($RequiredRelativePaths | Where-Object {
                        -not (Test-Path -LiteralPath (Join-PathStrict $root $_))
                    }).Count -eq 0
            } |
            Sort-Object LastWriteTimeUtc -Descending)
    }

    if ($versions.Count -gt 0) {
        return $versions[0].FullName
    }
    return $null
}

function Invoke-NodeSyntaxCheck {
    param(
        [string]$Node,
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Node) -or -not (Test-Path -LiteralPath $Node -PathType Leaf)) {
        return [ordered]@{ ok = $false; exit_code = $null; output_excerpt = "node shim missing" }
    }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return [ordered]@{ ok = $false; exit_code = $null; output_excerpt = "target missing" }
    }

    $output = @(& $Node --check $Path 2>&1)
    $text = (($output | Out-String).Trim())
    return [ordered]@{
        ok = ($LASTEXITCODE -eq 0)
        exit_code = $LASTEXITCODE
        output_excerpt = Limit-Text -Text $text
    }
}

function Invoke-NodeJsonScript {
    param(
        [string]$Node,
        [string]$Script,
        [string[]]$Arguments = @("--json")
    )

    if (-not (Test-Path -LiteralPath $Script -PathType Leaf)) {
        return [ordered]@{ ok = $false; exit_code = $null; output_excerpt = "script missing" }
    }
    $output = @(& $Node $Script @Arguments 2>&1)
    $text = (($output | Out-String).Trim())
    return [ordered]@{
        ok = ($LASTEXITCODE -eq 0)
        exit_code = $LASTEXITCODE
        output_excerpt = Limit-Text -Text $text
    }
}

function ConvertFrom-JsonOrNull {
    param([AllowNull()][string]$Text)

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $null
    }
    try {
        return ($Text | ConvertFrom-Json)
    } catch {
        return $null
    }
}

function ConvertTo-ComparablePath {
    param([AllowNull()][string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return ""
    }
    try {
        return [IO.Path]::GetFullPath($Path).TrimEnd("\").ToLowerInvariant()
    } catch {
        return ([string]$Path).TrimEnd("\").ToLowerInvariant()
    }
}

function Test-NativeHostRegistryCrossCheck {
    param([object]$Diagnostic)

    $result = [ordered]@{
        checked = $false
        ok = $false
        registry_key = $null
        registry_manifest_path = $null
        expected_manifest_path = $null
        error = $null
    }

    if ($null -eq $Diagnostic -or $null -eq $Diagnostic.registryKey -or $null -eq $Diagnostic.manifestPath) {
        $result.error = "diagnostic missing registryKey or manifestPath"
        return $result
    }

    $registryKey = [string]$Diagnostic.registryKey
    $result.registry_key = $registryKey
    $result.expected_manifest_path = [string]$Diagnostic.manifestPath
    if ($registryKey -notmatch "^HKCU\\(.+)$") {
        $result.error = "unsupported registry root"
        return $result
    }

    $result.checked = $true
    $subKey = $Matches[1]
    try {
        $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($subKey)
        if ($null -eq $key) {
            $result.error = "registry key missing"
            return $result
        }
        try {
            $value = [string]$key.GetValue("")
        } finally {
            $key.Dispose()
        }
        $result.registry_manifest_path = $value
        $result.ok = ((ConvertTo-ComparablePath -Path $value) -eq (ConvertTo-ComparablePath -Path ([string]$Diagnostic.manifestPath)))
        if (-not $result.ok) {
            $result.error = "registry default value does not match manifestPath"
        }
    } catch {
        $result.error = $_.Exception.Message
    }

    return $result
}

function Invoke-ChromeNativeHostManifestDiagnostic {
    param(
        [string]$Node,
        [string]$Script
    )

    if (-not (Test-Path -LiteralPath $Script -PathType Leaf)) {
        return [ordered]@{ ok = $false; exit_code = $null; output_excerpt = "script missing" }
    }

    $attempts = New-Object System.Collections.Generic.List[object]
    $lastText = ""
    $lastExitCode = $null
    $lastParsed = $null
    $lastCrossCheck = $null
    $lastFailureWasRegistryMissing = $false
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        $output = @(& $Node $Script --json 2>&1)
        $lastExitCode = $LASTEXITCODE
        $lastText = (($output | Out-String).Trim())
        $lastParsed = ConvertFrom-JsonOrNull -Text $lastText
        $problem = if ($null -ne $lastParsed -and $null -ne $lastParsed.problem) { [string]$lastParsed.problem } else { "" }
        $parsedCorrect = ($null -ne $lastParsed -and [bool]$lastParsed.correct -and [string]::IsNullOrWhiteSpace($problem))
        $attemptOk = ($lastExitCode -eq 0 -or $parsedCorrect)
        $lastFailureWasRegistryMissing = ($problem -match "Windows native host registry key does not exist")
        $attempts.Add([ordered]@{
            attempt = $attempt
            ok = $attemptOk
            exit_code = $lastExitCode
            output_excerpt = Limit-Text -Text $lastText
        }) | Out-Null

        if ($attemptOk) {
            return [ordered]@{
                ok = $true
                exit_code = $lastExitCode
                output_excerpt = Limit-Text -Text $lastText
                attempts = @($attempts.ToArray())
                accepted_by_registry_cross_check = $false
                registry_cross_check = $null
            }
        }

        if (-not $lastFailureWasRegistryMissing) {
            break
        }
        $lastCrossCheck = Test-NativeHostRegistryCrossCheck -Diagnostic $lastParsed
        if (-not [bool]$lastCrossCheck.ok) {
            break
        }
        Start-Sleep -Milliseconds 250
    }

    $acceptedByCrossCheck = ($lastFailureWasRegistryMissing -and $null -ne $lastCrossCheck -and [bool]$lastCrossCheck.ok)
    return [ordered]@{
        ok = $acceptedByCrossCheck
        exit_code = $lastExitCode
        output_excerpt = Limit-Text -Text $lastText
        attempts = @($attempts.ToArray())
        accepted_by_registry_cross_check = $acceptedByCrossCheck
        registry_cross_check = $lastCrossCheck
        note = $(if ($acceptedByCrossCheck) { "Plugin diagnostic reported a missing Windows registry key, but direct registry cross-check found the expected manifest path after retries." } else { $null })
    }
}

function Invoke-NodeReplStdioProbe {
    param(
        [string]$NodeRepl,
        [string]$CodexHome,
        [string]$Node,
        [string]$Codex
    )

    if (-not (Test-Path -LiteralPath $NodeRepl -PathType Leaf)) {
        return [ordered]@{ ok = $false; exit_code = $null; output_excerpt = "node_repl shim missing" }
    }
    $nodeReplExe = Resolve-CodexBundledExe -Name "node_repl"
    if ([string]::IsNullOrWhiteSpace($nodeReplExe)) {
        return [ordered]@{ ok = $false; exit_code = $null; output_excerpt = "node_repl bundled exe missing" }
    }
    $nodeExe = Resolve-CodexBundledExe -Name "node"
    if ([string]::IsNullOrWhiteSpace($nodeExe)) {
        $nodeExe = $Node
    }
    $codexExe = Resolve-CodexBundledExe -Name "codex"
    if ([string]::IsNullOrWhiteSpace($codexExe)) {
        $codexExe = $Codex
    }

    $inputLines = @(
        '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"automation-plugin-health","version":"1"}}}',
        '{"jsonrpc":"2.0","method":"notifications/initialized","params":{}}',
        '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"js","arguments":{"code":"nodeRepl.write(JSON.stringify({ok:true,cwd:nodeRepl.cwd}))","timeout_ms":10000,"title":"stdio js probe"}}}'
    )
    $process = New-Object System.Diagnostics.Process
    $process.StartInfo.FileName = $nodeReplExe
    $process.StartInfo.UseShellExecute = $false
    $process.StartInfo.RedirectStandardInput = $true
    $process.StartInfo.RedirectStandardOutput = $true
    $process.StartInfo.RedirectStandardError = $true
    $process.StartInfo.CreateNoWindow = $true
    if ($null -ne $process.StartInfo.ArgumentList) {
        $process.StartInfo.ArgumentList.Add("--disable-sandbox")
    } else {
        $process.StartInfo.Arguments = "--disable-sandbox"
    }
    $process.StartInfo.Environment["CODEX_HOME"] = $CodexHome
    $process.StartInfo.Environment["NODE_REPL_NODE_PATH"] = $nodeExe
    $process.StartInfo.Environment["CODEX_CLI_PATH"] = $codexExe
    $process.StartInfo.Environment["NODE_REPL_TRUSTED_CODE_PATHS"] = $CodexHome

    $timedOut = $false
    $exitCode = $null
    $stdout = ""
    $stderr = ""
    try {
        $null = $process.Start()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $stdinText = (($inputLines | ForEach-Object { [string]$_ }) -join "`n") + "`n"
        $stdinBytes = [Text.Encoding]::UTF8.GetBytes($stdinText)
        $process.StandardInput.BaseStream.Write($stdinBytes, 0, $stdinBytes.Length)
        $process.StandardInput.BaseStream.Flush()
        $process.StandardInput.Close()
        if (-not $process.WaitForExit(20000)) {
            $timedOut = $true
            try { $process.Kill() } catch {}
            try { $null = $process.WaitForExit(5000) } catch {}
        }
        $exitCode = if ($timedOut) { -1 } else { $process.ExitCode }
        try { $stdout = $stdoutTask.GetAwaiter().GetResult() } catch { $stdout = "" }
        try { $stderr = $stderrTask.GetAwaiter().GetResult() } catch { $stderr = "" }
    } finally {
        $process.Dispose()
    }

    $text = (($stdout, $stderr) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "`n"
    $text = $text.Trim()
    $serverInitialized = ($exitCode -eq 0 -and $text -match '"serverInfo"')
    $jsReturnedOk = ($text -match '"isError"\s*:\s*false' -and $text -match '\\"ok\\"\s*:\s*true')
    return [ordered]@{
        ok = ($serverInitialized -and $jsReturnedOk)
        exit_code = $exitCode
        timed_out = $timedOut
        executable = $nodeReplExe
        server_initialized = $serverInitialized
        js_returned_ok = $jsReturnedOk
        output_excerpt = Limit-Text -Text $text
    }
}

$checks = [System.Collections.Generic.List[object]]::new()
$pluginCache = Join-PathStrict $CodexHome "plugins\cache\openai-bundled"
$shimRoot = Join-PathStrict $CodexHome "toolchains\shims"
$node = Join-PathStrict $shimRoot "node.cmd"
$nodeRepl = Join-PathStrict $shimRoot "node_repl.cmd"
$codex = Join-PathStrict $shimRoot "codex.cmd"
$chromeRepairScript = Join-PathStrict $PSScriptRoot "repair-chrome-plugin-runtime.ps1"

$nodeReplProbe = Invoke-NodeReplStdioProbe -NodeRepl $nodeRepl -CodexHome $CodexHome -Node $node -Codex $codex
Add-Check $checks "node_repl_stdio_js_ready" ($(if ($nodeReplProbe.ok) { "pass" } else { "fail" })) @{
    shim = $nodeRepl
    probe = $nodeReplProbe
    note = "This proves the bundled execution primitive can initialize over MCP stdio and run JavaScript. Live tool-surface transport remains owned by the active Codex session."
}

$browserRoot = Get-PluginRoot -CacheRoot (Join-PathStrict $pluginCache "browser") -RequiredRelativePaths @(
    ".codex-plugin\plugin.json",
    "scripts\browser-client.mjs",
    "skills\control-in-app-browser\SKILL.md"
)
$browserClient = if ($browserRoot) { Join-PathStrict $browserRoot "scripts\browser-client.mjs" } else { "" }
$browserSyntax = Invoke-NodeSyntaxCheck -Node $node -Path $browserClient
Add-Check $checks "browser_plugin_static_health" ($(if ($browserRoot -and $browserSyntax.ok) { "pass" } else { "fail" })) @{
    root = $browserRoot
    browser_client = $browserClient
    browser_client_syntax = $browserSyntax
    note = "Static health covers the in-app Browser plugin files without opening or controlling a browser."
}

$chromeRoot = Get-PluginRoot -CacheRoot (Join-PathStrict $pluginCache "chrome") -RequiredRelativePaths @(
    ".codex-plugin\plugin.json",
    "scripts\browser-client.mjs",
    "scripts\chrome-is-running.js",
    "scripts\installed-browsers.js",
    "scripts\check-extension-installed.js",
    "scripts\check-native-host-manifest.js",
    "scripts\extension-id.json",
    "extension-host\windows\x64\extension-host.exe"
)
$chromeClient = if ($chromeRoot) { Join-PathStrict $chromeRoot "scripts\browser-client.mjs" } else { "" }
$chromeSyntax = Invoke-NodeSyntaxCheck -Node $node -Path $chromeClient
$chromeDiagnostics = @{}
if ($chromeRoot) {
    foreach ($scriptName in @(
            "chrome-is-running.js",
            "installed-browsers.js",
            "check-extension-installed.js",
            "check-native-host-manifest.js"
        )) {
        $scriptPath = Join-PathStrict $chromeRoot ("scripts\" + $scriptName)
        if ($scriptName -eq "check-native-host-manifest.js") {
            $chromeDiagnostics[$scriptName] = Invoke-ChromeNativeHostManifestDiagnostic -Node $node -Script $scriptPath
        } else {
            $chromeDiagnostics[$scriptName] = Invoke-NodeJsonScript -Node $node -Script $scriptPath
        }
    }
}
$chromeRuntime = $null
if (Test-Path -LiteralPath $chromeRepairScript -PathType Leaf) {
    try {
        $chromeRuntime = (& $chromeRepairScript -Mode status -CodexHome $CodexHome -Json 2>&1 | Out-String) | ConvertFrom-Json
    } catch {
        $chromeRuntime = [pscustomobject]@{ status = [pscustomobject]@{ ok = $false; problems = @($_.Exception.Message) } }
    }
}
$chromeDiagnosticsOk = ($chromeDiagnostics.Count -eq 4 -and @($chromeDiagnostics.Values | Where-Object { -not $_.ok }).Count -eq 0)
Add-Check $checks "chrome_plugin_runtime_health" ($(if ($chromeRoot -and $chromeSyntax.ok -and $chromeDiagnosticsOk -and [bool]$chromeRuntime.status.ok) { "pass" } else { "fail" })) @{
    root = $chromeRoot
    browser_client_syntax = $chromeSyntax
    diagnostics = $chromeDiagnostics
    runtime_status = $chromeRuntime.status
    note = "Chrome health uses the plugin's official read-only diagnostics plus scaffold runtime repair status."
}

$computerRoot = Get-PluginRoot -CacheRoot (Join-PathStrict $pluginCache "computer-use") -RequiredRelativePaths @(
    ".codex-plugin\plugin.json",
    "scripts\computer-use-client.mjs",
    "skills\computer-use\SKILL.md",
    "node_modules\@oai\sky\bin\windows\codex-computer-use.exe"
)
$computerClient = if ($computerRoot) { Join-PathStrict $computerRoot "scripts\computer-use-client.mjs" } else { "" }
$computerHelper = if ($computerRoot) { Join-PathStrict $computerRoot "node_modules\@oai\sky\bin\windows\codex-computer-use.exe" } else { "" }
$computerSyntax = Invoke-NodeSyntaxCheck -Node $node -Path $computerClient
Add-Check $checks "computer_use_plugin_static_health" ($(if ($computerRoot -and $computerSyntax.ok -and (Test-Path -LiteralPath $computerHelper -PathType Leaf)) { "pass" } else { "fail" })) @{
    root = $computerRoot
    computer_use_client = $computerClient
    helper = $computerHelper
    helper_exists = (Test-Path -LiteralPath $computerHelper -PathType Leaf)
    client_syntax = $computerSyntax
    note = "Static health avoids launching or controlling Windows apps; live app listing requires the active node_repl MCP transport."
}

$failures = @($checks | Where-Object { $_.status -eq "fail" })
$result = [ordered]@{
    generated_utc = (Get-Date).ToUniversalTime().ToString("o")
    overall_status = if ($failures.Count -eq 0) { "pass" } else { "fail" }
    fail_count = $failures.Count
    summary = [ordered]@{
        check_count = $checks.Count
        fail_count = $failures.Count
        coverage = [ordered]@{
            node_repl = "stdio MCP initialize plus JavaScript tool call"
            browser = "static plugin root, skill, and browser-client syntax"
            chrome = "static syntax, read-only plugin diagnostics, native-host manifest, and scaffold runtime status"
            computer_use = "static plugin root, skill, client syntax, and helper executable presence"
        }
    }
    checks = @($checks)
}

if ($Json) {
    $result | ConvertTo-Json -Depth 16
} else {
    "overall_status={0}" -f $result.overall_status
    "fail_count={0}" -f $failures.Count
    foreach ($failure in $failures) {
        "failure={0}" -f $failure.name
    }
}

if ($failures.Count -gt 0 -and -not $ReportOnly) {
    exit 1
}
