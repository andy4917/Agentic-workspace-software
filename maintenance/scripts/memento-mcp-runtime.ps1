[CmdletBinding()]
param(
    [ValidateSet("status", "start", "stop", "restart", "repair", "verify")]
    [string] $Action = "status",
    [switch] $WriteProbe
)

$ErrorActionPreference = "Stop"

function Join-PathStrict {
    param(
        [Parameter(Mandatory = $true)][string] $Base,
        [Parameter(Mandatory = $true)][string] $Child
    )

    return [System.IO.Path]::Combine($Base, $Child)
}

function Resolve-CodexHome {
    if (-not [string]::IsNullOrWhiteSpace($env:CODEX_HOME)) {
        return $env:CODEX_HOME
    }

    return Join-PathStrict $env:USERPROFILE ".codex"
}

$CodexHome = Resolve-CodexHome
$SourceRoot = Join-PathStrict $CodexHome "tools\memento-mcp"
$StateRoot = Join-PathStrict $CodexHome "state\memento-mcp"
$PgData = Join-PathStrict $StateRoot "pgdata"
$LogRoot = Join-PathStrict $StateRoot "logs"
$ServerPidPath = Join-PathStrict $StateRoot "memento-server.pid"
$ServerOutLog = Join-PathStrict $LogRoot "memento-server.out.log"
$ServerErrLog = Join-PathStrict $LogRoot "memento-server.err.log"
$EnvPath = Join-PathStrict $SourceRoot ".env"

function Resolve-CodexBundledTool {
    param([Parameter(Mandatory = $true)][string] $Name)

    $direct = Join-PathStrict $env:LOCALAPPDATA ("OpenAI\Codex\bin\" + $Name + ".exe")
    if (Test-Path -LiteralPath $direct -PathType Leaf) {
        return $direct
    }

    $binRoot = Join-PathStrict $env:LOCALAPPDATA "OpenAI\Codex\bin"
    if (Test-Path -LiteralPath $binRoot -PathType Container) {
        $matches = @(Get-ChildItem -LiteralPath $binRoot -Directory -ErrorAction SilentlyContinue |
            ForEach-Object {
                $candidate = Join-PathStrict $_.FullName ($Name + ".exe")
                if (Test-Path -LiteralPath $candidate -PathType Leaf) {
                    Get-Item -LiteralPath $candidate
                }
            } |
            Sort-Object LastWriteTime -Descending)
        if ($matches.Count -gt 0) {
            return $matches[0].FullName
        }
    }

    return $null
}

$CodexExe = Resolve-CodexBundledTool -Name "codex"
$NodeExe = Resolve-CodexBundledTool -Name "node"

function Get-MementoMinimalRuntimeGateMissing {
    $requirements = @(
        @{ Path = "lib\config.js"; Pattern = "NLI_ENABLED"; Description = "NLI_ENABLED config gate" },
        @{ Path = "lib\config.js"; Pattern = "RERANKER_ENABLED"; Description = "RERANKER_ENABLED config gate" },
        @{ Path = "lib\memory\signals\NLIClassifier.js"; Pattern = "NLI_ENABLED"; Description = "NLI disabled mode" },
        @{ Path = "lib\memory\Reranker.js"; Pattern = "RERANKER_ENABLED"; Description = "Reranker disabled mode" }
    )

    $missing = @()
    foreach ($requirement in $requirements) {
        $path = Join-PathStrict $SourceRoot $requirement.Path
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            $missing += ($requirement.Description + " missing file " + $requirement.Path)
            continue
        }
        if (-not (Select-String -LiteralPath $path -SimpleMatch -Pattern $requirement.Pattern -Quiet)) {
            $missing += ($requirement.Description + " missing pattern " + $requirement.Pattern)
        }
    }

    return @($missing)
}

function Assert-MementoMinimalRuntimeGateSupport {
    $missing = @(Get-MementoMinimalRuntimeGateMissing)
    if ($missing.Count -gt 0) {
        $patchPath = Join-PathStrict $CodexHome "maintenance\patches\memento-minimal-runtime-gates.patch"
        throw "Memento source is missing minimal runtime gates: $($missing -join '; '). Apply and review patch: $patchPath"
    }
}

function Read-DotEnv {
    param([Parameter(Mandatory = $true)][string] $Path)

    $map = @{}
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $map
    }

    foreach ($line in (Get-Content -LiteralPath $Path)) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith("#")) {
            continue
        }
        $index = $trimmed.IndexOf("=")
        if ($index -lt 1) {
            continue
        }
        $name = $trimmed.Substring(0, $index).Trim()
        $value = $trimmed.Substring($index + 1).Trim()
        if (($value.StartsWith('"') -and $value.EndsWith('"')) -or ($value.StartsWith("'") -and $value.EndsWith("'"))) {
            $value = $value.Substring(1, $value.Length - 2)
        }
        $map[$name] = $value
    }

    return $map
}

$EnvMap = Read-DotEnv -Path $EnvPath

function Get-EnvValue {
    param(
        [Parameter(Mandatory = $true)][string] $Name,
        [string] $Default = ""
    )

    if ($EnvMap.ContainsKey($Name) -and -not [string]::IsNullOrWhiteSpace([string]$EnvMap[$Name])) {
        return [string]$EnvMap[$Name]
    }
    $fromProcess = [Environment]::GetEnvironmentVariable($Name, "Process")
    if (-not [string]::IsNullOrWhiteSpace($fromProcess)) {
        return $fromProcess
    }
    $fromUser = [Environment]::GetEnvironmentVariable($Name, "User")
    if (-not [string]::IsNullOrWhiteSpace($fromUser)) {
        return $fromUser
    }
    return $Default
}

$Port = [int](Get-EnvValue -Name "PORT" -Default "57332")
$HostAddress = Get-EnvValue -Name "HOST" -Default "127.0.0.1"
$HttpClientHost = if ($HostAddress -in @("0.0.0.0", "::", "")) { "127.0.0.1" } else { $HostAddress }
$PgPort = [int](Get-EnvValue -Name "POSTGRES_PORT" -Default "55432")
$PgHost = Get-EnvValue -Name "POSTGRES_HOST" -Default "127.0.0.1"
$PgDb = Get-EnvValue -Name "POSTGRES_DB" -Default "memento_pm"
$PgUser = Get-EnvValue -Name "POSTGRES_USER" -Default "memento"
$InProcessOnnxEnabled = Get-EnvValue -Name "MEMENTO_INPROCESS_ONNX_ENABLED" -Default "false"
$ManagedEmbeddingProvider = Get-EnvValue -Name "MEMENTO_MANAGED_EMBEDDING_PROVIDER" -Default "none"
$MaxWorkingSetMb = [double](Get-EnvValue -Name "MEMENTO_MAX_WORKING_SET_MB" -Default "512")
$HttpTimeoutSec = [int](Get-EnvValue -Name "MEMENTO_HTTP_TIMEOUT_SECONDS" -Default "30")

function Resolve-PostgresBin {
    $scoopPath = Join-PathStrict $env:USERPROFILE "scoop\apps\postgresql\current\bin"
    if (Test-Path -LiteralPath (Join-PathStrict $scoopPath "pg_ctl.exe") -PathType Leaf) {
        return $scoopPath
    }

    $pgCtl = Get-Command pg_ctl.exe -ErrorAction Stop
    return Split-Path -Parent $pgCtl.Source
}

$PostgresBin = Resolve-PostgresBin
$PgCtl = Join-PathStrict $PostgresBin "pg_ctl.exe"
$PgIsReady = Join-PathStrict $PostgresBin "pg_isready.exe"
$Psql = Join-PathStrict $PostgresBin "psql.exe"
$PostgresExe = Join-PathStrict $PostgresBin "postgres.exe"

if ([string]::IsNullOrWhiteSpace($NodeExe) -or -not (Test-Path -LiteralPath $NodeExe -PathType Leaf)) {
    $NodeExe = (Get-Command node.exe -ErrorAction Stop).Source
}
if ([string]::IsNullOrWhiteSpace($CodexExe) -or -not (Test-Path -LiteralPath $CodexExe -PathType Leaf)) {
    $CodexExe = (Get-Command codex.exe -ErrorAction SilentlyContinue).Source
}

function Write-Detail {
    param([Parameter(Mandatory = $true)][string] $Message)
    Write-Output ("detail=" + $Message)
}

function Set-ScopedProcessEnv {
    param([Parameter(Mandatory = $true)][hashtable] $Values)

    $previous = @{}
    foreach ($name in $Values.Keys) {
        $previous[$name] = [Environment]::GetEnvironmentVariable($name, "Process")
        [Environment]::SetEnvironmentVariable($name, [string]$Values[$name], "Process")
    }
    return $previous
}

function Restore-ScopedProcessEnv {
    param([Parameter(Mandatory = $true)][hashtable] $Previous)

    foreach ($name in $Previous.Keys) {
        if ($null -eq $Previous[$name]) {
            [Environment]::SetEnvironmentVariable($name, $null, "Process")
        } else {
            [Environment]::SetEnvironmentVariable($name, [string]$Previous[$name], "Process")
        }
    }
}

function Test-PostgresReady {
    $output = @(& $PgIsReady -h $PgHost -p $PgPort -d $PgDb 2>&1)
    return ($LASTEXITCODE -eq 0 -and (($output | Out-String) -match "accepting connections"))
}

function Test-MementoHealth {
    try {
        $health = Invoke-RestMethod -Method Get -Uri "http://$HttpClientHost`:$Port/health" -TimeoutSec 5
        return ([string]$health.status -eq "healthy")
    } catch {
        return $false
    }
}

function Test-CurrentTokenAdministrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Assert-PostgresNonAdminLaunchToken {
    if (Test-CurrentTokenAdministrator) {
        throw "PostgreSQL refuses to run from an elevated administrator token. Start Codex or PowerShell normally as the current user, then rerun this script. This Memento runtime is designed to run without administrator privileges."
    }
}

function Get-MementoServerProcess {
    if (-not (Test-Path -LiteralPath $ServerPidPath -PathType Leaf)) {
        return $null
    }

    $pidText = (Get-Content -LiteralPath $ServerPidPath -TotalCount 1).Trim()
    $pidValue = 0
    if (-not [int]::TryParse($pidText, [ref]$pidValue)) {
        return $null
    }

    $proc = Get-Process -Id $pidValue -ErrorAction SilentlyContinue
    if ($null -eq $proc) {
        return $null
    }

    $escapedRoot = [regex]::Escape($SourceRoot)
    $cim = Get-CimInstance Win32_Process -Filter "ProcessId = $pidValue" -ErrorAction SilentlyContinue
    if ($null -ne $cim -and [string]$cim.CommandLine -match "server\.js" -and
        ([string]$cim.CommandLine -match $escapedRoot -or $proc.ProcessName -match "node")) {
        return $proc
    }

    return $null
}

function Convert-ToRuntimeMatchPath {
    param([string] $Path)

    if ($null -eq $Path) {
        return ""
    }
    return ([string]$Path).Replace("\", "/").ToLowerInvariant()
}

function Get-PostmasterPidFromFile {
    $pidPath = Join-PathStrict $PgData "postmaster.pid"
    if (-not (Test-Path -LiteralPath $pidPath -PathType Leaf)) {
        return $null
    }

    $pidText = (Get-Content -LiteralPath $pidPath -TotalCount 1).Trim()
    $pidValue = 0
    if ([int]::TryParse($pidText, [ref]$pidValue)) {
        return $pidValue
    }
    return $null
}

function Get-MementoPostgresProcessIds {
    $ids = New-Object System.Collections.Generic.List[int]
    $postmasterPid = Get-PostmasterPidFromFile
    if ($null -ne $postmasterPid) {
        $proc = Get-Process -Id $postmasterPid -ErrorAction SilentlyContinue
        if ($null -ne $proc -and $proc.ProcessName -match "postgres") {
            $ids.Add([int]$postmasterPid) | Out-Null
        }
    }

    $needle = Convert-ToRuntimeMatchPath -Path $PgData
    $processes = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue)
    foreach ($proc in $processes) {
        $cmd = Convert-ToRuntimeMatchPath -Path ([string]$proc.CommandLine)
        if ([string]$proc.Name -match "postgres" -and $cmd.Contains($needle)) {
            $ids.Add([int]$proc.ProcessId) | Out-Null
        }
    }

    $changed = $true
    while ($changed) {
        $changed = $false
        $current = @($ids | Sort-Object -Unique)
        foreach ($proc in $processes) {
            if ([string]$proc.Name -match "postgres" -and $current -contains [int]$proc.ParentProcessId -and $current -notcontains [int]$proc.ProcessId) {
                $ids.Add([int]$proc.ProcessId) | Out-Null
                $changed = $true
            }
        }
    }

    return @($ids | Sort-Object -Unique)
}

function Test-PostgresPortListening {
    try {
        $listeners = @(Get-NetTCPConnection -LocalPort $PgPort -State Listen -ErrorAction SilentlyContinue)
        return ($listeners.Count -gt 0)
    } catch {
        return $false
    }
}

function Wait-PostgresStopped {
    param([int] $TimeoutSeconds = 15)

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        if (@(Get-MementoPostgresProcessIds).Count -eq 0 -and -not (Test-PostgresPortListening)) {
            return $true
        }
        Start-Sleep -Milliseconds 500
    }
    return (@(Get-MementoPostgresProcessIds).Count -eq 0 -and -not (Test-PostgresPortListening))
}

function Clear-StalePostmasterPid {
    $pidPath = Join-PathStrict $PgData "postmaster.pid"
    if (-not (Test-Path -LiteralPath $pidPath -PathType Leaf)) {
        return
    }
    if (Test-PostgresReady -or @(Get-MementoPostgresProcessIds).Count -gt 0) {
        return
    }
    Remove-Item -LiteralPath $pidPath -Force -ErrorAction SilentlyContinue
    Write-Detail "postgres=removed-stale-postmaster-pid"
}

function Get-ProcessWorkingSetMb {
    param($Process)

    if ($null -eq $Process) {
        return $null
    }

    return [math]::Round($Process.WorkingSet64 / 1MB, 1)
}

function Get-ProcessPrivateMb {
    param($Process)

    if ($null -eq $Process) {
        return $null
    }

    return [math]::Round($Process.PrivateMemorySize64 / 1MB, 1)
}

function Start-PostgresRuntime {
    if (Test-PostgresReady) {
        Write-Detail "postgres=already-ready"
        return
    }

    if (-not (Test-Path -LiteralPath $PgData -PathType Container)) {
        throw "PostgreSQL data directory not found: $PgData"
    }

    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
    $existingPostgres = @(Get-MementoPostgresProcessIds)
    if ($existingPostgres.Count -gt 0 -or (Test-PostgresPortListening)) {
        Write-Detail ("postgres=stuck-detected pids=" + (($existingPostgres | ForEach-Object { [string]$_ }) -join ","))
        Stop-PostgresRuntime
    }

    Clear-StalePostmasterPid
    Assert-PostgresNonAdminLaunchToken

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $pgLog = Join-PathStrict $LogRoot ("postgresql-" + $timestamp + ".out.log")
    $pgErrLog = Join-PathStrict $LogRoot ("postgresql-" + $timestamp + ".err.log")
    $postgresProc = Start-Process -FilePath $PostgresExe -ArgumentList @("-D", $PgData, "-p", [string]$PgPort) -RedirectStandardOutput $pgLog -RedirectStandardError $pgErrLog -WindowStyle Hidden -PassThru

    $deadline = (Get-Date).AddSeconds(30)
    while ((Get-Date) -lt $deadline -and -not (Test-PostgresReady)) {
        if ($postgresProc.HasExited) {
            throw "PostgreSQL process exited before readiness; see $pgErrLog"
        }
        Start-Sleep -Milliseconds 500
    }
    if (-not (Test-PostgresReady)) {
        throw "PostgreSQL did not become ready on ${PgHost}:${PgPort}"
    }
    Write-Detail ("postgres=started pid=" + [string]$postgresProc.Id + " log=" + $pgLog)
}

function Stop-PostgresRuntime {
    if (-not (Test-Path -LiteralPath $PgData -PathType Container)) {
        Write-Detail "postgres=missing-data-dir"
        return
    }

    $runtimePids = @(Get-MementoPostgresProcessIds)
    if (-not (Test-PostgresReady) -and $runtimePids.Count -eq 0 -and -not (Test-PostgresPortListening)) {
        Clear-StalePostmasterPid
        Write-Detail "postgres=already-stopped-or-unreachable"
        return
    }

    $stopOutput = @(& $PgCtl -D $PgData -m fast stop 2>&1)
    if ($LASTEXITCODE -eq 0 -and (Wait-PostgresStopped -TimeoutSeconds 10)) {
        Clear-StalePostmasterPid
        Write-Detail "postgres=stopped"
        return
    }

    if ($stopOutput.Count -gt 0) {
        Write-Detail ("postgres=fast-stop-failed " + (($stopOutput | Select-Object -First 1) -replace "\s+", " ").Trim())
    }

    $runtimePids = @(Get-MementoPostgresProcessIds)
    if ($runtimePids.Count -gt 0) {
        foreach ($pidValue in $runtimePids) {
            Stop-Process -Id $pidValue -Force -ErrorAction SilentlyContinue
        }
        Write-Detail ("postgres=forced-stop pids=" + (($runtimePids | ForEach-Object { [string]$_ }) -join ","))
    }

    if (-not (Wait-PostgresStopped -TimeoutSeconds 15)) {
        throw "PostgreSQL runtime processes did not stop for data directory: $PgData"
    }

    Clear-StalePostmasterPid
    Write-Detail "postgres=stopped"
}

function Start-MementoRuntime {
    if (-not (Test-Path -LiteralPath (Join-PathStrict $SourceRoot "server.js") -PathType Leaf)) {
        throw "Memento source is missing server.js: $SourceRoot"
    }
    Assert-MementoMinimalRuntimeGateSupport

    Start-PostgresRuntime

    if (Test-MementoHealth) {
        Write-Detail "memento=http-already-healthy"
        return
    }

    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
    Remove-Item -LiteralPath $ServerPidPath -ErrorAction SilentlyContinue

    $childEnv = @{
        HOST = $HostAddress
        MEMENTO_INPROCESS_ONNX_ENABLED = $InProcessOnnxEnabled
        EMBEDDING_PROVIDER = $ManagedEmbeddingProvider
        MEMENTO_SEARCH_PARAM_ADAPTOR_ENABLED = "false"
        RERANKER_ENABLED = "false"
        NLI_ENABLED = "false"
    }
    if ($ManagedEmbeddingProvider -eq "none") {
        $childEnv["EMBEDDING_API_KEY"] = ""
        $childEnv["EMBEDDING_BASE_URL"] = ""
        $childEnv["OPENAI_API_KEY"] = ""
        $childEnv["GEMINI_API_KEY"] = ""
        $childEnv["CF_API_TOKEN"] = ""
        $childEnv["CLOUDFLARE_API_TOKEN"] = ""
    }

    $previousEnv = Set-ScopedProcessEnv -Values $childEnv
    try {
        $proc = Start-Process -FilePath $NodeExe -ArgumentList @("server.js") -WorkingDirectory $SourceRoot -RedirectStandardOutput $ServerOutLog -RedirectStandardError $ServerErrLog -WindowStyle Hidden -PassThru
    }
    finally {
        Restore-ScopedProcessEnv -Previous $previousEnv
    }
    Set-Content -LiteralPath $ServerPidPath -Value ([string]$proc.Id) -Encoding ascii

    $deadline = (Get-Date).AddSeconds(45)
    while ((Get-Date) -lt $deadline) {
        if (Test-MementoHealth) {
            Write-Detail "memento=started"
            return
        }
        Start-Sleep -Milliseconds 750
    }

    throw "Memento HTTP health did not become healthy on port $Port"
}

function Stop-MementoRuntime {
    param([bool] $StopPostgres = $true)

    $proc = Get-MementoServerProcess
    if ($null -ne $proc) {
        Stop-Process -Id $proc.Id -Force
        Remove-Item -LiteralPath $ServerPidPath -ErrorAction SilentlyContinue
        Write-Detail "memento=stopped"
    } else {
        Remove-Item -LiteralPath $ServerPidPath -ErrorAction SilentlyContinue
        Write-Detail "memento=already-stopped-or-untracked"
    }

    if ($StopPostgres) {
        Stop-PostgresRuntime
    }
}

function Invoke-PsqlScalar {
    param([Parameter(Mandatory = $true)][string] $Sql)

    $previous = [Environment]::GetEnvironmentVariable("PGPASSWORD", "Process")
    try {
        Set-Item -Path "Env:\PGPASSWORD" -Value (Get-EnvValue -Name "POSTGRES_PASSWORD")
        $output = @(& $Psql -h $PgHost -p $PgPort -U $PgUser -d $PgDb -tAc $Sql 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw (($output | Out-String).Trim())
        }
        return (($output | Out-String).Trim())
    }
    finally {
        if ($null -eq $previous) {
            Remove-Item -Path "Env:\PGPASSWORD" -ErrorAction SilentlyContinue
        } else {
            Set-Item -Path "Env:\PGPASSWORD" -Value $previous
        }
    }
}

function Invoke-MementoRpc {
    param(
        [Parameter(Mandatory = $true)][string] $Method,
        [hashtable] $Params = @{},
        [ref] $SessionId,
        [ref] $RequestId
    )

    $accessKey = Get-EnvValue -Name "MEMENTO_ACCESS_KEY"
    if ([string]::IsNullOrWhiteSpace($accessKey)) {
        throw "MEMENTO_ACCESS_KEY is missing from user environment or .env"
    }

    $RequestId.Value = [int]$RequestId.Value + 1
    $headers = @{
        Authorization = "Bearer $accessKey"
        Accept = "application/json, text/event-stream"
        "Content-Type" = "application/json"
    }
    if (-not [string]::IsNullOrWhiteSpace([string]$SessionId.Value)) {
        $headers["mcp-session-id"] = [string]$SessionId.Value
    }
    $body = @{
        jsonrpc = "2.0"
        id = [int]$RequestId.Value
        method = $Method
        params = $Params
    } | ConvertTo-Json -Depth 20

    $response = Invoke-WebRequest -Uri "http://$HttpClientHost`:$Port/mcp" -Method Post -Headers $headers -Body $body -UseBasicParsing -TimeoutSec $HttpTimeoutSec
    if ([string]::IsNullOrWhiteSpace([string]$SessionId.Value) -and $response.Headers -and $response.Headers["mcp-session-id"]) {
        $SessionId.Value = [string]($response.Headers["mcp-session-id"] | Select-Object -First 1)
    }
    return ($response.Content | ConvertFrom-Json)
}

function Invoke-MementoTool {
    param(
        [Parameter(Mandatory = $true)][string] $Name,
        [hashtable] $Arguments = @{},
        [ref] $SessionId,
        [ref] $RequestId
    )

    return Invoke-MementoRpc -Method "tools/call" -Params @{ name = $Name; arguments = $Arguments } -SessionId $SessionId -RequestId $RequestId
}

function Get-ToolTextJson {
    param($ToolResult)

    if ($null -ne $ToolResult.error) {
        throw ($ToolResult.error | ConvertTo-Json -Depth 8)
    }
    return ($ToolResult.result.content[0].text | ConvertFrom-Json)
}

function Invoke-MementoVerify {
    param([bool] $AllowMemoryWrite = $false)

    Start-MementoRuntime

    $vectorTypes = Invoke-PsqlScalar -Sql "SELECT string_agg(c.relname || ':' || format_type(a.atttypid, a.atttypmod), ', ' ORDER BY c.relname) FROM pg_attribute a JOIN pg_class c ON c.oid = a.attrelid JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'agent_memory' AND c.relname IN ('fragments','morpheme_dict') AND a.attname = 'embedding' AND NOT a.attisdropped;"
    Write-Detail ("vector_types=" + $vectorTypes)

    if (-not [string]::IsNullOrWhiteSpace($CodexExe)) {
        $mcpInfo = @(& $CodexExe mcp get memento --json 2>&1)
        if ($LASTEXITCODE -eq 0) {
            $mcp = ($mcpInfo | Out-String).Trim() | ConvertFrom-Json
            Write-Detail ("codex_mcp_enabled=" + [string]$mcp.enabled)
            $mcpUrl = [string]$mcp.url
            if ([string]::IsNullOrWhiteSpace($mcpUrl) -and $null -ne $mcp.transport) {
                $mcpUrl = [string]$mcp.transport.url
            }
            Write-Detail ("codex_mcp_url=" + $mcpUrl)
        } else {
            Write-Detail "codex_mcp_get=not-available"
        }
    }

    $sessionId = [ref]""
    $requestId = [ref]0
    $init = Invoke-MementoRpc -Method "initialize" -Params @{ protocolVersion = "2024-11-05"; capabilities = @{}; clientInfo = @{ name = "codex-memento-runtime"; version = "1.0.0" } } -SessionId $sessionId -RequestId $requestId
    if ($null -eq $init.result.protocolVersion) {
        throw "MCP initialize did not return a protocol version"
    }

    $tools = Invoke-MementoRpc -Method "tools/list" -Params @{} -SessionId $sessionId -RequestId $requestId
    $toolNames = @($tools.result.tools | ForEach-Object { $_.name })
    $required = @("remember", "recall", "context", "reflect", "tool_feedback", "get_skill_guide", "memory_stats", "search_traces")
    $missing = @($required | Where-Object { $toolNames -notcontains $_ })
    if ($missing.Count -gt 0) {
        throw "Memento tools missing: $($missing -join ', ')"
    }
    Write-Detail ("mcp_tool_count=" + $toolNames.Count)
    Write-Detail "required_tools=present"

    $guide = Get-ToolTextJson (Invoke-MementoTool -Name "get_skill_guide" -Arguments @{ section = "lifecycle" } -SessionId $sessionId -RequestId $requestId)
    if (-not [bool]$guide.success) {
        throw "get_skill_guide lifecycle failed"
    }
    Write-Detail "skill_guide_lifecycle=pass"

    $contextArgs = @{ workspace = "global_pm"; structured = $true }
    $contextArgs["tokenBudget"] = 1200
    $context = Get-ToolTextJson (Invoke-MementoTool -Name "context" -Arguments $contextArgs -SessionId $sessionId -RequestId $requestId)
    if (-not [bool]$context.success) {
        throw "context failed"
    }
    Write-Detail "context=pass"

    $recall = Get-ToolTextJson (Invoke-MementoTool -Name "recall" -Arguments @{ topic = "memento-pm-runtime"; workspace = "global_pm"; limit = 1; includeContext = $true; excludeSeen = $false } -SessionId $sessionId -RequestId $requestId)
    if ([int]$recall.count -lt 1) {
        if (-not $AllowMemoryWrite) {
            throw "recall did not return the runtime support fragment; rerun repair or verify -WriteProbe only when a write probe is intended"
        }
        $remember = Get-ToolTextJson (Invoke-MementoTool -Name "remember" -Arguments @{
            content = "Memento MCP runtime verification created the initial support-only Codex PM memory fragment."
            topic = "memento-pm-runtime"
            type = "decision"
            keywords = @("memento", "codex", "pm", "runtime")
            importance = 0.8
            workspace = "global_pm"
            caseId = "ops-memory-20260515-clean-memento-native-runtime"
            phase = "verification"
            assertionStatus = "verified"
        } -SessionId $sessionId -RequestId $requestId)
        if (-not [bool]$remember.success) {
            throw "remember probe failed"
        }
        $recall = Get-ToolTextJson (Invoke-MementoTool -Name "recall" -Arguments @{ topic = "memento-pm-runtime"; workspace = "global_pm"; limit = 1; includeContext = $true; excludeSeen = $false } -SessionId $sessionId -RequestId $requestId)
    }
    if ([int]$recall.count -lt 1) {
        throw "recall did not return the runtime support fragment"
    }
    Write-Detail ("recall=pass count=" + [string]$recall.count)

    if ($AllowMemoryWrite) {
        $fragmentIds = @([string]$recall.fragments[0].id)
        $searchEventId = [int]$recall._meta.searchEventId
        $feedback = Get-ToolTextJson (Invoke-MementoTool -Name "tool_feedback" -Arguments @{
            tool_name = "recall"
            relevant = $true
            sufficient = $true
            suggestion = "Runtime smoke returned the expected support-only fragment."
            context = "runtime verify"
            trigger_type = "voluntary"
            fragment_ids = $fragmentIds
            search_event_id = $searchEventId
        } -SessionId $sessionId -RequestId $requestId)
        if (-not [bool]$feedback.success) {
            throw "tool_feedback failed"
        }
        Write-Detail "tool_feedback=pass"
    } else {
        Write-Detail "tool_feedback=skipped-readonly"
    }

    $proc = Get-MementoServerProcess
    if ($null -eq $proc) {
        throw "Memento process is not tracked after verification"
    }
    $workingSetMb = Get-ProcessWorkingSetMb -Process $proc
    Write-Detail ("memento_working_set_mb=" + [string]$workingSetMb)
    Write-Detail ("memento_max_working_set_mb=" + [string]$MaxWorkingSetMb)
    if ($workingSetMb -gt $MaxWorkingSetMb) {
        throw "Memento working set ${workingSetMb}MB exceeds managed limit ${MaxWorkingSetMb}MB"
    }

    Write-Output "status=pass"
}

function Invoke-MementoRepair {
    Write-Detail "repair=begin"
    Stop-MementoRuntime -StopPostgres $true
    Start-MementoRuntime
    Invoke-MementoVerify -AllowMemoryWrite $true
    Write-Detail "repair=complete"
}

function Invoke-Status {
    Write-Output "status=observed"
    Write-Detail ("source_root=" + $SourceRoot)
    Write-Detail ("state_root=" + $StateRoot)
    Write-Detail "user_permission=allowed"
    Write-Detail ("current_process_administrator=" + [string](Test-CurrentTokenAdministrator))
    Write-Detail ("postgres_ready=" + [string](Test-PostgresReady))
    Write-Detail ("memento_health=" + [string](Test-MementoHealth))
    Write-Detail ("memento_inprocess_onnx_enabled=" + $InProcessOnnxEnabled)
    Write-Detail ("memento_managed_embedding_provider=" + $ManagedEmbeddingProvider)
    Write-Detail ("memento_max_working_set_mb=" + [string]$MaxWorkingSetMb)
    $missingGates = @(Get-MementoMinimalRuntimeGateMissing)
    Write-Detail ("memento_minimal_runtime_gates=" + $(if ($missingGates.Count -eq 0) { "present" } else { "missing:" + ($missingGates -join ";") }))
    $proc = Get-MementoServerProcess
    Write-Detail ("memento_pid=" + $(if ($null -eq $proc) { "none" } else { [string]$proc.Id }))
    if ($null -ne $proc) {
        Write-Detail ("memento_working_set_mb=" + [string](Get-ProcessWorkingSetMb -Process $proc))
        Write-Detail ("memento_private_mb=" + [string](Get-ProcessPrivateMb -Process $proc))
        Write-Detail ("memento_started_at=" + $proc.StartTime.ToString("s"))
    }
}

switch ($Action) {
    "status" { Invoke-Status; break }
    "start" { Start-MementoRuntime; Invoke-Status; break }
    "stop" { Stop-MementoRuntime; Invoke-Status; break }
    "restart" { Stop-MementoRuntime -StopPostgres $false; Start-MementoRuntime; Invoke-Status; break }
    "repair" { Invoke-MementoRepair; break }
    "verify" { Invoke-MementoVerify -AllowMemoryWrite ([bool]$WriteProbe); break }
}
