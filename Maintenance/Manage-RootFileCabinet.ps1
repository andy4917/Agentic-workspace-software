[CmdletBinding()]
param(
    [switch]$Refresh
)

$ErrorActionPreference = 'Stop'

$CodexRoot = Split-Path -Parent $PSScriptRoot
$CabinetRoot = Join-Path $PSScriptRoot 'file-cabinet'
$RootFilesDir = Join-Path $CabinetRoot 'root-files'

$ProtectedNames = @(
    'auth.json',
    'cap_sid',
    'installation_id'
)

$ProtectedPatterns = @(
    '*.sqlite',
    '*.sqlite-shm',
    '*.sqlite-wal',
    'session_index.jsonl',
    'models_cache.json',
    'config.toml',
    '.codex-global-state.json',
    '.codex-global-state.json.bak'
)

$SnapshotNames = @(
    '.gitattributes',
    '.gitignore',
    '.personality_migration',
    'AGENTS.md',
    'agent.md',
    'CHANGELOG.md',
    'INVENTORY.md',
    'MANIFEST.json',
    'README.md',
    'ROOT_MAP.json'
)

function Convert-ToSafeFolderName {
    param([Parameter(Mandatory)][string]$Name)

    $safe = $Name -replace '[^A-Za-z0-9._-]', '_'
    if ($safe.StartsWith('.')) {
        return "_$($safe.TrimStart('.'))"
    }
    return $safe
}

function Test-ProtectedRootFile {
    param([Parameter(Mandatory)][System.IO.FileInfo]$File)

    if ($ProtectedNames -contains $File.Name) {
        return $true
    }

    foreach ($pattern in $ProtectedPatterns) {
        if ($File.Name -like $pattern) {
            return $true
        }
    }

    return $false
}

New-Item -ItemType Directory -Force -Path $RootFilesDir | Out-Null

$files = Get-ChildItem -LiteralPath $CodexRoot -Force -File |
    Sort-Object Name

$indexRows = @()

foreach ($file in $files) {
    $safeName = Convert-ToSafeFolderName -Name $file.Name
    $entryDir = Join-Path $RootFilesDir $safeName
    $snapshotDir = Join-Path $entryDir 'snapshot'
    $isProtected = Test-ProtectedRootFile -File $file
    $shouldSnapshot = (-not $isProtected) -and ($SnapshotNames -contains $file.Name)

    New-Item -ItemType Directory -Force -Path $entryDir | Out-Null

    if ($shouldSnapshot) {
        New-Item -ItemType Directory -Force -Path $snapshotDir | Out-Null
        Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $snapshotDir $file.Name) -Force
    }

    $relativeSource = "%USERPROFILE%\.codex\$($file.Name)"
    $status = if ($isProtected) { 'protected-live-file' } elseif ($shouldSnapshot) { 'snapshot-managed' } else { 'indexed-only' }
    $snapshotText = if ($shouldSnapshot) { "snapshot/$($file.Name)" } else { 'none' }
    $sizeKb = [math]::Round($file.Length / 1KB, 2)

    $entryReadme = @"
# $($file.Name)

- Source: ``$relativeSource``
- Status: ``$status``
- Size: $sizeKb KiB
- Last modified: $($file.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss zzz'))
- Snapshot: ``$snapshotText``

Protected or live runtime files stay in their original root location. This folder is for management, inventory, and safe snapshots only.
"@

    Set-Content -LiteralPath (Join-Path $entryDir 'README.md') -Value $entryReadme -Encoding utf8

    $indexRows += [pscustomobject]@{
        Name = $file.Name
        Folder = "root-files/$safeName"
        Status = $status
        SizeBytes = $file.Length
        LastWriteTime = $file.LastWriteTime.ToString('o')
        Snapshot = $snapshotText
    }
}

$indexJson = @{
    root = '%USERPROFILE%\.codex'
    cabinet = '%USERPROFILE%\.codex\Maintenance\file-cabinet'
    generated_at = (Get-Date).ToString('o')
    policy = @{
        move_root_files = $false
        copy_protected_files = $false
        snapshots_are_for_safe_static_documents = $true
    }
    files = $indexRows
} | ConvertTo-Json -Depth 5

Set-Content -LiteralPath (Join-Path $CabinetRoot 'root-files.index.json') -Value $indexJson -Encoding utf8

$readme = @"
# Root File Cabinet

This cabinet keeps root-level ``%USERPROFILE%\.codex`` files manageable without moving live Codex files away from the paths the app expects.

## Layout

- ``root-files/``: one folder per root-level file.
- ``root-files/<file>/README.md``: source path, status, size, modified time, and snapshot status.
- ``root-files/<file>/snapshot/``: copies only for safe static documents and manifests.
- ``root-files.index.json``: machine-readable inventory for all root-level files.

## Safety Policy

- Live runtime, database, session, cache, and credential files remain in place.
- ``auth.json`` and similar credential/session files are never copied by this script.
- SQLite, WAL, SHM, state, cache, and session index files are indexed only.
- Re-run ``Maintenance/Manage-RootFileCabinet.ps1 -Refresh`` to refresh folders and safe snapshots.
"@

Set-Content -LiteralPath (Join-Path $CabinetRoot 'README.md') -Value $readme -Encoding utf8

Write-Host "Root file cabinet refreshed: $CabinetRoot"
Write-Host "Indexed files: $($indexRows.Count)"
