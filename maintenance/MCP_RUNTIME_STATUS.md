# MCP Runtime Status

Updated for the 2026-05-16 Codex app update clean pass.

## Current Finding

MCP tool loading is working in the current Codex Desktop session after tool
discovery. The earlier failure was not a broken package install. The confirmed
causes were path/filter fragility and already-running session tool schemas that
had not refreshed.

The 2026-05-15 refresh excludes `memento` from optimization changes. It keeps
Memento as support-only memory and updates the active-use posture for the other
configured MCPs. `codex.cmd` now exists in `%USERPROFILE%\.codex\toolchains\shims`
so MCP inventory commands can use the same explicit wrapper pattern as the
other Codex-owned command-line tools.

`node_repl` is a separate Codex Desktop bundled execution tool, not a user
`[mcp_servers.*]` entry in `config.toml`. It is surfaced through tool discovery
as the `mcp__node_repl__` namespace and runs from the Codex app bundle
(`%LOCALAPPDATA%\OpenAI\Codex\bin\node_repl.exe` plus the bundled Node runtime).

## Global MCP Scope

The configured MCP servers live in `%USERPROFILE%\.codex\config.toml`, so their
intended scope is user-global across trusted Codex workspaces. Do not duplicate
these servers in project-local config unless a repository needs a genuinely
different command, credential source, or policy boundary.

## Current MCP Intent

- `openaiDeveloperDocs`: global, streamable HTTP. Use for current OpenAI API,
  model, Codex, plugin, and app-server documentation. Search first, then fetch
  the exact doc page before quoting or relying on details.
- `context7`: global, stdio via `npx -y @upstash/context7-mcp`, with
  `CONTEXT7_API_KEY`. The configured command is the local-chain wrapper
  `%USERPROFILE%\.codex\toolchains\shims\npx.cmd`, which prepends the official
  Codex bundled Node runtime before invoking the local npm package command. Use
  for current third-party library, framework, SDK, CLI, and cloud-service
  documentation. Resolve the library id before querying.
- `shadcn`: global, stdio via
  `%USERPROFILE%\.codex\toolchains\shims\npx.cmd -y shadcn@latest mcp`. Use for
  frontend work that needs shadcn/ui registry browsing, searching, component
  docs, or install planning. It is enabled in global config for future frontend
  sessions. Active-session usability still requires tool injection and a safe
  read-only MCP call after the app/session reloads. If MCP tools are not
  injected, use the shadcn CLI fallback through the same `npx.cmd` wrapper and
  report `CLI_FALLBACK`.
- `sequential_thinking`: global, stdio via
  `%USERPROFILE%\.codex\toolchains\shims\npx.cmd -y
  @modelcontextprotocol/server-sequential-thinking`. Use only for ambiguous
  multi-step planning/debugging where revision or branching adds value.
- `windows_powershell`: global, stdio via
  `maintenance\scripts\start-windows-powershell-mcp.cmd`, which prepends
  `%USERPROFILE%\.codex\toolchains\shims` and
  `%LOCALAPPDATA%\OpenAI\Codex\bin` before launching the installed
  `PowerShell.MCP.Proxy.exe`. Use for persistent PowerShell diagnostics and
  Windows command execution when its stateful console is useful. It exposes
  `start_console`, `get_current_location`, `invoke_expression`, and
  `wait_for_completion`; because `invoke_expression` is broad, keep approval
  prompting and avoid treating it as a narrow read-only server.
- `node_repl`: bundled Codex tool, discovered rather than configured. Use when a
  skill or prompt says `node_repl`, for JavaScript execution, browser-plugin
  setup code, package import checks, and app-bundled Node runtime diagnostics.
- `chrome_devtools_observe`: frontend-only stdio MCP, intentionally OFF by
  default. It remains registered in config with `enabled = false` so Codex app
  settings show the capability without loading the tool outside frontend
  observation work. It is toggled with
  `maintenance\scripts\chrome-devtools-mcp-toggle.ps1`, not by hand-editing
  `config.toml`. Use only after a task is confirmed to require rendered browser
  observation. Default command is the local-chain wrapper
  `%USERPROFILE%\.codex\toolchains\shims\npx.cmd -y
  chrome-devtools-mcp@latest --slim --headless --isolated
  --no-usage-statistics --no-performance-crux`, with usage statistics and update
  checks disabled by environment variables. Turn it OFF after the frontend task
  and verify `state=off` with the server still registered as disabled.
- `memento`: global, streamable HTTP at `http://127.0.0.1:57332/mcp`, bearer
  token sourced from `MEMENTO_ACCESS_KEY`. Use for PM memory support only:
  `context` at session start, `get_skill_guide` when behavior is unclear,
  `recall` before hook/MCP/toolchain/prior-state work, `remember` only through
  the PM durable-write gate, `reflect` for final durable handoff, and
  `tool_feedback` after recall. It is not completion authority and must not
  override current user instructions, scoped `AGENTS.md`, files, tests, runtime
  output, or direct PM verification. Active source is
  `%USERPROFILE%\.codex\tools\memento-mcp`; active state is
  `%USERPROFILE%\.codex\state\memento-mcp`; PostgreSQL listens on local port
  `55432`; Memento HTTP listens on local port `57332`. Manage and verify with
  `maintenance\scripts\memento-mcp-runtime.ps1`.

## Frontend Browser Observation Toggle

Chrome DevTools MCP is not part of the always-on global MCP set. Its scope is
Codex-global only while a frontend task needs real rendered observation.

Activation sequence:

1. Confirm the task touches visible frontend UI or browser behavior.
2. Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.codex\maintenance\scripts\chrome-devtools-mcp-toggle.ps1 on
```

3. Reload or restart the Codex app/session before expecting new
   `mcp__chrome_devtools_observe__...` tools to appear.
4. Verify active tool exposure with tool discovery, then perform a small browser
   observation such as navigation plus screenshot or equivalent safe read.
5. After the frontend verification pass, run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.codex\maintenance\scripts\chrome-devtools-mcp-toggle.ps1 off
```

6. Confirm:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.codex\maintenance\scripts\chrome-devtools-mcp-toggle.ps1 status
```

Expected final state is `state=off`.

Use `-Visible` only when the task specifically requires a visible isolated Chrome
window. Use `-Full` only when the slim tool surface is insufficient, for example
when performance, network, accessibility snapshot, or deeper DevTools categories
are required. Do not connect this MCP to a user's normal Chrome profile or
logged-in sensitive pages unless the user explicitly asks for that risk boundary.

## Memento PM Memory Runtime

Memento MCP was installed as a clean Windows-native local-chain runtime. It does
not use WSL, Docker, the old temp clone, old memory DB paths, or legacy
`memsearch` as fallback.

- `source_class`: `local-chain`.
- `active_source`: `%USERPROFILE%\.codex\tools\memento-mcp`.
- `state_root`: `%USERPROFILE%\.codex\state\memento-mcp`.
- `postgres_data`: `%USERPROFILE%\.codex\state\memento-mcp\pgdata`.
- `postgres_port`: `55432`.
- `memento_url`: `http://127.0.0.1:57332/mcp`.
- `codex_mcp_name`: `memento`.
- `current_version`: local source package version `4.1.0`; upstream
  `origin/main` and tag `v4.1.0` both resolve to commit
  `98289226527f8be0138b7e34d3f843d040b09817`. The local runtime keeps the
  Codex Windows patches for disabled in-process ONNX and disabled adaptive
  search parameter learning.
- `credential_source`: user environment variable `MEMENTO_ACCESS_KEY` and the
  ignored local `.env`; do not print either value.
- `dependency_chain`: Codex official bundled Node -> local Memento checkout ->
  Scoop PostgreSQL 18 -> pgvector `0.8.2` -> dedicated `memento_pm` database.
- `privilege_model`: PostgreSQL is started by
  `memento-mcp-runtime.ps1` from the current non-elevated user token. It must
  not be launched from an elevated administrator token. Elevated Codex or
  PowerShell clients may request `start`, `repair`, or `verify`, but the script
  bridges the launch to a non-elevated user PowerShell and then connects to the
  same loopback MCP service.
- `user_permission`: `allowed` for the current non-elevated user token.
- `managed_memory_policy`: the Codex-managed runtime starts Memento with
  `MEMENTO_INPROCESS_ONNX_ENABLED=false` and
  `MEMENTO_MANAGED_EMBEDDING_PROVIDER=none` unless explicitly overridden. This
  keeps Reranker, NLI, and local transformers embedding models from loading into
  the long-lived MCP process while preserving the required PM memory tools for
  support-only context, topic/keyword recall, durable writes, and feedback. The
  runtime verifier reports `memento_working_set_mb` and fails above the managed
  default `MEMENTO_MAX_WORKING_SET_MB=512`.
- `verification`: run
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.codex\maintenance\scripts\memento-mcp-runtime.ps1 verify`.
- `session_start_guard`: `hooks\lightweight-codex-hook.ps1` calls
  `Invoke-MementoSessionStartEnsure` during `SessionStart`. The guard runs
  `memento-mcp-runtime.ps1 status`; if PostgreSQL or Memento HTTP is unhealthy,
  it schedules `memento-mcp-runtime.ps1 start` in a hidden background
  PowerShell and returns a context note with log paths. This prevents the
  previous hidden failure mode where a configured Memento MCP stayed down until
  a later manual `verify`. It does not claim that an already-running Codex
  session receives `mcp__memento__...` tools retroactively; reload may still be
  required when tools were missing at session creation.
- `doctor_coverage`: `maintenance\scripts\codex_agent_harness.py doctor --json`
  remains the full backward-compatible local check and includes
  `memento_runtime`. `doctor --tier core --json` intentionally excludes
  Memento/PostgreSQL so managed-source work is not blocked by optional PM memory
  runtime state. `doctor --tier stress --json` includes the runtime-heavy
  Memento check. The Memento check runs the managed runtime `status` action,
  records `current_process_administrator` as context, requires
  `postgres_ready=True` and `memento_health=True`, records the Memento working set against
  `MEMENTO_MAX_WORKING_SET_MB`, checks that the managed ONNX/local embedding
  defaults remain disabled, and scans recent
  Memento/PostgreSQL logs for known Windows failure signatures such as
  `0xC0000142`, shared-memory reservation `error code 487`, timeout, and
  `FATAL`/`PANIC` lines. Historical pre-restart matches are warnings; matches
  after the current managed runtime start fail doctor.
- `restart`: run the same script with `restart` to recycle the Memento HTTP
  process without stopping PostgreSQL. Use `stop` only when intentionally
  taking down both Memento HTTP and the dedicated PostgreSQL runtime.
- `session_reload_note`: current Codex sessions may not expose new
  `mcp__memento__...` tools until the app/session reloads. Until then, direct
  HTTP JSON-RPC probes are acceptable runtime evidence and must be reported as
  fallback verification, not as a hidden tool substitution.
- `rollback`: run the runtime script with `stop`; restore the saved config backup
  from `%USERPROFILE%\.codex\state\memento-mcp\config-backups` or remove the
  `memento` MCP entry only after an explicit user request. Preserve state unless
  destructive cleanup is explicitly requested.

Legacy Memory/RAG surfaces are contamination boundaries:

- `toolchains\shims\memsearch.*` and
  `maintenance\scripts\check-memory-rag-status.ps1` were removed to the Windows
  Recycle Bin on 2026-05-16 and must remain absent unless a reviewed rollback is
  requested.
- `memories` raw historical data was also recycled without reading contents.
  A reviewed import or migration into Memento must use an explicit user request,
  not hidden fallback.
- Cleanup manifest:
  `maintenance\reports\2026-05-16-clean-all-slop-runtime-cleanup.json`.

## Toolchain Source Rule

Codex-bundled command-line tools are `node`, `node_repl`, `rg`, and `codex`.
Use those from the official bundle. Local duplicates are removed when broken, or
left installed but marked unused by Codex wrappers when another local package
chain still depends on them.

`features.workspace_dependencies = true` is intentional. Workspace dependency
runtime paths come from the Codex app bundle and should not be treated as local
toolchain contamination.

Use local-chain tools for non-bundled capabilities such as npm packages, Python,
Rust, JVM, Git, PowerShell modules, and stdio MCP packages. Local-chain commands
must use explicit wrappers or absolute paths so PATH order cannot silently pick a
different runtime.

Run this check after shim or MCP command changes:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.codex\maintenance\scripts\check-toolchain-sources.ps1
```

## 2026-05-16 Codex App Update Clean Pass

- `source_class`: Codex Desktop package update plus managed workstation config
  cleanup.
- `package`: `OpenAI.Codex_26.513.3673.0_x64__2p2nqsd0c76g0`.
- `app_version_file`: `42.0.1`.
- `bundled_cli`: `codex-cli 0.131.0-alpha.9`.
- `changed_config`: `%USERPROFILE%\.codex\config.toml`.
- `changed_script`:
  `%USERPROFILE%\.codex\maintenance\scripts\start-windows-powershell-mcp.cmd`.
- `changed_profile`:
  `%USERPROFILE%\Documents\PowerShell\Microsoft.PowerShell_profile.ps1` now
  prepends the Codex shim root and official Codex bin for interactive PowerShell
  sessions.
- `persistent_path`: the temporary User PATH addition of
  `%USERPROFILE%\.codex\toolchains\shims` and
  `%LOCALAPPDATA%\OpenAI\Codex\bin` was removed after `rg-resolution-smoke`
  proved it violated the managed process-local PATH policy.
- `changed_native_host`:
  `%LOCALAPPDATA%\OpenAI\extension\com.openai.codexextension.json` and
  `HKCU\Software\Google\Chrome\NativeMessagingHosts\com.openai.codexextension`.
- `owner`: Codex global workstation maintenance.
- `config_surface`: `[mcp_servers.windows_powershell].command` now points to the
  wrapper above; `model_reasoning_effort` is reset to the managed default
  `medium`; legacy local `memories` generation/use is disabled in
  `%USERPROFILE%\.codex\config.toml` so raw Memory/RAG residue cannot keep
  reappearing as a fallback route.
- `dependency_chain`: Codex Desktop official bundle ->
  `%LOCALAPPDATA%\OpenAI\Codex\bin` -> `%USERPROFILE%\.codex\toolchains\shims`
  -> installed `PowerShell.MCP.Proxy.exe`.
- `reason`: after the app update, the active PowerShell MCP console could run
  by explicit path but bare `rg` and `codex` were not on PATH. The wrapper makes
  future PowerShell MCP sessions inherit the same official Codex bundle/shim
  route used by normal Codex tooling, and the PowerShell profile covers
  profile-rebuilt internal shells without requiring persistent User PATH
  pollution. The Chrome native messaging manifest was also re-registered with
  the current installed Codex app bundle so it no longer points at
  `.codex\plugins\cache`.
- `verification`: parse config with `codex mcp list`, run
  `check-toolchain-sources.ps1`, run `memento-mcp-runtime.ps1 verify`, and
  verify `rg`, `codex`, `node`, and `python` resolve through the Codex shims in
  a new PowerShell profile session reconstructed from persistent User and
  Machine PATH. Run `codex-home-maintenance.ps1 -Mode Report` and require
  `native_messaging_hosts.stale_cache_reference=false`.
- `reload_note`: already-running Codex sessions may keep the old MCP process
  until the app/session reloads. This is runtime state, not a config failure.
- `known_runtime_noise`: PowerShell.MCP `1.8.0` is the current PSGallery
  version as of 2026-05-16. Codex MCP discovery may still ask this server for
  `resources/list` and `resources/templates/list`; the server logs Windows
  Application Event warnings because those optional handlers are not available.
  Tool calls such as `get_current_location` and `invoke_expression` remain
  functional, so this is tracked as upstream/client capability-probe noise, not
  a local workstation clean failure.
- `rollback`: restore
  `%USERPROFILE%\.codex\maintenance\backups\config-before-codex-update-clean-20260516-205543.toml`
  or
  `%USERPROFILE%\.codex\maintenance\backups\config-before-disable-legacy-memories-20260516-225648.toml`
  to `%USERPROFILE%\.codex\config.toml`, import the matching
  `%USERPROFILE%\.codex\maintenance\backups\com.openai.codexextension-before-clean-*.reg`
  file and restore the matching JSON backup if the Chrome native host needs to
  be reverted, remove the wrapper script if no longer referenced, restore
  `%USERPROFILE%\.codex\maintenance\backups\user-path-before-removing-codex-shim-persistent-20260516-213112.txt`
  only if persistent PATH behavior must be reverted, and remove the two Codex
  entries from the PowerShell profile if the profile route must be reverted.

## 2026-05-18 Browser And Chrome Native Host Recovery

- `source_class`: Codex Desktop browser/plugin runtime repair.
- `package`: `OpenAI.Codex_26.513.4821.0_x64__2p2nqsd0c76g0`.
- `changed_native_host`:
  `%LOCALAPPDATA%\OpenAI\extension\com.openai.codexextension.json`.
- `changed_runbook`:
  `%USERPROFILE%\Downloads\codex-windows-browser-recovery-runbook.md`.
- `root_cause`: the Chrome native messaging manifest survived a Codex Desktop
  update and still pointed to the removed
  `OpenAI.Codex_26.513.3673.0_x64__2p2nqsd0c76g0` package. The HKCU registry
  key was still valid because it pointed to the manifest JSON, but the
  executable path inside that JSON no longer existed.
- `secondary_mismatch`: importing `browser-client.mjs` from the legacy
  `browser-use` cache path failed native bridge trust with `browser-client is
  not trusted`; the working in-app Browser route is the official installed app
  bundle `plugins\browser\scripts\browser-client.mjs`.
- `fix`: back up the native host JSON, then update only its `path` value to the
  current installed app bundle host:
  `C:\Program Files\WindowsApps\OpenAI.Codex_26.513.4821.0_x64__2p2nqsd0c76g0\app\resources\plugins\openai-bundled\plugins\chrome\extension-host\windows\x64\extension-host.exe`.
- `backup`:
  `%LOCALAPPDATA%\OpenAI\extension\com.openai.codexextension.json.bak-20260518-023107`.
- `verification`:
  - manifest JSON parses and `Test-Path` for the manifest `path` is true;
  - `reg.exe query HKCU\Software\Google\Chrome\NativeMessagingHosts\com.openai.codexextension /ve`
    points at `%LOCALAPPDATA%\OpenAI\extension\com.openai.codexextension.json`;
  - Chrome backend discovery lists `type=extension`;
  - in-app Browser `iab` and Chrome `extension` both opened
    `http://127.0.0.1:5173/` and `http://localhost:5173/`, clicked the smoke
    button, and navigated to `/clicked` with title `Codex Browser E2E Clicked`;
  - temporary port `5173` was closed after the check.
- `runbook_policy_update`: removed the project-level browser automation fallback
  from the Windows browser recovery runbook. Future agents should not use
  project browser automation as proof that Codex Browser or the Codex Chrome
  plugin works.
- `2026-05-18 follow_up_prevention`: `ensure-chrome-extension-origin.ps1` now
  verifies `browser@openai-bundled` through the Codex app-server protocol and
  reports `installed=true enabled=true` instead of trusting cache presence. The
  helper avoids the Windows PowerShell `ProcessStartInfo.ArgumentList` null
  issue and uses a UTF-8 Python probe for app-server requests because the app
  protocol accepts `id/method/params` line JSON, not generic JSON-RPC with a
  `jsonrpc` field.
- `2026-05-18 maintenance_guard`: `codex-home-maintenance.ps1` now records
  whether the Chrome native host executable exists and whether it is under the
  currently installed Codex package location. This catches registry-valid but
  executable-stale native host manifests after app updates.
- `rollback`: restore the JSON backup above, or rerun the Codex Chrome plugin
  setup flow from the Codex app UI if a future app version changes the native
  host contract.
- `agent_handoff`: when Chrome disappears after a Codex app update, first check
  the manifest executable path existence before changing firewall, loopback,
  cache, or browser security settings. Existing helper scripts may report the
  manifest as `correct=true` while the executable path is stale, so always run a
  direct `Test-Path` on the manifest `path`.

## Required Agent Behavior

When a task matches one of the purposes above:

1. Use `tool_search` if a configured MCP namespace is not already visible in the
   active tool list.
2. If the namespace is exposed, call the MCP tool directly and cite the tool
   result as evidence.
3. If config says enabled but the namespace remains absent, record a runtime-load
   issue, inspect `codex mcp list/get`, and use the best available fallback.
4. For `enabled_tools`, verify the allow-list against the server's actual
   `tools/list` names before concluding the install is broken.
5. Do not wait for the user to name MCPs when the task clearly requires current
   docs, registry facts, Windows stateful diagnostics, JavaScript execution, or
   high-ambiguity planning; choose the matching MCP proactively and report the
   evidence surface used.

## 2026-05-15 Active-Use Verification

- `codex.cmd` shim added at `%USERPROFILE%\.codex\toolchains\shims\codex.cmd`.
- `codex mcp list` through the shim succeeded and reported:
  `context7`, `sequential_thinking`, `windows_powershell`,
  `openaiDeveloperDocs`, and `memento` enabled; `chrome_devtools_observe` and
  `shadcn` were disabled before the refresh.
- `shadcn` was changed to `enabled = true` in global config so future frontend
  sessions can inject the MCP without a manual config edit. Current already
  running sessions may still need reload before `mcp__shadcn__...` tools appear.
- `chrome_devtools_observe` remains disabled by default. This is intentional:
  it should be toggled on only for rendered frontend/browser observation and
  turned off after use.
- Memento was inspected for support-only PM context but was not optimized or
  reconfigured in this refresh.

## Delete/Reinstall Guidance

Do not delete and reinstall first for the known symptom "configured MCP is
enabled but absent from a session." Prefer this order:

1. Verify global config with `codex mcp list` and `codex mcp get <name>`.
2. Replace fragile `~` or `%VAR%` command/cwd values with absolute paths.
3. Align `enabled_tools` with actual server tool names.
4. Reload the app/session or use Codex app-server MCP reload when available.
5. Reinstall only when the command binary/package is missing, corrupted, or
   fails a direct `initialize`/`tools/list` probe after the config is known good.
