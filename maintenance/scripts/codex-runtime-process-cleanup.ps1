param(
    [ValidateSet("status", "cleanup-stale", "cleanup-all", "watch", "ensure-watch")]
    [string]$Mode = "status",
    [int]$ParentPid = 0,
    [int]$PollSeconds = 3,
    [int]$DuplicateGraceSeconds = 15,
    [int]$DuplicateConfirmations = 3,
    [string]$CodexHome = $(if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $env:USERPROFILE ".codex" }),
    [switch]$CleanupStaleOnEnsure,
    [switch]$StopAppServerOnOwnerExit,
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

function Get-ProcessTable {
    @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
        Select-Object ProcessId, ParentProcessId, Name, CreationDate, CommandLine)
}

function Get-CodexAppServer {
    param([object[]]$Processes)

    $candidates = @(Get-CodexAppServers -Processes $Processes)

    if ($candidates.Count -gt 0) {
        return $candidates[0]
    }
    return $null
}

function Get-CodexAppServers {
    param([object[]]$Processes)

    @($Processes | Where-Object {
        [string]$_.Name -ieq "codex.exe" -and [string]$_.CommandLine -match "\bapp-server\b" -and
            [string]$_.CommandLine -notmatch "--listen\s+stdio://"
    } | Sort-Object CreationDate -Descending)
}

function Get-ManagedRootKey {
    param(
        [string]$Name,
        [string]$CommandLine
    )

    $text = [string]$CommandLine
    if (($Name -ieq "cmd.exe" -or $Name -ieq "powershell.exe" -or $Name -ieq "pwsh.exe") -and
        $text -match "(?i)\\toolchains\\shims\\uv\.cmd\b.*\bserena\b.*\bstart-mcp-server\b") { return "serena" }
    if ($Name -ieq "serena.exe" -and $text -match "(?i)\bstart-mcp-server\b") { return "serena" }
    if (($Name -ieq "cmd.exe" -or $Name -ieq "powershell.exe" -or $Name -ieq "pwsh.exe") -and
        $text -match "(?i)\\toolchains\\shims\\npx\.cmd\b.*@upstash[\\/]context7-mcp") { return "context7" }
    if ($Name -ieq "node.exe" -and $text -match "(?i)@upstash[\\/]context7-mcp") { return "context7" }
    if (($Name -ieq "cmd.exe" -or $Name -ieq "powershell.exe" -or $Name -ieq "pwsh.exe") -and
        $text -match "(?i)\\toolchains\\shims\\npx\.cmd\b.*chrome-devtools-mcp") { return "chrome-devtools" }
    if ($Name -ieq "node.exe" -and $text -match "(?i)chrome-devtools-mcp") { return "chrome-devtools" }
    if ($Name -ieq "node_repl.exe") { return "node_repl" }
    if (($Name -ieq "cmd.exe" -or $Name -ieq "powershell.exe" -or $Name -ieq "pwsh.exe") -and
        $text -match "(?i)\\toolchains\\shims\\node_repl\.cmd\b") { return "node_repl" }
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

function Get-ManagedOrphans {
    param(
        [object[]]$Processes,
        [int]$RootParentPid
    )

    $roots = @(Get-ManagedRoots -Processes $Processes -RootParentPid $RootParentPid)
    $rootIds = @($roots | ForEach-Object { [int]$_.ProcessId })
    $orphans = New-Object System.Collections.Generic.List[object]
    foreach ($process in $Processes) {
        $isOrphan = $true
        $key = Get-ManagedRootKey -Name ([string]$process.Name) -CommandLine ([string]$process.CommandLine)
        if ($null -eq $key) { continue }
        if ([int]$process.ParentProcessId -eq $RootParentPid) { continue }
        foreach ($rootId in $rootIds) {
            if (Test-IsProcessDescendant -Processes $Processes -RootPid $rootId -CandidatePid ([int]$process.ProcessId)) {
                $isOrphan = $false
                break
            }
        }
        if (-not $isOrphan) { continue }
        $orphans.Add([pscustomobject]@{
            Key = $key
            ProcessId = [int]$process.ProcessId
            ParentProcessId = [int]$process.ParentProcessId
            CreationDate = $process.CreationDate
            Name = [string]$process.Name
            CommandLine = [string]$process.CommandLine
        }) | Out-Null
    }
    return @($orphans.ToArray())
}

function Stop-ManagedOrphans {
    param(
        [object[]]$Processes,
        [int]$AppServerPid,
        [string]$Reason
    )

    $stopped = New-Object System.Collections.Generic.List[object]
    foreach ($orphan in @(Get-ManagedOrphans -Processes $Processes -RootParentPid $AppServerPid)) {
        $stopped.Add((Stop-ProcessTree -Processes $Processes -RootPid ([int]$orphan.ProcessId) -Reason $Reason -ExpectedRootKey ([string]$orphan.Key))) | Out-Null
    }
    return @($stopped.ToArray())
}

function Get-ChromeExtensionHostProcesses {
    param([object[]]$Processes)

    $cacheRoot = Join-Path $CodexHome "plugins\cache\openai-bundled\chrome"
    $escapedCacheRoot = [regex]::Escape($cacheRoot)
    @($Processes | Where-Object {
        ([string]$_.Name -ieq "extension-host.exe" -and [string]$_.CommandLine -match $escapedCacheRoot) -or
            ([string]$_.Name -ieq "cmd.exe" -and [string]$_.CommandLine -match $escapedCacheRoot -and [string]$_.CommandLine -match "extension-host\.exe")
    } | ForEach-Object {
        [pscustomobject]@{
            ProcessId = [int]$_.ProcessId
            ParentProcessId = [int]$_.ParentProcessId
            CreationDate = $_.CreationDate
            Name = [string]$_.Name
            CommandLine = [string]$_.CommandLine
        }
    })
}

function Stop-ChromeExtensionHosts {
    param(
        [object[]]$Processes,
        [string]$Reason
    )

    $hosts = @(Get-ChromeExtensionHostProcesses -Processes $Processes)
    $hostPidSet = New-Object System.Collections.Generic.HashSet[int]
    foreach ($hostProcess in $hosts) {
        $null = $hostPidSet.Add([int]$hostProcess.ProcessId)
    }
    $roots = @($hosts | Where-Object { -not $hostPidSet.Contains([int]$_.ParentProcessId) })
    $stopped = New-Object System.Collections.Generic.List[object]
    foreach ($root in $roots) {
        $stopped.Add((Stop-ProcessTree -Processes $Processes -RootPid ([int]$root.ProcessId) -Reason $Reason)) | Out-Null
    }
    return @($stopped.ToArray())
}

function Convert-CimCreationDate {
    param([object]$Value)

    if ($null -eq $Value) { return $null }
    if ($Value -is [datetime]) { return [datetime]$Value }

    $text = [string]$Value
    try {
        return [Management.ManagementDateTimeConverter]::ToDateTime($text)
    } catch {
        try {
            return [datetime]::Parse($text)
        } catch {
            return $null
        }
    }
}

function Get-ProcessAgeSeconds {
    param([object]$Process)

    $created = Convert-CimCreationDate -Value $Process.CreationDate
    if ($null -eq $created) { return [double]::PositiveInfinity }
    return [Math]::Max(0, ((Get-Date) - $created).TotalSeconds)
}

function Convert-ToComparablePath {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) { return "" }
    try {
        return ([IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables($Path))).TrimEnd("\").ToLowerInvariant()
    } catch {
        return ([Environment]::ExpandEnvironmentVariables($Path)).TrimEnd("\").ToLowerInvariant()
    }
}

function Get-CommandLineValue {
    param(
        [string]$CommandLine,
        [string]$Name
    )

    $pattern = "(?i)(?:^|\s)-" + [regex]::Escape($Name) + "\s+(`"([^`"]+)`"|'([^']+)'|(\S+))"
    $match = [regex]::Match([string]$CommandLine, $pattern)
    if (-not $match.Success) { return "" }
    foreach ($index in @(2, 3, 4)) {
        if (-not [string]::IsNullOrWhiteSpace($match.Groups[$index].Value)) {
            return $match.Groups[$index].Value
        }
    }
    return ""
}

function Test-CommandLineSwitch {
    param(
        [string]$CommandLine,
        [string]$Name
    )

    return ([string]$CommandLine -match ("(?i)(?:^|\s)-" + [regex]::Escape($Name) + "(?:\s|$)"))
}

function Convert-ToNullableInt {
    param([string]$Value)

    $parsed = 0
    if ([int]::TryParse([string]$Value, [ref]$parsed)) {
        return $parsed
    }
    return $null
}

function Test-IsProcessDescendant {
    param(
        [object[]]$Processes,
        [int]$RootPid,
        [int]$CandidatePid
    )

    if ($CandidatePid -eq $RootPid) { return $true }
    $seen = New-Object System.Collections.Generic.HashSet[int]
    $current = $CandidatePid
    while ($current -gt 0 -and $seen.Add($current)) {
        $proc = $Processes | Where-Object { [int]$_.ProcessId -eq $current } | Select-Object -First 1
        if ($null -eq $proc) { return $false }
        $parent = [int]$proc.ParentProcessId
        if ($parent -eq $RootPid) { return $true }
        $current = $parent
    }
    return $false
}

function Test-ProcessMatchesSnapshot {
    param(
        [object]$Snapshot,
        [object]$Current
    )

    if ($null -eq $Snapshot -or $null -eq $Current) { return $false }
    if ([int]$Snapshot.ProcessId -ne [int]$Current.ProcessId) { return $false }
    if ([string]$Snapshot.CreationDate -ne [string]$Current.CreationDate) { return $false }
    return $true
}

function Test-AppServerProcess {
    param([object]$Process)

    return ([string]$Process.Name -ieq "codex.exe" -and
        [string]$Process.CommandLine -match "\bapp-server\b" -and
        [string]$Process.CommandLine -notmatch "--listen\s+stdio://")
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
        [string]$Reason,
        [string]$ExpectedRootKey = "",
        [switch]$AllowAppServerRoot
    )

    $ids = @(Get-DescendantIds -Processes $Processes -RootPid $RootPid)
    $ordered = @($ids | Where-Object { $_ -ne $RootPid } | Sort-Object -Descending)
    $ordered += $RootPid
    $rootSnapshot = $Processes | Where-Object { [int]$_.ProcessId -eq $RootPid } | Select-Object -First 1
    $details = [ordered]@{
        root_pid = $RootPid
        reason = $Reason
        expected_root_key = $ExpectedRootKey
        allow_app_server_root = [bool]$AllowAppServerRoot
        process_ids = $ordered
        dry_run = [bool]$DryRun
    }
    Write-Ledger -Action "stop_tree" -Details $details

    if ($DryRun) {
        return ,$details
    }

    foreach ($id in $ordered) {
        try {
            $currentProcesses = Get-ProcessTable
            $snapshot = $Processes | Where-Object { [int]$_.ProcessId -eq [int]$id } | Select-Object -First 1
            $current = $currentProcesses | Where-Object { [int]$_.ProcessId -eq [int]$id } | Select-Object -First 1
            $currentRoot = $currentProcesses | Where-Object { [int]$_.ProcessId -eq [int]$RootPid } | Select-Object -First 1
            $skipReason = $null

            if ($null -eq $current) {
                $skipReason = "already-exited"
            } elseif (-not (Test-ProcessMatchesSnapshot -Snapshot $snapshot -Current $current)) {
                $skipReason = "pid-identity-changed"
            } elseif ($id -eq $RootPid -and $null -ne $rootSnapshot -and -not (Test-ProcessMatchesSnapshot -Snapshot $rootSnapshot -Current $current)) {
                $skipReason = "root-identity-changed"
            } elseif ($id -ne $RootPid -and -not (Test-IsProcessDescendant -Processes $currentProcesses -RootPid $RootPid -CandidatePid ([int]$id))) {
                $skipReason = "no-longer-descendant"
            } elseif ($id -eq $RootPid -and -not [string]::IsNullOrWhiteSpace($ExpectedRootKey)) {
                $currentKey = Get-ManagedRootKey -Name ([string]$current.Name) -CommandLine ([string]$current.CommandLine)
                if ($currentKey -ne $ExpectedRootKey) {
                    $skipReason = "root-key-mismatch"
                }
            } elseif ($id -eq $RootPid -and $AllowAppServerRoot -and -not (Test-AppServerProcess -Process $current)) {
                $skipReason = "root-app-server-mismatch"
            }

            if ($null -ne $skipReason) {
                Write-Ledger -Action "stop_skip" -Details @{
                    process_id = [int]$id
                    root_pid = $RootPid
                    reason = $Reason
                    skip_reason = $skipReason
                }
                continue
            }
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
    $appServers = @(Get-CodexAppServers -Processes $processes | ForEach-Object {
        [pscustomobject]@{
            ProcessId = [int]$_.ProcessId
            ParentProcessId = [int]$_.ParentProcessId
            CreationDate = $_.CreationDate
            Name = [string]$_.Name
            CommandLine = [string]$_.CommandLine
        }
    })
    $watchers = @(Get-Watchers -Processes $processes)
    $appServer = if ($AppServerPid -gt 0) {
        $processes | Where-Object { $_.ProcessId -eq $AppServerPid } | Select-Object -First 1
    } else {
        Get-CodexAppServer -Processes $processes
    }

    if ($null -eq $appServer) {
        return ,([pscustomobject]@{
            app_server_pid = $null
            app_server_parent_pid = $null
            app_servers = $appServers
            watchers = $watchers
            chrome_extension_hosts = @(Get-ChromeExtensionHostProcesses -Processes $processes)
            managed_roots = @()
            managed_orphans = @()
            duplicate_keys = @()
        })
    }

    $roots = @(Get-ManagedRoots -Processes $processes -RootParentPid ([int]$appServer.ProcessId))
    $orphans = @(Get-ManagedOrphans -Processes $processes -RootParentPid ([int]$appServer.ProcessId))
    $duplicates = @($roots | Group-Object Key | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
    return ,([pscustomobject]@{
        app_server_pid = [int]$appServer.ProcessId
        app_server_parent_pid = [int]$appServer.ParentProcessId
        app_server_command = [string]$appServer.CommandLine
        app_servers = $appServers
        watchers = $watchers
        chrome_extension_hosts = @(Get-ChromeExtensionHostProcesses -Processes $processes)
        managed_roots = @($roots | Sort-Object Key, CreationDate)
        managed_orphans = @($orphans | Sort-Object Key, CreationDate)
        duplicate_keys = $duplicates
    })
}

function Invoke-CleanupStale {
    param(
        [int]$AppServerPid,
        [string[]]$OnlyKeys = @()
    )

    $processes = Get-ProcessTable
    $status = Get-Status -AppServerPid $AppServerPid
    if ($null -eq $status.app_server_pid) {
        return ,([pscustomobject]@{ app_server_pid = $null; stopped = @(); note = "app-server not found" })
    }

    $appServerPidValue = [int](@($status.app_server_pid)[0])
    $roots = @(Get-ManagedRoots -Processes $processes -RootParentPid $appServerPidValue)
    $stopped = New-Object System.Collections.Generic.List[object]
    foreach ($orphanStop in @(Stop-ManagedOrphans -Processes $processes -AppServerPid $appServerPidValue -Reason "orphan-managed-process")) {
        $stopped.Add($orphanStop) | Out-Null
    }
    foreach ($group in @($roots | Group-Object Key)) {
        if ($OnlyKeys.Count -gt 0 -and $group.Name -notin $OnlyKeys) {
            continue
        }
        $keep = @($group.Group | Sort-Object CreationDate -Descending | Select-Object -First 1)[0]
        foreach ($stale in @($group.Group | Where-Object { $_.ProcessId -ne $keep.ProcessId })) {
            $stopped.Add((Stop-ProcessTree -Processes $processes -RootPid ([int]$stale.ProcessId) -Reason ("stale-" + $group.Name) -ExpectedRootKey $group.Name)) | Out-Null
        }
    }

    $statusAfter = Get-Status -AppServerPid $appServerPidValue
    return ,([pscustomobject]@{
        app_server_pid = $appServerPidValue
        stopped = @($stopped.ToArray())
        status_after = $statusAfter
    })
}

function Invoke-CleanupAll {
    param(
        [int]$AppServerPid,
        [int[]]$KnownRootPids = @()
    )

    $processes = Get-ProcessTable
    $rootPids = New-Object System.Collections.Generic.HashSet[int]

    foreach ($knownRootPid in $KnownRootPids) {
        $null = $rootPids.Add([int]$knownRootPid)
    }

    if ($AppServerPid -gt 0) {
        foreach ($root in @(Get-ManagedRoots -Processes $processes -RootParentPid $AppServerPid)) {
            $null = $rootPids.Add([int]$root.ProcessId)
        }
    }

    $stopped = New-Object System.Collections.Generic.List[object]
    $appServerAlive = $AppServerPid -gt 0 -and @($processes | Where-Object { $_.ProcessId -eq $AppServerPid }).Count -gt 0
    if ($appServerAlive) {
        foreach ($orphanStop in @(Stop-ManagedOrphans -Processes $processes -AppServerPid $AppServerPid -Reason "app-server-exit-orphan-managed-process")) {
            $stopped.Add($orphanStop) | Out-Null
        }
    }
    foreach ($rootPid in @($rootPids)) {
        if (@($processes | Where-Object { $_.ProcessId -eq $rootPid -or $_.ParentProcessId -eq $rootPid }).Count -gt 0) {
            $stopped.Add((Stop-ProcessTree -Processes $processes -RootPid $rootPid -Reason "app-server-exit")) | Out-Null
        }
    }

    return ,([pscustomobject]@{
        app_server_pid = $AppServerPid
        stopped = @($stopped.ToArray())
    })
}

function Invoke-Watch {
    param([int]$AppServerPid)

    $initialProcesses = Get-ProcessTable
    if ($AppServerPid -le 0) {
        $appServer = Get-CodexAppServer -Processes $initialProcesses
        if ($null -eq $appServer) {
            throw "Codex app-server not found."
        }
        $AppServerPid = [int]$appServer.ProcessId
    } else {
        $appServer = $initialProcesses | Where-Object { $_.ProcessId -eq $AppServerPid } | Select-Object -First 1
        if ($null -eq $appServer) {
            throw "Codex app-server not found: $AppServerPid"
        }
    }

    $ownerPid = [int]$appServer.ParentProcessId
    $known = New-Object System.Collections.Generic.HashSet[int]
    $duplicateSignatures = @{}
    Write-Ledger -Action "watch_start" -Details @{
        app_server_pid = $AppServerPid
        app_server_parent_pid = $ownerPid
        poll_seconds = $PollSeconds
        stop_app_server_on_owner_exit = [bool]$StopAppServerOnOwnerExit
        duplicate_grace_seconds = $DuplicateGraceSeconds
        duplicate_confirmations = $DuplicateConfirmations
    }

    while ($true) {
        $processes = Get-ProcessTable
        $parentAlive = @($processes | Where-Object { $_.ProcessId -eq $AppServerPid }).Count -gt 0
        $ownerAlive = (-not $StopAppServerOnOwnerExit) -or $ownerPid -le 0 -or @($processes | Where-Object { $_.ProcessId -eq $ownerPid }).Count -gt 0

        if (-not $parentAlive) {
            $result = Invoke-CleanupAll -AppServerPid $AppServerPid -KnownRootPids @($known)
            $chromeStopped = Stop-ChromeExtensionHosts -Processes $processes -Reason "app-server-exit-chrome-extension-host"
            $result | Add-Member -NotePropertyName chrome_extension_hosts_stopped -NotePropertyValue @($chromeStopped) -Force
            Write-Ledger -Action "watch_cleanup_complete" -Details $result
            return $result
        }

        if (-not $ownerAlive) {
            $stopped = Stop-ProcessTree -Processes $processes -RootPid $AppServerPid -Reason "app-server-owner-exit" -AllowAppServerRoot
            $chromeStopped = Stop-ChromeExtensionHosts -Processes $processes -Reason "app-server-owner-exit-chrome-extension-host"
            $result = [pscustomobject]@{
                app_server_pid = $AppServerPid
                app_server_parent_pid = $ownerPid
                stopped = @($stopped)
                chrome_extension_hosts_stopped = @($chromeStopped)
            }
            Write-Ledger -Action "watch_owner_exit_cleanup_complete" -Details $result
            return $result
        }

        $roots = @(Get-ManagedRoots -Processes $processes -RootParentPid $AppServerPid)
        $orphanStops = @(Stop-ManagedOrphans -Processes $processes -AppServerPid $AppServerPid -Reason "watch-orphan-managed-process")
        if ($orphanStops.Count -gt 0) {
            Write-Ledger -Action "watch_cleanup_orphans" -Details @{
                app_server_pid = $AppServerPid
                stopped = $orphanStops
            }
            $processes = Get-ProcessTable
            $roots = @(Get-ManagedRoots -Processes $processes -RootParentPid $AppServerPid)
        }
        foreach ($root in $roots) {
            $null = $known.Add([int]$root.ProcessId)
        }

        $groups = @($roots | Group-Object Key | Where-Object { $_.Count -gt 1 })
        $currentDuplicateKeys = @($groups | ForEach-Object { $_.Name })
        foreach ($key in @($duplicateSignatures.Keys)) {
            if ($key -notin $currentDuplicateKeys) {
                $duplicateSignatures.Remove($key)
            }
        }

        $confirmedDuplicateKeys = New-Object System.Collections.Generic.List[string]
        foreach ($group in $groups) {
            $staleRoots = @($group.Group | Sort-Object CreationDate -Descending | Select-Object -Skip 1)
            $stalePids = @($staleRoots | ForEach-Object { [string]$_.ProcessId })
            $signature = ($stalePids | Sort-Object) -join ","
            $oldEnough = (@($staleRoots | Where-Object { (Get-ProcessAgeSeconds -Process $_) -lt $DuplicateGraceSeconds }).Count -eq 0)
            if ($duplicateSignatures.ContainsKey($group.Name) -and
                [string]$duplicateSignatures[$group.Name].signature -eq $signature) {
                $duplicateSignatures[$group.Name].count = [int]$duplicateSignatures[$group.Name].count + 1
            } else {
                $duplicateSignatures[$group.Name] = [pscustomobject]@{
                    signature = $signature
                    count = 1
                    first_seen_utc = (Get-Date).ToUniversalTime().ToString("o")
                }
            }

            if ($oldEnough -and [int]$duplicateSignatures[$group.Name].count -ge $DuplicateConfirmations) {
                $confirmedDuplicateKeys.Add([string]$group.Name) | Out-Null
            } else {
                Write-Ledger -Action "watch_duplicate_candidate" -Details @{
                    app_server_pid = $AppServerPid
                    duplicate_key = [string]$group.Name
                    stale_pids = $stalePids
                    confirmation_count = [int]$duplicateSignatures[$group.Name].count
                    old_enough = [bool]$oldEnough
                    duplicate_grace_seconds = $DuplicateGraceSeconds
                }
            }
        }

        if ($confirmedDuplicateKeys.Count -gt 0) {
            $result = Invoke-CleanupStale -AppServerPid $AppServerPid -OnlyKeys @($confirmedDuplicateKeys.ToArray())
            Write-Ledger -Action "watch_cleanup_stale" -Details @{
                duplicate_keys = @($confirmedDuplicateKeys.ToArray())
                cleanup = $result
            }
            foreach ($key in @($confirmedDuplicateKeys.ToArray())) {
                $duplicateSignatures.Remove($key)
            }
        }

        Start-Sleep -Seconds $PollSeconds
    }
}

function Get-PwshPath {
    $candidates = @()
    $candidates += @(Get-Command pwsh.exe -All -ErrorAction SilentlyContinue |
        Where-Object { $_.Source -and $_.Source -notmatch "(?i)\\WindowsApps\\" } |
        ForEach-Object { $_.Source })
    $candidates += "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe"
    $candidates += "powershell.exe"

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

function Join-CommandLine {
    param([string[]]$Arguments)

    ($Arguments | ForEach-Object {
        if ($_ -match '[\s"]') {
            '"' + ($_ -replace '"', '\"') + '"'
        } else {
            $_
        }
    }) -join " "
}

function Test-WatcherRunning {
    param(
        [object[]]$Processes,
        [string]$ScriptPath,
        [int]$AppServerPid,
        [string]$RequiredCodexHome,
        [int]$RequiredPollSeconds,
        [int]$RequiredDuplicateGraceSeconds,
        [int]$RequiredDuplicateConfirmations,
        [bool]$RequireStopAppServerOnOwnerExit
    )

    $requiredScript = Convert-ToComparablePath -Path $ScriptPath
    $requiredHome = Convert-ToComparablePath -Path $RequiredCodexHome
    @($Processes | Where-Object {
        $watchParentPid = Convert-ToNullableInt -Value (Get-CommandLineValue -CommandLine ([string]$_.CommandLine) -Name "ParentPid")
        $watchPollSeconds = Convert-ToNullableInt -Value (Get-CommandLineValue -CommandLine ([string]$_.CommandLine) -Name "PollSeconds")
        $watchDuplicateGraceSeconds = Convert-ToNullableInt -Value (Get-CommandLineValue -CommandLine ([string]$_.CommandLine) -Name "DuplicateGraceSeconds")
        $watchDuplicateConfirmations = Convert-ToNullableInt -Value (Get-CommandLineValue -CommandLine ([string]$_.CommandLine) -Name "DuplicateConfirmations")
        [int]$_.ProcessId -ne [int]$PID -and
            [string]$_.Name -match "^(pwsh|powershell)\.exe$" -and
            [string]$_.CommandLine -match "codex-runtime-process-cleanup\.ps1" -and
            [string]$_.CommandLine -match "\s-Mode\s+watch\b" -and
            $watchParentPid -eq [int]$AppServerPid -and
            (Convert-ToComparablePath -Path (Get-CommandLineValue -CommandLine ([string]$_.CommandLine) -Name "File")) -eq $requiredScript -and
            (Convert-ToComparablePath -Path (Get-CommandLineValue -CommandLine ([string]$_.CommandLine) -Name "CodexHome")) -eq $requiredHome -and
            $watchPollSeconds -eq [int]$RequiredPollSeconds -and
            $watchDuplicateGraceSeconds -eq [int]$RequiredDuplicateGraceSeconds -and
            $watchDuplicateConfirmations -eq [int]$RequiredDuplicateConfirmations -and
            ((-not $RequireStopAppServerOnOwnerExit) -or (Test-CommandLineSwitch -CommandLine ([string]$_.CommandLine) -Name "StopAppServerOnOwnerExit"))
    }).Count -gt 0
}

function Get-Watchers {
    param([object[]]$Processes)

    @($Processes | Where-Object {
        [string]$_.Name -match "^(pwsh|powershell)\.exe$" -and
            [string]$_.CommandLine -match "codex-runtime-process-cleanup\.ps1" -and
            [string]$_.CommandLine -match "\s-Mode\s+watch\b"
    } | ForEach-Object {
        $parentPid = $null
        if ([string]$_.CommandLine -match "\s-ParentPid\s+([0-9]+)\b") {
            $parentPid = [int]$Matches[1]
        }
        $poll = Get-CommandLineValue -CommandLine ([string]$_.CommandLine) -Name "PollSeconds"
        $duplicateGrace = Get-CommandLineValue -CommandLine ([string]$_.CommandLine) -Name "DuplicateGraceSeconds"
        $duplicateConfirmations = Get-CommandLineValue -CommandLine ([string]$_.CommandLine) -Name "DuplicateConfirmations"
        [pscustomobject]@{
            ProcessId = [int]$_.ProcessId
            ParentProcessId = [int]$_.ParentProcessId
            WatchedAppServerPid = $parentPid
            ScriptPath = Get-CommandLineValue -CommandLine ([string]$_.CommandLine) -Name "File"
            CodexHome = Get-CommandLineValue -CommandLine ([string]$_.CommandLine) -Name "CodexHome"
            PollSeconds = $(if ([string]::IsNullOrWhiteSpace($poll)) { $null } else { [int]$poll })
            DuplicateGraceSeconds = $(if ([string]::IsNullOrWhiteSpace($duplicateGrace)) { $null } else { [int]$duplicateGrace })
            DuplicateConfirmations = $(if ([string]::IsNullOrWhiteSpace($duplicateConfirmations)) { $null } else { [int]$duplicateConfirmations })
            StopAppServerOnOwnerExit = Test-CommandLineSwitch -CommandLine ([string]$_.CommandLine) -Name "StopAppServerOnOwnerExit"
            CreationDate = $_.CreationDate
            Name = [string]$_.Name
            CommandLine = [string]$_.CommandLine
        }
    })
}

function Invoke-EnsureWatch {
    param([int]$AppServerPid)

    $cleanupResult = if ($CleanupStaleOnEnsure) {
        Invoke-CleanupStale -AppServerPid $AppServerPid
    } else {
        [pscustomobject]@{
            skipped = $true
            reason = "ensure-watch does not stop live runtimes by default"
        }
    }
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
    $alreadyRunning = Test-WatcherRunning -Processes $processes -ScriptPath $scriptPath -AppServerPid $appServerPidValue -RequiredCodexHome $CodexHome -RequiredPollSeconds $PollSeconds -RequiredDuplicateGraceSeconds $DuplicateGraceSeconds -RequiredDuplicateConfirmations $DuplicateConfirmations -RequireStopAppServerOnOwnerExit ([bool]$StopAppServerOnOwnerExit)
    $watchersForApp = @(Get-Watchers -Processes $processes | Where-Object { $_.WatchedAppServerPid -eq $appServerPidValue })
    $incompatibleWatchers = @($watchersForApp | Where-Object {
        -not (Test-WatcherRunning -Processes @($_) -ScriptPath $scriptPath -AppServerPid $appServerPidValue -RequiredCodexHome $CodexHome -RequiredPollSeconds $PollSeconds -RequiredDuplicateGraceSeconds $DuplicateGraceSeconds -RequiredDuplicateConfirmations $DuplicateConfirmations -RequireStopAppServerOnOwnerExit ([bool]$StopAppServerOnOwnerExit))
    })
    foreach ($watcher in $incompatibleWatchers) {
        try {
            Stop-Process -Id ([int]$watcher.ProcessId) -Force -ErrorAction SilentlyContinue
            Write-Ledger -Action "stop_incompatible_watcher" -Details @{
                watcher_pid = [int]$watcher.ProcessId
                app_server_pid = $appServerPidValue
                required_script = $scriptPath
                required_codex_home = $CodexHome
                required_poll_seconds = $PollSeconds
                require_stop_app_server_on_owner_exit = [bool]$StopAppServerOnOwnerExit
            }
        } catch {
            Write-Ledger -Action "stop_incompatible_watcher_error" -Details @{
                watcher_pid = [int]$watcher.ProcessId
                error = $_.Exception.Message
            }
        }
    }
    if ($incompatibleWatchers.Count -gt 0) {
        $processes = Get-ProcessTable
        $alreadyRunning = Test-WatcherRunning -Processes $processes -ScriptPath $scriptPath -AppServerPid $appServerPidValue -RequiredCodexHome $CodexHome -RequiredPollSeconds $PollSeconds -RequiredDuplicateGraceSeconds $DuplicateGraceSeconds -RequiredDuplicateConfirmations $DuplicateConfirmations -RequireStopAppServerOnOwnerExit ([bool]$StopAppServerOnOwnerExit)
    }

    $watcherPid = $null
    if (-not $alreadyRunning -and -not $DryRun) {
        $stateDir = Join-Path $CodexHome "state"
        New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
        $outLog = Join-Path $stateDir ("runtime-process-watch-" + $appServerPidValue + ".out.log")
        $errLog = Join-Path $stateDir ("runtime-process-watch-" + $appServerPidValue + ".err.log")
        $pwsh = Get-PwshPath
        $arguments = @(
            "-NoProfile",
            "-ExecutionPolicy", "Bypass",
            "-File", $scriptPath,
            "-Mode", "watch",
            "-ParentPid", ([string]$appServerPidValue),
            "-PollSeconds", ([string]$PollSeconds),
            "-DuplicateGraceSeconds", ([string]$DuplicateGraceSeconds),
            "-DuplicateConfirmations", ([string]$DuplicateConfirmations),
            "-CodexHome", $CodexHome
        )
        if ($StopAppServerOnOwnerExit) {
            $arguments += "-StopAppServerOnOwnerExit"
        }
        $created = Start-Process -FilePath $pwsh -ArgumentList $arguments -WindowStyle Hidden -RedirectStandardOutput $outLog -RedirectStandardError $errLog -PassThru
        Start-Sleep -Milliseconds 500
        if ($created.HasExited) {
            $errorText = if (Test-Path -LiteralPath $errLog -PathType Leaf) {
                ((Get-Content -LiteralPath $errLog -Raw -ErrorAction SilentlyContinue) -replace "\s+", " ").Trim()
            } else {
                ""
            }
            throw ("Runtime cleanup watcher exited immediately. exit=" + $created.ExitCode + " stderr=" + $errorText)
        }
        $watcherPid = [int]$created.ProcessId
    }

    $result = [pscustomobject]@{
        app_server_pid = $appServerPidValue
        cleanup_stale = $cleanupResult
        watcher_already_running = [bool]$alreadyRunning
        watcher_started = [bool]((-not $alreadyRunning) -and (-not $DryRun))
        watcher_pid = $watcherPid
        incompatible_watcher_pids_stopped = @($incompatibleWatchers | ForEach-Object { [int]$_.ProcessId })
        stop_app_server_on_owner_exit = [bool]$StopAppServerOnOwnerExit
        duplicate_grace_seconds = $DuplicateGraceSeconds
        duplicate_confirmations = $DuplicateConfirmations
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
