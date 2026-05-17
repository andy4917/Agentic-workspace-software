# 2026-05-18 Browser And Chrome Native Host Recovery

## Summary

Codex in-app Browser was usable through the official installed app bundle, but
Chrome extension-backed Browser Use was blocked because the Chrome native
messaging manifest pointed at a removed Codex Desktop package version.

## Root Cause

`%LOCALAPPDATA%\OpenAI\extension\com.openai.codexextension.json` contained a
`path` under:

```text
C:\Program Files\WindowsApps\OpenAI.Codex_26.513.3673.0_x64__2p2nqsd0c76g0\app\resources\plugins\openai-bundled\plugins\chrome\extension-host\windows\x64\extension-host.exe
```

The installed Codex package was:

```text
OpenAI.Codex_26.513.4821.0_x64__2p2nqsd0c76g0
```

The old manifest executable path did not exist. The current app bundle host did
exist. The HKCU native messaging registry key still pointed at the manifest JSON,
so registry-only checks were insufficient.

## Confirmed Mismatches

- Chrome helper checks reported the extension installed and enabled.
- Native host helper reported `correct=true` for name, registry path, and
  allowed origin.
- Direct executable check showed the manifest `path` was stale and missing.
- Before the manifest fix, Chrome backend discovery did not expose an
  `extension` backend.
- Loading `browser-client.mjs` from the legacy `browser-use` cache path failed
  native bridge trust. The official `browser` app bundle client was the trusted
  IAB route.

## Fix Applied

Backed up the manifest:

```text
C:\Users\anise\AppData\Local\OpenAI\extension\com.openai.codexextension.json.bak-20260518-023107
```

Updated only the JSON `path` field to:

```text
C:\Program Files\WindowsApps\OpenAI.Codex_26.513.4821.0_x64__2p2nqsd0c76g0\app\resources\plugins\openai-bundled\plugins\chrome\extension-host\windows\x64\extension-host.exe
```

No firewall, loopback exemption, browser policy, Chrome profile, or plugin cache
change was needed.

## Verification

- Manifest JSON parsed successfully.
- `Test-Path` for the manifest `path` returned true.
- `reg.exe query HKCU\Software\Google\Chrome\NativeMessagingHosts\com.openai.codexextension /ve`
  pointed at the same manifest JSON.
- Chrome backend discovery listed `type=extension` with profile metadata.
- In-app Browser `iab` opened both `http://127.0.0.1:5173/` and
  `http://localhost:5173/`, clicked the smoke button, and navigated to
  `/clicked` with title `Codex Browser E2E Clicked`.
- Chrome `extension` opened a public page and both local URLs, clicked the smoke
  button, and navigated to `/clicked` with title `Codex Browser E2E Clicked`.
- Temporary smoke server on port `5173` was closed after verification.

## Follow-Up Repair Helper Cleanup

The SessionStart hook later surfaced a separate helper-script issue:
`Chrome extension origin repair failed: File "<stdin>", line 1`.

Root cause: the repair helper's app-server probe was executed from inside a hook
process that already consumed hook JSON from stdin. The Python fallback used
`python -`, so it could read hook stdin instead of the app-server probe code.
Earlier variants of the same helper also assumed Windows PowerShell supported
`ProcessStartInfo.ArgumentList` and stream encoding properties that are only
reliable in newer PowerShell/.NET runtimes.

Fix: `maintenance\scripts\ensure-chrome-extension-origin.ps1` now writes the
Python app-server probe to a temporary `.py` file before execution, keeps the
line-JSON app-server request shape (`id`, `method`, `params`), and uses guarded
PowerShell stream handling for fallback code. The temporary probe file is
removed after the check.

Verification:

- `ensure-chrome-extension-origin.ps1 -NoNodeCheck` exits `0` and reports
  `browser@openai-bundled is installed and enabled`; when the legacy
  `browser-use-bundled-plugin-auto-install-disabled` flag is stale, it patches
  that flag back to `false`.
- A synthetic `SessionStart` hook exits `0` and no longer includes Chrome
  origin repair failure text.
- PowerShell AST parsing for the helper passes.
- `codex_agent_harness.py doctor --tier stress --json` exits `0`; all harness
  files are now at or below the 800-line maintenance limit after the Stop final
  evidence checks were split into `hooks\lib\lightweight-codex-final-gates.ps1`.
- `codex_agent_harness.py eval --eval-id hook-policy-smoke` exits `0`.
- Memento log scanning now ignores the expected transient PostgreSQL startup
  line `FATAL:  the database system is starting up` while still reporting real
  post-start risk patterns.
- The final self-test mismatch was in the temporary harness fixture, not the
  live hook path: the fixture did not create the current Vowline compatibility
  mirror or AGENTS marker, so `hook_subagent_vowline` failed only inside
  self-test. The fixture now creates both before running `doctor_data(root)`.
- `codex_agent_harness.py doctor --tier full --json`, `benchmark`, and
  `verify` all exit `0`; `verification.latest.md` reports pass for doctor,
  Memento MCP status, Python compile, self-test, hook AST parse, and audit.

## Browserify Decision

`browserify/browserify` is not required for Codex Browser or Chrome Browser Use.
It is a browser-side JavaScript bundler for CommonJS-style `require()` graphs.
The Codex Browser path depends on the bundled `browser-client.mjs`, the Codex
app-server plugin state, and the Chrome native messaging bridge when using the
Chrome extension backend.

Do not install Browserify to fix Codex Browser or Chrome Browser Use unless a
separate application project explicitly needs CommonJS browser bundling.
Do not use Playwright or Puppeteer as a fallback for this recovery path.
The tracked patched Chrome skill was also updated to remove the
`Prefer Playwright` guidance; it now treats `tab.playwright` references as an
in-skill browser-client API shape only and forbids standalone Playwright or
Puppeteer packages for this recovery path.

Current runtime notes:

- `agent.browsers.list()` exposes both `type=extension` for Chrome and
  `type=iab` for the Codex in-app Browser.
- Chrome extension backend selection succeeds, `tabs.list()` responds, and a
  native `tabs.new()` + `goto("https://example.com/")` smoke returns title
  `Example Domain`; the smoke tab was closed.
- 2026-05-18 PM follow-up: the active Codex session listed two native backends
  and selected both `type=iab` and `type=extension` successfully through the
  official `browser-client.mjs` runtime. This supersedes the earlier IAB pane
  activation concern for the current window.
- No Playwright or Puppeteer fallback was used for these checks.

## Agent Maintenance Playbook

When Chrome Browser Use disappears or cannot connect after a Codex app update:

1. Check the installed app package:

   ```powershell
   Get-AppxPackage *Codex* |
     Select-Object Name, Version, PackageFamilyName, PackageFullName, InstallLocation
   ```

2. Parse the native host manifest and verify the executable path:

   ```powershell
   $manifest = "$env:LOCALAPPDATA\OpenAI\extension\com.openai.codexextension.json"
   $m = Get-Content -Raw -LiteralPath $manifest | ConvertFrom-Json
   $m.path
   Test-Path -LiteralPath $m.path
   ```

3. Verify the registry points at the manifest:

   ```powershell
   reg.exe query "HKCU\Software\Google\Chrome\NativeMessagingHosts\com.openai.codexextension" /ve
   ```

4. If the manifest path is stale, back up the JSON before editing and update
   only `path` to the current installed app bundle's `extension-host.exe`.

5. Re-test actual Codex backends. Do not treat extension-installed checks,
   registry-only checks, or project-level browser automation as completion.

## Residual Risk

Future Codex Desktop updates may again leave the native host manifest pinned to
an older package. If Chrome backend discovery fails while the extension appears
installed, the manifest executable path is the first check.
