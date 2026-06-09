# Codex SDK Runtime

This runbook records the local setup for the official Codex SDK.

## Official Surface

- `https://developers.openai.com/codex/sdk` documents two Codex SDKs:
  `@openai/codex-sdk` for TypeScript and `openai-codex` for Python.
- The Python Codex SDK controls the local Codex app-server over JSON-RPC and
  published SDK builds include a pinned Codex CLI runtime dependency.
- The Python package metadata for `openai-codex` says existing Codex
  authentication is reused automatically when available, with explicit ChatGPT
  browser login, ChatGPT device-code login, and API-key login also exposed.
- This is different from the general `openai` Python API SDK. The OpenAI API
  SDK still uses API credentials such as `OPENAI_API_KEY` for direct API calls.

## Local Setup

As of 2026-06-03, this workstation has:

- `openai-codex==0.1.0b2`
- `openai-codex-cli-bin==0.132.0`
- `openai==2.36.0`
- `openai-agents==0.17.2`

The installed `openai-codex-cli-bin` runtime stays inside Python
`site-packages`; it does not install a new PATH `codex` command. The active
shell `codex` command remains the workstation shim under
`%USERPROFILE%\.codex\toolchains\shims`, then the Codex app bundle under
`%ProgramFiles%\WindowsApps`.

Do not uninstall the Codex app-bundled CLI just to use the Python Codex SDK.
Use the SDK default pinned runtime unless a task explicitly needs a specific
local app-server binary. Pass `AppServerConfig(codex_bin=...)` only for that
intentional override.

## Validation

Use the managed-source check:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\maintenance\scripts\check-codex-sdk.ps1
```

That check verifies package import, package versions, current `codex` command
resolution, SDK account read, and SDK model list. It redacts account
identifiers.

To run a real minimal Codex turn through the SDK:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\maintenance\scripts\check-codex-sdk.ps1 -RunTurn
```

`-RunTurn` starts a read-only SDK thread and asks it to return `SDK_READY`.

## Usage Pattern

```python
from openai_codex import Codex, Sandbox

with Codex() as codex:
    thread = codex.thread_start(
        model="gpt-5.4",
        sandbox=Sandbox.workspace_write,
    )
    result = thread.run("Make the requested change.")
    print(result.final_response)
```

Use `Sandbox.read_only` for review or inspection turns. Use
`Sandbox.workspace_write` only when the SDK-run Codex thread is expected to edit
workspace files.

## Secret Boundary

Do not store API keys in this repository or in scaffold config fragments. If a
task needs direct OpenAI API calls rather than Codex ChatGPT-managed auth, set
`OPENAI_API_KEY` through the user's normal secret-management route and keep it
out of logs.
