function Update-CodexNativePath {
    $candidatePaths = @(
        "C:\Program Files\nodejs",
        "C:\Python314",
        "C:\Python314\Scripts",
        "$env:LOCALAPPDATA\Programs\Python\Python312",
        "$env:LOCALAPPDATA\Programs\Python\Python312\Scripts",
        "C:\Program Files\Git\cmd",
        "$env:USERPROFILE\.local\bin",
        "$env:USERPROFILE\AppData\Roaming\npm",
        "$env:USERPROFILE\.cargo\bin",
        "$env:LOCALAPPDATA\Microsoft\WinGet\Links",
        "$env:LOCALAPPDATA\PowerToys",
        "C:\Program Files\CMake\bin"
    )

    $existing = $env:Path -split ';' | Where-Object { $_ }
    $orderedPaths = [array]$candidatePaths.Clone()
    [array]::Reverse($orderedPaths)
    foreach ($path in $orderedPaths) {
        if ((Test-Path -LiteralPath $path) -and ($existing -notcontains $path)) {
            $env:Path = "$path;$env:Path"
        }
    }
}

function Enter-WindowsNativeDev {
    Update-CodexNativePath

    $vswhereCandidates = @(
        "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe",
        "$env:ProgramFiles\Microsoft Visual Studio\Installer\vswhere.exe"
    )
    $vswhere = $vswhereCandidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $vswhere) {
        throw "vswhere.exe was not found. Install Visual Studio Build Tools before entering the native developer environment."
    }

    $installPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if (-not $installPath) {
        $installPath = & $vswhere -latest -products * -property installationPath
    }

    $vsDevCmd = Join-Path $installPath 'Common7\Tools\VsDevCmd.bat'
    if (-not (Test-Path -LiteralPath $vsDevCmd)) {
        throw "VsDevCmd.bat was not found under $installPath."
    }

    $envLines = & cmd.exe @('/d', '/c', 'call', $vsDevCmd, '-arch=x64', '-host_arch=x64', '>', 'nul', '&&', 'set')
    if ($LASTEXITCODE -ne 0) {
        throw "VsDevCmd.bat failed with exit code $LASTEXITCODE."
    }
    foreach ($line in $envLines) {
        $index = $line.IndexOf('=')
        if ($index -gt 0) {
            $name = $line.Substring(0, $index)
            $value = $line.Substring($index + 1)
            Set-Item -Path "Env:$name" -Value $value
        }
    }

    Update-CodexNativePath
    Write-Host "Windows native developer environment is ready. cl, link, cmake, ninja, cargo, node, python helpers are on PATH."
}

Set-Alias -Name cdev -Value Enter-WindowsNativeDev -Scope Global
Update-CodexNativePath
