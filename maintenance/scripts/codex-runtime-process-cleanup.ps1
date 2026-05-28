param(
    [ValidateSet("status", "cleanup-stale", "cleanup-all", "watch", "ensure-watch")]
    [string]$Mode = "status",
    [int]$ParentPid = 0,
    [int]$PollSeconds = 3,
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE ".codex" }),
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Get-ProcessTable {
    @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Select-Object ProcessId, ParentProcessId, Name, CreationDate, CommandLine)
}

function Get-CodexAppServer {
    param([object[]]$Processes)

    $candidates = @($Processes | Where-Object {
        [string]$_.Name -ieq "codex.exe" -and [string]$_.CommandLine -match "\bapp-server\b" -and
            [string]$_.CommandLine -notmatch "--listen\s+stdio://"
    } | Sort-Object CreationDate -Descending)

    if ($candidates.Count -gt 0) {
        return $candidates[0]
    }
    return $null
}

function Get-ManagedRootKey {
    param(
        [string]$Name,
        [string]$CommandLine
    )

    if ($CommandLine -match "uvx.*\bserena\b.*\bstart-mcp-server\b") { return "serena" }
    if ($CommandLine -match "npx.*@upstash/context7-mcp") { return "context7" }
    if ($CommandLine -match "npx.*chrome-devtools-mcp") { return "chrome-devtools" }
    if ($Name -ieq "node_repl.exe") { return "node_repl" }
    if ($Name -ieq "pwsh.exe" -and $CommandLine -match "-EncodedCommand") { return "powershell-command-parser" }
    if ($Name -ieq "conhost.exe") { return "appserver-conhost" }
    return $null
}

function Get-ManagedRoots {
    param(
        [object[]]$Processes,
        [int]$RootParentPid
    )

    @($Processes | Where-Object {
        $_.ParentProcessId -eq $RootParentPid -and
            $null -ne (Get-ManagedRootKey -Name ([string]$_.Name) -CommandLine ([string]$_.CommandLine))
    } | ForEach-Object {
        [pscustomobject]@{
            Key = Get-ManagedRootKey -Name ([string]$_.Name) -CommandLine ([string]$_.CommandLine)
            ProcessId = [int]$_.ProcessId
            ParentProcessId = [int]$_.ParentProcessId
            CreationDate = $_.CreationDate
            Name = [string]$_.Name
            CommandLine = [string]$_.CommandLine
        }
    })
}

function Get-DescendantIds {
    param(
        [object[]]$Processes,
        [int]$RootPid
    )

    $ids = New-Object System.Collections.Generic.List[int]
    $queue = New-Object System.Collections.Generic.Queue[int]
    $queue.Enqueue($RootPid)

    while ($queue.Count -gt 0) {
        $current = $queue.Dequeue()
        if (-not $ids.Contains($current)) {
            $ids.Add($current) | Out-Null
            foreach ($child in @($Processes | Where-Object { $_.ParentProcessId -eq $current })) {
                $queue.Enqueue([int]$child.ProcessId)
            }
        }
    }

    return @($ids)
}

function Write-Ledger {
    param(
        [string]$Action,
        [object]$Details
    )

    $stateDir = Join-Path $CodexHome "state"
    New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
    $record = [ordered]@{
        ts = (Get-Date).ToUniversalTime().ToString("o")
        script = "codex-runtime-process-cleanup"
        action = $Action
        details = $Details
    }
    ($record | ConvertTo-Json -Compress -Depth 12) |
        Add-Content -LiteralPath (Join-Path $stateDir "runtime-process-cleanup.jsonl") -Encoding UTF8
}

function Stop-ProcessTree {
    param(
        [object[]]$Processes,
        [int]$RootPid,
        [string]$Reason
    )

    $ids = @(Get-DescendantIds -Processes $Processes -RootPid $RootPid)
    $ordered = @($ids | Sort-Object -Descending)
    $details = [ordered]@{
        root_pid = $RootPid
        reason = $Reason
        process_ids = $ordered
        dry_run = [bool]$DryRun
    }
    Write-Ledger -Action "stop_tree" -Details $details

    if ($DryRun) {
        return ,$details
    }

    foreach ($id in $ordered) {
        try {
            Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
        } catch {
            Write-Ledger -Action "stop_error" -Details @{ process_id = $id; error = $_.Exception.Message }
        }
    }
    return ,$details
}

function Get-Status {
    param([int]$AppServerPid)

    $processes = Get-ProcessTable
    $appServer = if ($AppServerPid -gt 0) {
        $processes | Where-Object { $_.ProcessId -eq $AppServerPid } | Select-Object -First 1
    } else {
        Get-CodexAppServer -Processes $processes
    }

    if ($null -eq $appServer) {
        return ,([pscustomobject]@{
            app_server_pid = $null
            managed_roots = @()
            duplicate_keys = @()
        })
    }

    $roots = @(Get-ManagedRoots -Processes $processes -RootParentPid ([int]$appServer.ProcessId))
    $duplicates = @($roots | Group-Object Key | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
    return ,([pscustomobject]@{
        app_server_pid = [int]$appServer.ProcessId
        app_server_command = [string]$appServer.CommandLine
        managed_roots = @($roots | Sort-Object Key, CreationDate)
        duplicate_keys = $duplicates
    })
}

function Invoke-CleanupStale {
    param([int]$AppServerPid)

    $processes = Get-ProcessTable
    $status = Get-Status -AppServerPid $AppServerPid
    if ($null -eq $status.app_server_pid) {
        return ,([pscustomobject]@{ app_server_pid = $null; stopped = @(); note = "app-server not found" })
    }

    $appServerPidValue = [int](@($status.app_server_pid)[0])
    $roots = @(Get-ManagedRoots -Processes $processes -RootParentPid $appServerPidValue)
    $stopped = New-Object System.Collections.Generic.List[object]
    foreach ($group in @($roots | Group-Object Key)) {
        $keep = @($group.Group | Sort-Object CreationDate -Descending | Select-Object -First 1)[0]
        foreach ($stale in @($group.Group | Where-Object { $_.ProcessId -ne $keep.ProcessId })) {
            $stopped.Add((Stop-ProcessTree -Processes $processes -RootPid ([int]$stale.ProcessId) -Reason ("stale-" + $group.Name))) | Out-Null
        }
    }

    return ,([pscustomobject]@{
        app_server_pid = $appServerPidValue
        stopped = @($stopped.ToArray())
    })
}

function Invoke-CleanupAll {
    param(
        [int]$AppServerPid,
        [int[]]$KnownRootPids = @()
    )

    $processes = Get-ProcessTable
    $rootPids = New-Object System.Collections.Generic.HashSet[int]

    foreach ($pid in $KnownRootPids) {
        $null = $rootPids.Add([int]$pid)
    }

    if ($AppServerPid -gt 0) {
        foreach ($root in @(Get-ManagedRoots -Processes $processes -RootParentPid $AppServerPid)) {
            $null = $rootPids.Add([int]$root.ProcessId)
        }
    }

    $stopped = New-Object System.Collections.Generic.List[object]
    foreach ($pid in @($rootPids)) {
        if (@($processes | Where-Object { $_.ProcessId -eq $pid }).Count -gt 0) {
            $stopped.Add((Stop-ProcessTree -Processes $processes -RootPid $pid -Reason "app-server-exit")) | Out-Null
        }
    }

    return ,([pscustomobject]@{
        app_server_pid = $AppServerPid
        stopped = @($stopped.ToArray())
    })
}

function Invoke-Watch {
    param([int]$AppServerPid)

    if ($AppServerPid -le 0) {
        $status = Get-Status -AppServerPid 0
        if ($null -eq $status.app_server_pid) {
            throw "Codex app-server not found."
        }
        $AppServerPid = [int]$status.app_server_pid
    }

    $known = New-Object System.Collections.Generic.HashSet[int]
    Write-Ledger -Action "watch_start" -Details @{ app_server_pid = $AppServerPid; poll_seconds = $PollSeconds }

    while ($true) {
        $processes = Get-ProcessTable
        $parentAlive = @($processes | Where-Object { $_.ProcessId -eq $AppServerPid }).Count -gt 0
        foreach ($root in @(Get-ManagedRoots -Processes $processes -RootParentPid $AppServerPid)) {
            $null = $known.Add([int]$root.ProcessId)
        }

        if (-not $parentAlive) {
            $result = Invoke-CleanupAll -AppServerPid $AppServerPid -KnownRootPids @($known)
            Write-Ledger -Action "watch_cleanup_complete" -Details $result
            return $result
        }

        Start-Sleep -Seconds $PollSeconds
    }
}

function Get-PwshPath {
    $candidates = @(
        (Join-Path $env:LOCALAPPDATA "Microsoft\WindowsApps\pwsh.exe"),
        "pwsh.exe",
        "powershell.exe"
    )

    foreach ($candidate in $candidates) {
        try {
            $resolved = Get-Command $candidate -ErrorAction Stop
            if ($resolved.Source) { return $resolved.Source }
        } catch {
        }
    }

    throw "PowerShell executable not found."
}

function Get-CurrentScriptPath {
    if ($PSCommandPath) { return $PSCommandPath }
    if ($MyInvocation.MyCommand.Path) { return $MyInvocation.MyCommand.Path }
    throw "Unable to resolve current script path."
}

function Test-WatcherRunning {
    param(
        [object[]]$Processes,
        [string]$ScriptPath,
        [int]$AppServerPid
    )

    @($Processes | Where-Object {
        [int]$_.ProcessId -ne [int]$PID -and
            [string]$_.Name -match "^(pwsh|powershell)\.exe$" -and
            [string]$_.CommandLine -match "codex-runtime-process-cleanup\.ps1" -and
            [string]$_.CommandLine -match "\s-Mode\s+watch\b" -and
            [string]$_.CommandLine -match ("\s-ParentPid\s+" + [regex]::Escape([string]$AppServerPid) + "\b")
    }).Count -gt 0
}

function Invoke-EnsureWatch {
    param([int]$AppServerPid)

    $cleanupResult = Invoke-CleanupStale -AppServerPid $AppServerPid
    $status = Get-Status -AppServerPid $AppServerPid
    if ($null -eq $status.app_server_pid) {
        $result = [pscustomobject]@{
            app_server_pid = $null
            cleanup_stale = $cleanupResult
            watcher_started = $false
            watcher_pid = $null
            note = "app-server not found"
        }
        Write-Ledger -Action "ensure_watch" -Details $result
        return ,$result
    }

    $appServerPidValue = [int](@($status.app_server_pid)[0])
    $scriptPath = Get-CurrentScriptPath
    $processes = Get-ProcessTable
    $alreadyRunning = Test-WatcherRunning -Processes $processes -ScriptPath $scriptPath -AppServerPid $appServerPidValue

    $watcherPid = $null
    if (-not $alreadyRunning -and -not $DryRun) {
        $stateDir = Join-Path $CodexHome "state"
        New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
        $outLog = Join-Path $stateDir ("runtime-process-watch-" + $appServerPidValue + ".out.log")
        $errLog = Join-Path $stateDir ("runtime-process-watch-" + $appServerPidValue + ".err.log")
        $pwsh = Get-PwshPath
        $started = Start-Process -FilePath $pwsh `
            -ArgumentList @(
                "-NoProfile",
                "-ExecutionPolicy", "Bypass",
                "-File", $scriptPath,
                "-Mode", "watch",
                "-ParentPid", ([string]$appServerPidValue),
                "-PollSeconds", ([string]$PollSeconds),
                "-CodexHome", $CodexHome
            ) `
            -WindowStyle Hidden `
            -RedirectStandardOutput $outLog `
            -RedirectStandardError $errLog `
            -PassThru
        $watcherPid = [int]$started.Id
    }

    $result = [pscustomobject]@{
        app_server_pid = $appServerPidValue
        cleanup_stale = $cleanupResult
        watcher_already_running = [bool]$alreadyRunning
        watcher_started = [bool]((-not $alreadyRunning) -and (-not $DryRun))
        watcher_pid = $watcherPid
        dry_run = [bool]$DryRun
    }
    Write-Ledger -Action "ensure_watch" -Details $result
    return ,$result
}

switch ($Mode) {
    "status" {
        Get-Status -AppServerPid $ParentPid | ConvertTo-Json -Depth 12
        break
    }
    "cleanup-stale" {
        Invoke-CleanupStale -AppServerPid $ParentPid | ConvertTo-Json -Depth 12
        break
    }
    "cleanup-all" {
        Invoke-CleanupAll -AppServerPid $ParentPid | ConvertTo-Json -Depth 12
        break
    }
    "watch" {
        Invoke-Watch -AppServerPid $ParentPid | ConvertTo-Json -Depth 12
        break
    }
    "ensure-watch" {
        Invoke-EnsureWatch -AppServerPid $ParentPid | ConvertTo-Json -Depth 12
        break
    }
}
