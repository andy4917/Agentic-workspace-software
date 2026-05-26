# MCP Runtime Status

Updated for the 2026-05-26 minimal scaffold pass.

## Current Finding

The minimal scaffold MCP set is intentionally limited to `memento`, `context7`,
`chrome-devtools`, and `serena`. Any other user-configured MCP entry is stale
for this baseline unless a future user request explicitly widens the set.

`memento` is the only configured MCP that has an expected live local service for
scaffold validation. The current baseline policy is `registered + read-only live
verify`: keep the MCP registration, keep the local service/start script
documented, prove HTTP readiness and tool exposure with read-only verification,
and exclude PostgreSQL data, Memento state, logs, sessions, caches, and auth
material from the final clean baseline. Memory write/feedback probes require
the explicit `verify -WriteProbe` path.

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

- `memento`: global, streamable HTTP at `http://127.0.0.1:57332/mcp`, bearer
  token sourced from `MEMENTO_ACCESS_KEY`. Use for PM memory support only:
  `context` at session start, `get_skill_guide` when behavior is unclear,
  `recall` before hook/MCP/toolchain/prior-state work, `remember` only through
  the PM durable-write gate, `reflect` for final durable handoff, and
  `tool_feedback` after recall. It is not completion authority and must not
  override current user instructions, scoped `AGENTS.md`, files, tests, runtime
  output, or direct PM verification. Active source is
  `%USERPROFILE%\.codex\tools\memento-mcp`; active state is excluded from the
  final scaffold baseline. Manage and verify with
  `maintenance\scripts\memento-mcp-runtime.ps1 verify`.
- `context7`: global, stdio via `cmd /c npx -y @upstash/context7-mcp`, with
  `CONTEXT7_API_KEY` sourced from the environment. Use for current third-party
  library, framework, SDK, CLI, and cloud-service documentation. Resolve the
  library id before querying.
- `chrome-devtools`: global, stdio via
  `cmd /c npx -y chrome-devtools-mcp@latest --slim --headless --isolated
  --no-usage-statistics --no-performance-crux`. Use for rendered browser
  observation when the active session exposes the tools. Do not connect it to a
  user's normal Chrome profile or logged-in sensitive pages unless the user
  explicitly asks for that risk boundary.
- `serena`: global, stdio via pinned `uvx` source
  `git+https://github.com/oraios/serena@981f560fa334ba52e9a2a45c702f23d971c9dcca`.
  It starts with `--project-from-cwd --context=codex --open-web-dashboard
  False`. For coding tasks, call `initial_instructions` when exposed, activate
  the project when needed, and verify the next spawn leaves exactly one Serena
  server root and no auto-opened dashboard.
- `node_repl`: bundled Codex tool, discovered rather than configured. Use when a
  skill or prompt says `node_repl`, for JavaScript execution, browser-plugin
  setup code, package import checks, and app-bundled Node runtime diagnostics.

Historical MCPs such as `openaiDeveloperDocs`, `shadcn`,
`sequential_thinking`, `windows_powershell`, and `chrome_devtools_observe` are
not part of the minimal scaffold baseline. Reintroduce them only through an
explicit future user request and a new config-fragment reconciliation pass.

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
- `credential_source`: user environment variable `MEMENTO_ACCESS_KEY` and the
  ignored local `.env`; do not print either value.
- `dependency_chain`: Codex official bundled Node -> local Memento checkout ->
  Scoop PostgreSQL 18 -> pgvector `0.8.2` -> dedicated `memento_pm` database.
- `privilege_model`: PostgreSQL is started by
  `memento-mcp-runtime.ps1` from the current non-elevated user token. It must
  not be launched from an elevated administrator token; the runtime is intended
  to require no administrator privileges after installation.
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
  `verify` is read-only for memory feedback by default and reports
  `tool_feedback=skipped-readonly`; use `verify -WriteProbe` only when an
  intentional memory write/feedback probe is part of the check.
- `doctor_coverage`: `maintenance\scripts\codex_agent_harness.py doctor --json`
  remains the full backward-compatible local check and includes
  `memento_runtime`. `doctor --tier core --json` intentionally excludes
  Memento/PostgreSQL so managed-source work is not blocked by optional PM memory
  runtime state. `doctor --tier stress --json` includes the runtime-heavy
  Memento check. The Memento check runs the managed runtime `status` action,
  requires `current_process_administrator=False`, `postgres_ready=True`, and
  `memento_health=True`, records the Memento working set against
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

## Historical 2026-05-16 Codex App Update Clean Pass

This section is retained as historical maintenance evidence only. It is not the
current minimal MCP baseline.

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

## Historical 2026-05-15 Active-Use Verification

This section records the pre-reset MCP posture and must not be used as the
current MCP allow-list.

- `codex.cmd` shim added at `%USERPROFILE%\.codex\toolchains\shims\codex.cmd`.
- `codex mcp list` through the shim succeeded and reported:
  `context7`, `sequential_thinking`, `windows_powershell`,
  `openaiDeveloperDocs`, and `memento` enabled; `chrome_devtools_observe` and
  `shadcn` were disabled before the refresh.
- `shadcn` was changed to `enabled = true` in that historical config pass, but
  it is not part of the 2026-05-26 minimal scaffold baseline.
- `chrome_devtools_observe` was disabled by default in that historical config
  pass. The 2026-05-26 minimal baseline uses the `chrome-devtools` MCP entry
  instead.
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
