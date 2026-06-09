param(
    [string]$Python = "python",
    [string]$Model = "gpt-5.4",
    [switch]$RunTurn
)

$ErrorActionPreference = "Stop"

function Add-Check {
    param(
        [System.Collections.Generic.List[object]]$Checks,
        [string]$Name,
        [string]$Status,
        [object]$Details
    )

    $Checks.Add([ordered]@{
        name = $Name
        status = $Status
        details = $Details
    }) | Out-Null
}

$checks = [System.Collections.Generic.List[object]]::new()

try {
    $pythonCommand = Get-Command $Python -ErrorAction Stop
    Add-Check $checks "python_resolution" "pass" ([ordered]@{
        source = $pythonCommand.Source
    })
} catch {
    Add-Check $checks "python_resolution" "fail" ([ordered]@{
        error = $_.Exception.Message
    })
    [ordered]@{ ok = $false; checks = $checks } | ConvertTo-Json -Depth 8
    exit 1
}

$packageScript = @'
import importlib.metadata as md
import json
import pathlib
import sys

names = ["openai-codex", "openai-codex-cli-bin", "openai", "openai-agents"]
out = {"python": sys.executable, "packages": {}}

for name in names:
    try:
        out["packages"][name] = md.version(name)
    except md.PackageNotFoundError:
        out["packages"][name] = None

try:
    import codex_cli_bin
    import openai_codex

    out["openai_codex_path"] = str(pathlib.Path(openai_codex.__file__).resolve())
    out["codex_cli_bin_path"] = str(pathlib.Path(codex_cli_bin.__file__).resolve())
except Exception as exc:
    out["import_error"] = type(exc).__name__ + ": " + str(exc)

print(json.dumps(out, sort_keys=True))
'@

try {
    $previousPackageScript = $env:CODEX_SDK_CHECK_PACKAGE_SCRIPT
    $env:CODEX_SDK_CHECK_PACKAGE_SCRIPT = $packageScript
    $packageInfo = (& $pythonCommand.Source -c "import os; exec(os.environ['CODEX_SDK_CHECK_PACKAGE_SCRIPT'])" | ConvertFrom-Json)
    $missing = @($packageInfo.packages.PSObject.Properties | Where-Object { $null -eq $_.Value } | ForEach-Object { $_.Name })
    Add-Check $checks "python_packages" ($(if ($missing.Count -eq 0 -and -not $packageInfo.import_error) { "pass" } else { "fail" })) ([ordered]@{
        python = $packageInfo.python
        packages = $packageInfo.packages
        openai_codex_path = $packageInfo.openai_codex_path
        codex_cli_bin_path = $packageInfo.codex_cli_bin_path
        missing = $missing
        import_error = $packageInfo.import_error
    })
} catch {
    Add-Check $checks "python_packages" "fail" ([ordered]@{
        error = $_.Exception.Message
    })
} finally {
    $env:CODEX_SDK_CHECK_PACKAGE_SCRIPT = $previousPackageScript
}

try {
    $codexCommands = @(Get-Command codex -All -ErrorAction Stop | ForEach-Object {
        [ordered]@{
            source = $_.Source
            command_type = $_.CommandType.ToString()
        }
    })
    $codexVersion = ((& codex --version 2>&1) | Out-String).Trim()
    Add-Check $checks "codex_command" "pass" ([ordered]@{
        commands = $codexCommands
        version = $codexVersion
    })
} catch {
    Add-Check $checks "codex_command" "fail" ([ordered]@{
        error = $_.Exception.Message
    })
}

$previousRunTurn = $env:CODEX_SDK_CHECK_RUN_TURN
$previousModel = $env:CODEX_SDK_CHECK_MODEL
$env:CODEX_SDK_CHECK_RUN_TURN = if ($RunTurn) { "1" } else { "0" }
$env:CODEX_SDK_CHECK_MODEL = $Model

$sdkScript = @'
import json
import os

from openai_codex import Codex, Sandbox


def plain(obj):
    if hasattr(obj, "model_dump"):
        return obj.model_dump(mode="json")
    if isinstance(obj, dict):
        return obj
    if hasattr(obj, "__dict__"):
        return dict(vars(obj))
    return {"repr": repr(obj)}


def model_items(data):
    if isinstance(data, dict):
        for key in ("models", "items", "data"):
            value = data.get(key)
            if isinstance(value, list):
                return value
    if isinstance(data, list):
        return data
    return []


with Codex() as codex:
    account = plain(codex.account())
    account_info = account.get("account") if isinstance(account, dict) else None
    if not isinstance(account_info, dict):
        account_info = {}

    models = plain(codex.models())
    items = model_items(models)
    sample = []
    for item in items[:5]:
        if isinstance(item, dict):
            sample.append(item.get("id") or item.get("name") or "<model>")
        else:
            sample.append(str(item))

    out = {
        "account": {
            "present": bool(account_info),
            "type": account_info.get("type"),
            "plan_type": account_info.get("plan_type"),
        },
        "requires_openai_auth": account.get("requires_openai_auth") if isinstance(account, dict) else None,
        "models": {
            "count": len(items),
            "sample": sample,
        },
        "turn": None,
    }

    if os.environ.get("CODEX_SDK_CHECK_RUN_TURN") == "1":
        thread = codex.thread_start(
            model=os.environ.get("CODEX_SDK_CHECK_MODEL") or None,
            sandbox=Sandbox.read_only,
        )
        result = thread.run("Reply exactly: SDK_READY")
        response = getattr(result, "final_response", "") or str(result)
        out["turn"] = {
            "ran": True,
            "response": response.strip()[:200],
        }
    else:
        out["turn"] = {"ran": False}

print(json.dumps(out, sort_keys=True))
'@

try {
    $previousSdkScript = $env:CODEX_SDK_CHECK_SCRIPT
    $env:CODEX_SDK_CHECK_SCRIPT = $sdkScript
    $sdkInfo = (& $pythonCommand.Source -c "import os; exec(os.environ['CODEX_SDK_CHECK_SCRIPT'])" | ConvertFrom-Json)
    $sdkPass = $sdkInfo.account.present -and $sdkInfo.models.count -gt 0
    if ($RunTurn) {
        $sdkPass = $sdkPass -and $sdkInfo.turn.ran -and $sdkInfo.turn.response -eq "SDK_READY"
    }
    Add-Check $checks "codex_sdk_runtime" ($(if ($sdkPass) { "pass" } else { "fail" })) $sdkInfo
} catch {
    Add-Check $checks "codex_sdk_runtime" "fail" ([ordered]@{
        error = $_.Exception.Message
    })
} finally {
    $env:CODEX_SDK_CHECK_SCRIPT = $previousSdkScript
    $env:CODEX_SDK_CHECK_RUN_TURN = $previousRunTurn
    $env:CODEX_SDK_CHECK_MODEL = $previousModel
}

$failed = @($checks | Where-Object { $_.status -ne "pass" })
$result = [ordered]@{
    ok = ($failed.Count -eq 0)
    checks = $checks
}

$result | ConvertTo-Json -Depth 12

if ($failed.Count -ne 0) {
    exit 1
}
