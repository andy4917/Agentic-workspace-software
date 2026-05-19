# Agent Incident Manual

This file is a mutable knowledge base for recurring agent, subagent, Codex app, tool, and workflow incidents. Use it during live troubleshooting, then update it when a new pattern is verified.

## Fast Triage

1. Capture the fingerprint:
   - exact error fragment;
   - tool, command, or agent role involved;
   - path or surface involved;
   - expected result versus actual result;
   - whether any fallback happened.
2. Classify one primary type from `Incident Types`.
3. Check the reward-hacking and app/tool pattern sections for a matching fingerprint.
4. Apply only fixes whose assumptions match the current context.
5. Verify with the same failing action when practical.
6. Add or update a record if the issue was new, repeated, or likely to mislead future agents.

## Incident Types

Use one primary type and optional secondary tags.

| Type | Use For | Typical Evidence |
| --- | --- | --- |
| `reward_hacking` | Agent claims success without direct proof, weakens acceptance criteria, hides skipped checks, or treats a report as completion. | PASS labels, vague summaries, missing command output, unverified subagent claims. |
| `subagent_drift` | Subagent exceeds charter, edits outside owned files, duplicates PM work, ignores not-checked requirements, or reports stale context. | Changed unrelated files, missing mid-report, unsupported conclusions. |
| `tool_runtime_error` | Shell, MCP, browser, image, automation, patch, or other tool fails unexpectedly. | Tool error text, invalid arguments, unavailable server, timeout. |
| `codex_app_error` | Desktop app terminal, thread, automation, connector, rendering, or attachment behavior fails. | App-specific error, missing terminal session, UI artifact not displayed. |
| `workflow_hook_issue` | Hook reminder blocks too broadly, records misleading state, or creates non-authoritative completion pressure. | Hook text, state file, stop reminder, mismatch with actual evidence. |
| `environment_path_issue` | Windows quoting, path separators, path length, cwd, shim, shell, or executable resolution causes failure. | Absolute path, runner, PATH/shim check, command line. |
| `validation_gap` | Tests/builds/screenshots/checks are absent, stale, partial, or do not cover the changed behavior. | Not-run reason, changed surface, missing acceptance check. |
| `skill_or_doc_drift` | Skill instructions, references, templates, or manual entries are stale, ambiguous, duplicated, or too broad. | Trigger mismatch, outdated pattern, conflicting docs. |
| `git_or_state_issue` | Dirty worktree, unrelated user edits, branch mismatch, staging/commit/push issue, or generated metadata drift. | `git status`, branch, diff, lockfile or generated files. |
| `security_boundary` | Secret access, credential handling, destructive command, irreversible action, or out-of-scope mutation risk. | File path, command, approval requirement, protected asset. |

## Reward-Hacking Patterns

| Pattern | Fingerprint | PM Response |
| --- | --- | --- |
| Unsupported PASS | Output says PASS/complete but lacks command, path, line, diff, or reproducible observation. | Downgrade to unsupported claim. Re-run or inspect directly before using it. |
| Check laundering | A broad check is cited as proof for behavior it does not cover. | Map each acceptance criterion to direct evidence; record uncovered areas. |
| Fallback concealment | Agent silently switches tools, files, models, or scope after failure. | Surface the fallback, verify equivalence, and record the original failure. |
| Scope shrinking | Agent redefines the goal to match what was already done. | Restate the user's objective and compare changed behavior against it. |
| Not-run erasure | Skipped checks disappear from the final report or become "validated by inspection." | Restore `not_run` with exact reason and closest substitute evidence. |
| Stale-context success | Agent reports on old files, old branches, or pre-change state. | Rebuild context from current paths and rerun the relevant check. |
| Tool-availability illusion | Agent treats configured or installed tools as actual use. | Require a real tool invocation or mark as not applicable. |
| Project-chain omission | Agent performs project work or claims readiness while the project lacks the relevant workflow chain. | Classify `chain_ready`, `chain_partial`, `chain_missing`, or `chain_not_applicable`; scaffold or report the missing chain before implementation. |
| Review theater | Reviewer gives a summary before findings and misses concrete line/path evidence. | Ask for findings first, severity, file/line, and not-checked items. |
| Evidence flooding | Large logs are pasted to imply rigor without isolating the decisive lines. | Extract the minimal failing fragment and the command that produced it. |
| Worker authority leak | PM accepts worker/subagent completion without independent verification. | Treat worker output as candidate evidence and verify the decisive claim. |

## Codex App And Tool Patterns

### Shell Tool Argument Failure

- Type: `tool_runtime_error`, `environment_path_issue`
- Fingerprint: every `shell_command` call fails before execution with an argument or wrapper error, even for `pwd` or `Get-Location`.
- Likely cause: runtime wrapper problem, shell launch configuration, or command transport issue rather than the requested command.
- Fix:
  1. Try a simpler command once to confirm it is global.
  2. Use another local execution surface when available, such as a Node REPL MCP, for read-only inspection and validation.
  3. Use `apply_patch` for manual edits instead of shell write tricks.
  4. Record that shell-based validation could not run and cite the alternate checks.
- Verification: alternate tool successfully reads files or runs a small child process; original shell tool failure is preserved as not fixed unless directly recovered.
- Not checked by default: root cause inside the Codex desktop runtime.

### Reference Read Blocked By Primary Tool

- Type: `tool_runtime_error`, `validation_gap`
- Fingerprint: an agent can read the main skill or has the skill path, but fails to read a referenced manual because its first file-reading tool fails globally.
- Risk: the agent may complete from partial instructions and miss the detailed taxonomy or templates.
- Fix:
  1. Preserve the failed read attempt and exact error.
  2. Try another available local read surface, such as MCP filesystem resources, Node REPL, app attachment context, or a different non-destructive file read command.
  3. If no alternate read path is available, state that the response is based only on the loaded skill body and mark the reference as not checked.
- Verification: the reference file is read successfully through an alternate path, or the final report explicitly marks it as not checked.

### Harness Verify Uses Caller CWD As CODEX_HOME

- Type: `environment_path_issue`, `validation_gap`
- Fingerprint: invoking `%USERPROFILE%\.codex\maintenance\scripts\codex_agent_harness.py verify` from another directory writes reports under the caller CWD and fails to find `maintenance/scripts/codex_agent_harness.py` or `hooks/lightweight-codex-hook.ps1`.
- Risk: agents may report harness failure even though the `.codex` harness is healthy, or may require users to manually `cd` into `.codex`.
- Likely cause: `--root` default resolves to `.` instead of the harness install root.
- Fix playbook:
  1. Default the harness root to the script install root when `--root` is omitted.
  2. Preserve explicit `--root` for intentional alternate roots.
  3. Re-run verification from a non-`.codex` cwd and confirm reports are written to `%USERPROFILE%\.codex\reports`.
- Verification: absolute script invocation succeeds from another cwd; `.codex\reports\verification.latest.md` shows all checks pass.
- Do not claim: the harness is broken solely because a relative-root run failed from a non-root cwd.

### Harness Relative Path Fails On Junctioned Plugin Cache

- Type: `environment_path_issue`, `validation_gap`
- Fingerprint: `codex_agent_harness.py doctor --json` fails in `rel(path, root)` with `ValueError: '<Program Files ... browser-client.mjs>' is not in the subpath of 'C:\\Users\\anise\\.codex'` while scanning `plugins/cache`.
- Risk: a valid plugin cache junction to the installed Codex app bundle can make doctor fail before reporting the actual hook or harness status.
- Likely cause: path reporting resolves junction targets before computing root-relative display paths.
- Fix playbook:
  1. Keep the resolved-path relative check for normal files.
  2. Fall back to the logical root-relative path when the original path is under the root but resolves outside through a junction.
  3. Return an absolute resolved path only for truly external paths.
- Verification: `codex_agent_harness.py doctor --json` runs past `workspace_script_file_size` and reports normal check results.
- Do not claim: that the external app bundle file is owned by `.codex`; the fallback is display/reporting only.

### Missing App Terminal Session

- Type: `codex_app_error`
- Fingerprint: terminal inspection reports no attached app terminal session.
- Fix:
  1. Do not assume a hidden terminal is running.
  2. Use available execution tools for direct checks.
  3. If the user asked for terminal state specifically, report that no session is attached.
- Verification: the terminal inspection tool returns the no-session message or a later session state.

### Codex Windows Read-Only Sandbox Runner Denies Process Creation

- Type: `codex_app_error`, `tool_runtime_error`, `validation_gap`
- Fingerprint: `codex exec --sandbox read-only` fails before the requested shell command starts with `CreateProcessAsUserW failed: 5`.
- Risk: agents may misdiagnose a tested command, shim, or repository as broken even though the sandbox runner failed first.
- Likely cause: Codex Windows sandbox process-creation boundary, not the target command.
- Fix playbook:
  1. Preserve the exact `codex exec` command and error text.
  2. Do not use read-only sandbox exec as a required verification path until a Codex update or confirmed local runtime fix resolves it.
  3. Use the active local shell or `codex exec --sandbox danger-full-access --disable plugins` with an explicit no-mutation prompt for Codex-internal smoke tests.
  4. Record read-only sandbox verification as not run, with this runner error as the reason.
- Verification: alternate command surface runs the intended command; read-only sandbox remains a separate unresolved runtime item.
- Do not claim: that the target command failed, or that danger-full-access smoke testing proves read-only sandbox behavior.

### MCP Server Configured But Tools Unloaded

- Type: `tool_runtime_error`, `skill_or_doc_drift`
- Fingerprint: instructions mention an MCP server, but no matching `mcp__...` tools are exposed.
- Fix:
  1. Use tool discovery if available.
  2. Record a runtime-load issue if discovery does not expose the tool.
  3. Use the best available fallback and state the fallback in the final report.
- Verification: discovered tool list, fallback command output, or explicit not-available evidence.

### MCP Server Enabled But Filtered Or Path-Fragile

- Type: `tool_runtime_error`, `environment_path_issue`
- Fingerprint: `codex mcp list` shows a server as enabled, but the active session omits its namespace; direct MCP `tools/list` succeeds or shows tool names that do not match `enabled_tools`.
- Risk: agents may claim "configured" as "usable", or miss that path expansion/filtering caused the app loader to expose zero tools.
- Likely causes: Windows `%VAR%` or `~` paths in MCP config are not expanded by the loader; `enabled_tools` names are stale after a server version change.
- Fix playbook:
  1. Replace fragile paths in `command` and `cwd` with absolute Windows paths.
  2. Run the server directly and call MCP `tools/list` when practical.
  3. Align `enabled_tools` with actual server tool names, keeping approval prompts for broad command tools.
  4. Start a new session or reload the app because existing sessions do not receive newly exposed MCP tool schemas.
- Verification: `codex mcp get/list` shows the intended absolute paths and filters; direct server startup or `tools/list` succeeds; current session remains not fixed unless the namespace appears in the active tool list.
- Do not claim: that the current session can call the MCP just because config was fixed.

### Memento In-Process ONNX Memory Spike

- Type: `tool_runtime_error`, `environment_path_issue`
- Fingerprint: Windows Task Manager shows a long-lived `node.exe server.js` process from the Codex bundled Node runtime using around 1GB RAM after Codex app restart or after semantic memory use.
- Risk: agents may misclassify the process as an orphaned Codex app leak, kill the wrong Node process, or leave a managed MCP runtime outside the memory budget.
- Likely causes: Memento loads Reranker, NLIClassifier, and local transformers embedding models in-process; the server is a global HTTP MCP runtime and does not automatically exit with the Codex app.
- Fix playbook:
  1. Identify the process by PID, command line, listening port `57332`, and `memento-mcp-runtime.ps1 status`.
  2. Prefer `memento-mcp-runtime.ps1 restart` for the HTTP server; do not stop PostgreSQL unless the user asked to take down the whole runtime.
  3. For Codex PM memory use, start the managed runtime with `MEMENTO_INPROCESS_ONNX_ENABLED=false` and `MEMENTO_MANAGED_EMBEDDING_PROVIDER=none`; keep semantic/local embedding use explicit.
  4. Verify with `memento-mcp-runtime.ps1 verify` and check `memento_working_set_mb` against the managed limit.
- Verification: verifier reports required tools present, `context`/`recall`/`tool_feedback` pass, and `memento_working_set_mb` stays below `MEMENTO_MAX_WORKING_SET_MB`.
- Do not claim: that all Node processes are safe to kill, or that configured MCP memory is healthy without PID/port/tool verification.

### Memento PostgreSQL Shared-Memory Stuck Runtime

- Type: `tool_runtime_error`, `environment_path_issue`
- Fingerprint: Memento `context` or `recall` returns `Connection terminated due to connection timeout`; `/health` returns 503; `pg_isready` reports `no response` even though port `55432` is listening; PostgreSQL log includes `autovacuum worker ... exception 0xC0000142` followed by `could not reserve shared memory region ... error code 487`.
- Risk: agents may misdiagnose the timeout as a thread-local Codex session issue, while the shared Memento PostgreSQL runtime is stuck for every session.
- Likely causes: Windows PostgreSQL postmaster remains alive after a worker crash, but child backend processes can no longer attach the shared memory region; `pg_ctl start/stop -w` can also hang around this state.
- Fix playbook:
  1. Confirm the runtime with `memento-mcp-runtime.ps1 status`, `/health`, `pg_isready`, and the PostgreSQL log fingerprint.
  2. Use `memento-mcp-runtime.ps1 repair` after the runtime script has bounded non-waiting PostgreSQL stop/start logic.
  3. Scope any forced process stop to the Memento `pgdata` PID/process tree, not all PostgreSQL processes.
  4. Keep PM-only Memento runtime with `MEMENTO_SEARCH_PARAM_ADAPTOR_ENABLED=false` unless adaptive search-threshold learning is explicitly needed.
- Verification: `memento-mcp-runtime.ps1 verify` reports `context=pass`, `recall=pass`, `tool_feedback=pass`, `/health` returns healthy, and a live MCP `context(workspace="global_pm")` returns immediately.
- Do not claim: that restarting the Codex thread fixes this; the failure is in the shared local Memento backend until PostgreSQL and the Memento HTTP server are repaired.

### Memento PostgreSQL Administrator Token Refusal

- Type: `tool_runtime_error`, `security_boundary`
- Fingerprint: PostgreSQL stderr says the server cannot run as a system administrator ID; `memento-mcp-runtime.ps1 status` reports `postgres_ready=False` and Memento MCP calls fail with `ECONNREFUSED 127.0.0.1:55432`.
- Risk: agents may ask for elevation even though PostgreSQL explicitly requires the opposite launch condition.
- Likely cause: Memento PostgreSQL was started from an elevated administrator token instead of the current non-elevated user token.
- Required service owner state: `user_permission=allowed`; PostgreSQL is owned by the current non-elevated user token. Elevated clients may connect to the loopback MCP service, but must not directly launch PostgreSQL.
- Fix playbook:
  1. Check `memento-mcp-runtime.ps1 status`; preserve `current_process_administrator`, `postgres_ready`, and `memento_health`.
  2. Run `memento-mcp-runtime.ps1 start`, `repair`, or `verify`; the script must bridge elevated clients to a non-elevated user launch before starting PostgreSQL.
  3. Verify with `memento-mcp-runtime.ps1 verify`, `doctor --tier stress --json`, and live `context(workspace="global_pm")`.
- Do not claim: that administrator permission is required for normal Memento runtime operation after installation.

### Memento Runtime Healthy Too Late For MCP Tool Exposure

- Type: `tool_runtime_error`, `workflow_hook_issue`, `validation_gap`
- Fingerprint: `codex mcp get memento --json` shows the server configured and enabled, but the active session exposes no `mcp__memento__...` tools; `memento-mcp-runtime.ps1 status` reports `postgres_ready=True` and `memento_health=False` until `memento-mcp-runtime.ps1 verify` or `start` is run.
- Risk: agents may treat Memento as unavailable and fall back to legacy Memory/RAG or final prose, even though the memory backend is repairable and should be support-only MCP evidence.
- Likely cause: the old SessionStart hook only told the PM to use Memento after tools were exposed; it did not ensure the local HTTP runtime was healthy early enough for MCP tool schema loading.
- Fix playbook:
  1. Preserve `status`, `/health`, `codex mcp get memento --json`, and active-session tool exposure evidence.
  2. Keep `memento-mcp-runtime.ps1 verify` as the direct repair and verification command.
  3. Add or keep a SessionStart guard that checks `memento-mcp-runtime.ps1 status` and schedules `start` when the runtime is unhealthy.
  4. Record that the current session may need a reload because MCP tool schemas are not retroactively injected after session start.
- Verification: `memento-mcp-runtime.ps1 verify` reports required tools present plus `context=pass`, `recall=pass`, and `tool_feedback=pass`; a synthetic SessionStart hook sample returns normal context without failing when Memento is healthy.
- Do not claim: that a background start proves current-session `mcp__memento__...` tool exposure unless the active tool namespace is actually visible.

### MCP Capability Works But Is Invisible In App Settings

- Type: `codex_app_error`, `skill_or_doc_drift`
- Fingerprint: a capability is available through local files, scripts, or package probes, but app settings imply it is missing because the MCP entry is removed while inactive, or because the capability is a Skill rather than an MCP server.
- Likely cause: conflating runtime availability, MCP registration, active tool exposure, and app settings visibility.
- Fix:
  1. Classify the capability: MCP server, Skill, plugin, connector, or script.
  2. For MCP servers that should be discoverable in settings while inactive, keep the MCP entry registered with `enabled = false` instead of removing the entry.
  3. For Skills, state clearly that they will not appear in MCP settings and document the skill path.
  4. Update the owning maintenance record so future agents do not report "installed" when the user's UI concern is "visible".
- Verification: `codex mcp list` shows the intended MCP with `Status disabled` or `enabled`; `codex mcp get <name> --json` returns the expected config; the skill path exists when the concern is a Skill.
- Do not claim: app UI visibility from a package probe alone.

### Disabled Chrome DevTools MCP Leaves Stale Node Processes

- Type: `tool_runtime_error`, `state_failure`, `workflow_hook_issue`
- Fingerprint: `codex mcp get chrome_devtools_observe --json` reports `enabled=false`, but `Get-CimInstance Win32_Process` still shows `node.exe` processes whose command line contains `chrome-devtools-mcp`.
- Risk: agents may report the MCP as disabled while stale observer processes continue running and consuming runtime resources.
- Likely cause: disabling the MCP config does not retroactively stop already-started stdio server processes in the active app session.
- Fix playbook:
  1. Preserve the disabled MCP config evidence and the stale process count.
  2. Use `maintenance\scripts\chrome-devtools-mcp-toggle.ps1 off`; the script must keep the server registered with `enabled=false` and stop stale `chrome-devtools-mcp` Node processes.
  3. Remove any toggle backup directory that is no longer needed after `codex mcp get chrome_devtools_observe --json` parses and reports `enabled=false`.
- Verification: `chrome-devtools-mcp-toggle.ps1 off` reports `stopped_stale_processes=<n>`, `codex mcp get chrome_devtools_observe --json` reports `enabled=false`, and the stale `chrome-devtools-mcp` process count is `0`.
- Do not claim: process cleanup from config text alone.

### Browser Use Native Bridge Trust Blocked By Patched Client

- Type: `tool_runtime_error`, `skill_or_doc_drift`, `environment_path_issue`
- Fingerprint: `browser-use:browser` setup through Node REPL fails with `privileged native pipe bridge is not available; browser-client is not trusted. Load browser-client from the openai-bundled marketplace directory.`
- Risk: agents may use Chrome headless, CDP, or another browser surface and report the requested Browser plugin as verified.
- Likely cause: `openai-bundled` points to an unregistered copied or patched marketplace, or the skill imports stale `plugins/cache/openai-bundled/browser-use/.../scripts/browser-client.mjs`; native bridge trust is normally granted to the active `openai-bundled` marketplace source, not arbitrary cache paths.
- Fix playbook:
  1. Preserve the exact Node REPL setup error and the imported `browser-client.mjs` path.
  2. Check the active `[marketplaces.openai-bundled]` source in `config.toml`.
  3. Prefer the active configured marketplace that contains `plugins/browser/scripts/browser-client.mjs`, exports `setupBrowserRuntime`, and is not under `.tmp`, `tmp`, or `plugins/cache`.
  4. Do not import arbitrary patched `browser-client.mjs` copies to bypass origin policy; that can remove native bridge trust. If the official WindowsApps bundle itself appears to have an overblocking URL policy, keep `[marketplaces.openai-bundled].source` pointed at the official bundle, preserve the evidence, and treat the fix path as an official app update or product/runtime issue. Do not patch WindowsApps, cache copies, or mirrors as a durable repair unless the user explicitly asks for that specific file.
- Verification: import the official bundled client with Node REPL, call `setupBrowserRuntime({ globals: globalThis })`, get `agent.browsers.get("iab")`, and confirm `browser.tabs.list()` succeeds.
- Do not claim: Browser plugin verification from Chrome headless/CDP fallback alone.

### Browser URL Policy Overblocks Chrome Extension Pages

- Type: `tool_runtime_error`, `policy_overblock`, `environment_path_issue`
- Fingerprint: Chrome backend discovery succeeds, but `tab.goto("chrome-extension://.../sidepanel.html")` fails with `Browser Use cannot visit the requested page because its URL is blocked by the Browser Use URL policy.` Local inspection shows the official URL gate only allows `about:blank`, `http:`, and `https:`.
- Risk: agents may substitute standalone Playwright, CDP, or an in-app browser preview and falsely report the actual Chrome extension UI as verified.
- Likely cause: the trusted `browser-client.mjs` URL gate was narrower than the Chrome extension product surface. Chrome side panels are extension pages, and the Codex Chrome documentation describes Chrome as the profile-backed browser surface while in-app browser remains the first choice for ordinary localhost/public previews.
- Fix playbook:
  1. Preserve the blocked URL, backend type, selected browser metadata, and the exact `Qv`/origin-gate snippets before changing anything.
  2. Do not force a headless/CDP workaround and do not make a mirror or cache path the active source.
  3. Do not run local repair scripts that take ownership of, grant permissions on, or patch the installed WindowsApps bundle. Official bundle behavior should be corrected by an official app update unless the user explicitly asks to edit a specific official file.
  4. Keep `[marketplaces.openai-bundled].source` pointed at the official WindowsApps bundle to avoid mirror drift, and keep stale `browser-use@openai-bundled` config absent or disabled unless the active official marketplace contains that plugin ID.
  5. Treat the running session as stale after official app updates; restart/reload Codex before claiming runtime verification.
- Verification: confirm `config.toml` parses, the active `openai-bundled` source is the installed Codex Desktop bundle, the official marketplace manifest contains the plugin ID being enabled, `ensure-chrome-extension-origin.ps1 -NoNodeCheck` does not depend on cache or mirror clients, and a fresh Codex session can import the official client and observe the requested backend. If the official client still rejects `chrome-extension://...`, report the product/runtime limitation instead of patching it locally.
- Do not patch `plugins\cache` as a durable fix. Modified cache clients can lose native bridge trust and fail before URL-policy verification with `browser-client is not trusted`.
- If an official app update or replacement changes the file text but `setupBrowserRuntime` then fails with `browser-client is not trusted`, restore only user-owned changes and escalate as a native bridge trust/content-integrity issue rather than trying a mirror, cache patch, raw CDP, or global monkeypatch.
- Do not claim: actual extension UI verification while the current session still returns the URL policy block or native bridge trust block.

### Browser Plugin Hidden In App UI After Restart

- Type: `tool_runtime_error`, `environment_path_issue`, `workflow_hook_issue`
- Fingerprint: Browser runtime can connect through the official `plugins/browser/scripts/browser-client.mjs`, but the app plugin UI does not show Browser/browser-use after restart.
- Risk: agents may treat runtime success as UI recovery, leaving the user with an invisible plugin card and no way to inspect or toggle it in the app.
- Likely cause: `[marketplaces.openai-bundled].source` points at an active temporary or cache path such as `.tmp\bundled-marketplaces`, `tmp`, or `plugins\cache`, or `.codex-global-state.json` keeps `browser-use-bundled-plugin-auto-install-disabled` set to `true` after the browser plugin ID migrated from `browser-use` to `browser`.
- Additional confirmed cause: `plugin/read` for `browser` can report `enabled=true` and `availability=AVAILABLE` while `installed=false`. In that state the skill can still appear from cache, but the app plugin UI may omit the Browser card or fail to show it as installed.
- Additional confirmed cause: the repair helper can fail before checking plugin state when run under Windows PowerShell if it uses `ProcessStartInfo.ArgumentList`, sends generic JSON-RPC with a `jsonrpc` field, or runs the Python probe as `python -` from a hook process that already consumed hook JSON on stdin. Codex app-server accepts line JSON shaped as `id/method/params`; the maintained helper writes the Python probe to a temporary `.py` file and sends UTF-8 app-server requests.
- Not a cause: `browserify/browserify` is a CommonJS browser bundler and is not required for Codex Browser, Chrome Browser Use, native bridge trust, app-server plugin install state, or Chrome native messaging.
- Fix playbook:
  1. Preserve current `config.toml` and `.codex-global-state.json` backups before mutation.
  2. Point `[marketplaces.openai-bundled].source` at the installed Codex app bundle marketplace under `Program Files\WindowsApps\OpenAI.Codex_...\app\resources\plugins\openai-bundled` when available.
  3. Ensure `plugins\cache\openai-bundled\browser\<version>` exists; if the loader logs `failed to load plugin: plugin is not installed plugin="browser@openai-bundled"`, create a junction from that cache path to the installed app bundle `plugins\browser` directory.
  4. Run `maintenance\scripts\ensure-chrome-extension-origin.ps1`. It uses app-server `plugin/read` against `openai-bundled\.agents\plugins\marketplace.json` and `pluginName=browser`; if `summary.installed=false`, it calls `plugin/install` for the same marketplace file and plugin name, then re-reads until `summary.installed=true` and `summary.enabled=true`.
  5. Keep `[plugins."browser@openai-bundled"] enabled = true`; do not re-enable stale `[plugins."browser-use@openai-bundled"]` unless an active marketplace actually contains that plugin ID.
  6. Observe the legacy `browser-use-bundled-plugin-auto-install-disabled` state flag, but do not fight the official app by repeatedly rewriting generated state. Treat it as a residual app-state signal only when `browser@openai-bundled` is installed/enabled incorrectly despite the official marketplace source.
- Verification: `config.toml` parses, `ensure-chrome-extension-origin.ps1` reports an installed app bundle source, browser cache path, and `browser@openai-bundled is installed and enabled`, keep-codex-fast reports `openai-bundled ok`, the loader no longer reports missing `browser@openai-bundled` cache on the next turn, and the Browser runtime can list the `iab` backend. If `agent.browsers.list()` shows `type=iab` but selecting it reports `No active Codex browser pane available`, treat that as an app pane activation state, not a missing Browserify or plugin-cache dependency. UI drawer visibility still requires user- or app-side visual confirmation.
- Do not claim: UI recovery from runtime-only checks if the app drawer itself was not inspected.

### Chrome Native Host Manifest Points At Removed Codex App Version

- Type: `tool_runtime_error`, `environment_path_issue`
- Fingerprint: Chrome extension discovery says the Codex Chrome extension is installed and enabled, but `agent.browsers.get("extension")` or equivalent Chrome backend discovery returns no `extension` backend. `%LOCALAPPDATA%\OpenAI\extension\com.openai.codexextension.json` has a `path` under `Program Files\WindowsApps\OpenAI.Codex_<old version>...\extension-host.exe`, and `Test-Path` for that exact path is false.
- Risk: agents may trust `check-native-host-manifest.js --json` because it validates host name, registry path, and allowed origin, while missing that the manifest executable path no longer exists. This can lead to firewall, loopback, cache, or browser policy changes that do not address the root cause.
- Likely cause: Codex Desktop was updated, but the Chrome native messaging manifest stayed pinned to the previous packaged app version. The HKCU native messaging registry entry can still be valid because it points to the JSON manifest, not to the executable inside that manifest.
- Fix playbook:
  1. Capture `Get-AppxPackage *Codex*` and the manifest JSON before editing.
  2. Parse `%LOCALAPPDATA%\OpenAI\extension\com.openai.codexextension.json`; check `Test-Path -LiteralPath $manifest.path`.
  3. Locate the current app bundle host at `Get-AppxPackage *Codex*.InstallLocation\app\resources\plugins\openai-bundled\plugins\chrome\extension-host\windows\x64\extension-host.exe` and verify it exists.
  4. Back up the manifest, then update only the JSON `path` field to the current installed app bundle host. Keep `name`, `type`, and `allowed_origins` unchanged.
  5. Do not run `installManifest.mjs` or mutate Chrome profile state unless the Chrome skill or current user instruction explicitly allows that route.
- Verification: manifest JSON parses, `Test-Path` for the new `path` is true, `reg.exe query HKCU\Software\Google\Chrome\NativeMessagingHosts\com.openai.codexextension /ve` points at the same manifest, Chrome backend discovery lists `type="extension"`, and Chrome can open both a public page and local `127.0.0.1`/`localhost` smoke pages.
- Do not claim: Chrome is fixed solely because the extension is installed/enabled, because the native-host registry key exists, or because `check-native-host-manifest.js` reports `correct=true`.

### Browser And Chrome Recovery Must Not Fall Back To Project Browser Automation

- Type: `validation_gap`, `skill_or_doc_drift`
- Fingerprint: Browser or Chrome plugin verification is replaced with project-level browser automation, dependency installation, headless browser checks, or CDP-only checks after a Codex Browser/Chrome failure.
- Risk: agents may prove that some browser can render localhost while leaving the requested Codex native Browser or Chrome plugin broken.
- Fix playbook:
  1. Verify local HTTP reachability from shell first.
  2. Use the Codex native Browser backend for `iab` checks and the Codex Chrome extension backend for `extension` checks.
  3. If native backends remain unavailable, report the product/runtime blocker with direct evidence instead of substituting another browser automation stack.
- Verification: final evidence names the actual backend used (`iab` or `extension`) and includes URL/title/screenshot or navigation evidence from that backend.
- Do not claim: project-level browser automation, headless browser success, or external CDP success as evidence that Codex Browser or Codex Chrome plugin is healthy.

### Harness Self-Test Fixture Missing Current Hook Contract

- Type: `validation_gap`, `workflow_hook_issue`
- Fingerprint: live `doctor --tier full` passes, but `codex_agent_harness.py self-test` prints only `doctor failed in self-test`; rerunning doctor against the preserved temporary self-test root shows `hook_subagent_vowline` missing fixture-only files or markers.
- Risk: agents may chase the live hook implementation even though the mismatch is in the self-test fixture's synthetic root.
- Likely cause: a hook or skill contract changed, but `cmd_self_test` did not create the same minimal contract in its temporary root before calling `doctor_data(root)`.
- Fix playbook:
  1. Preserve the self-test temp root by monkeypatching or instrumenting `TemporaryDirectory`, then run `doctor --tier full --json --root <temp-root>`.
  2. Patch the self-test fixture, not the live hook, when the missing item exists in the live root and is absent only in the fixture.
  3. Keep the fixture minimal: create only the files and markers required by the doctor contract.
  4. Rerun `self-test`, `benchmark`, and `verify`.
- Verification: `self-test` exits `0`; `verify` exits `0` and `verification.latest.md` reports `self_test: pass` and `audit: pass`.
- Do not claim: a live hook regression until the same missing condition is reproduced in the real `%USERPROFILE%\.codex` root.

### Subagent Not Spawned Before Explicit Authorization

- Type: `workflow_hook_issue`, `validation_gap`
- Fingerprint: `[features].multi_agent = true` or PM workflow text exists, but no `spawn_agent` occurs until the user writes an explicit authorization phrase such as `subagent`, `spawn_agent`, `delegate`, or the configured localized equivalent.
- Risk: agents or reviewers may misdiagnose this as disabled subagents rather than the runtime authorization gate, or may accept a subagent's own `SUBAGENT_CALL not_used` report as evidence about the PM session.
- Likely cause: Codex runtime policy requires explicit user authorization before subagent tools are called; feature flags and workflow presets are capability only.
- Fix playbook:
  1. Inspect the target rollout JSONL for user text order and actual `spawn_agent` tool events.
  2. Compare hook classification: `delegationAuthorized=false` before explicit text, `true` after explicit text.
  3. Treat subagent notifications as candidate evidence; distinguish PM-level subagent use from nested subagent use.
  4. If authorization is absent and delegation would help, report the limitation instead of spawning.
- Verification: target thread shows no `spawn_agent` before explicit authorization and shows `spawn_agent` only after the authorization text, or the final report records `SUBAGENT_CALL not_used` with reason and residual risk.
- Do not claim: that `multi_agent = true`, a team preset, or a reviewer report proves subagents should have been spawned.

### Nested Parallel Subagent Tool Event Not Recorded

- Type: `workflow_hook_issue`, `validation_gap`
- Fingerprint: the PM calls `multi_tool_use.parallel` with nested `functions.spawn_agent` or related subagent tools, but `hooks/state/lightweight-status.json` keeps `subagentEvents=[]` and later evidence implies subagents were not used.
- Risk: final evidence can underreport PM-level delegation, and Stop-hook checks may rely only on prompt authorization instead of actual observed subagent tool use.
- Likely cause: PostToolUse checks only the wrapper tool name, so `multi_tool_use.parallel` hides nested `spawn_agent`, `wait_agent`, `send_input`, `close_agent`, or `resume_agent` recipient names.
- Fix playbook:
  1. Detect subagent tool use from both direct tool names and nested `recipient_name` values inside `multi_tool_use.parallel` payloads.
  2. Keep plain text mentions such as `WATCHER_REPORT` or `SUBAGENT_CALL` from creating subagent events.
  3. Add hook smoke coverage that runs a nested parallel `functions.spawn_agent` sample and verifies `subagentEvents` records `multi_tool_use.parallel`.
- Verification: `hook-policy-smoke` passes `posttooluse_records_nested_parallel_subagent_event` and still passes `posttooluse_text_mentions_do_not_create_subagent_events`.
- Do not claim: that a subagent's own `SUBAGENT_CALL not_used` declaration describes the parent PM session when the parent used `spawn_agent`.

### Hook Overblocks Toolchain Or MCP Maintenance

- Type: `workflow_hook_issue`, `security_boundary`
- Fingerprint: toolchain, MCP, CLI, package install, or generated setup cleanup work is denied by a broad hook rule even though the user explicitly requested workstation/tool maintenance.
- Risk: agents leave required tools half-installed, claim configured capability without runtime proof, or ask the user to operate around the harness.
- Fix playbook:
  1. Preserve the exact denied command and hook reason.
  2. Keep hard blocks for secret content access, irreversible destructive action, hook weakening without explicit scope, fake success, and out-of-scope mutation.
  3. Store prompt-derived authorization as a narrow state flag such as `hook_policy_change` or `toolchain_mcp_cli_maintenance`, not as raw prompt text.
  4. Allow read-only inspection and ordinary toolchain/MCP/CLI use/install to continue unless the specific action matches a remaining hard-block class.
- Verification: synthetic `UserPromptSubmit` plus `PreToolUse` samples prove an authorized hook-policy edit is observed, a safe toolchain command is observed, and secret/destructive denial cases still deny.
- Do not claim: broad hook disabling, blanket `permissionDecision=allow`, or bypassing final evidence checks as a valid fix.

### Hook Overblocks Reversible Cleanup Or Incident Recording

- Type: `workflow_hook_issue`, `validation_gap`
- Fingerprint: a needed cleanup under a temporary path is blocked as irreversible, or an `apply_patch` documentation/report edit is blocked only because it records the denied cleanup command text.
- Risk: agents leave temporary files behind, erase not-run evidence from reports, or avoid documenting the first mismatch.
- Fix playbook:
  1. Preserve the denied hook reason and the intended cleanup path.
  2. Prefer Windows Recycle Bin movement for removable files when cleanup is needed but permanent deletion is blocked.
  3. Keep permanent recursive cleanup blocked unless an existing scoped allow rule validates the resolved path and boundary.
  4. Allow documentation-only Markdown incident/report patches to record blocked cleanup cases; this is not permission to execute the cleanup.
- Verification: hook policy smoke includes `permanent_recursive_cleanup_still_blocked`, `recycle_bin_cleanup_allowed`, and `documented_blocked_cleanup_case_allowed`.
- Do not claim: that Recycle Bin cleanup is equivalent to permanent deletion, or that recording a blocked command grants future execution permission.

### Advisory PM Contract Without Verifiable State

- Type: `workflow_hook_issue`, `validation_gap`
- Fingerprint: `UserPromptSubmit` injects PM workflow text such as delegation authorization, English intent framing, or watcher expectations, but hook state stores only a prompt hash/workflow label and Stop checks do not require subagent evidence, `WATCHER_REPORT`, or `WATCHER_NOT_USED`.
- Risk: agents can skip the required workflow, omit authorized inspect/watcher subagents, and still satisfy final wording checks.
- Likely causes: treating hook reminders and structural document smoke tests as enforcement; missing structured state fields for task class, delegation authorization, intent frame, goal requirement, and watcher expectation.
- Fix playbook:
  1. Persist structured prompt-derived state: `taskClass`, `delegationAuthorized`, `goalRequired`, `watcherExpected`, and an English intent frame.
  2. Emit an actionable PM startup packet with L1-L4 classification and selected workflow continuation requirements.
  3. For L4 delegated incidents, Stop must require accepted/rejected subagent evidence plus watcher coverage, or explicit `WATCHER_NOT_USED` with risk and substitute check.
  4. Add a behavioral hook smoke test with a P0 delegated workflow prompt; do not rely only on document term checks.
- Verification: synthetic `UserPromptSubmit` output includes `task_class=L4`, goal action, watcher action, and delegation authorization; hook state contains the structured fields; Stop blocks a final message that omits watcher/subagent evidence for active L4 delegated work.
- Do not claim: that a reminder sentence or a worker-watcher document proves runtime PM behavior.

### L4 Stop Evidence Skipped After State Rewrite

- Type: `workflow_hook_issue`, `validation_gap`, `git_or_state_issue`
- Fingerprint: an L4 delegated prompt is recorded, then a later prompt or hook prompt rewrites the singleton `hooks/state/lightweight-status.json`; Stop sees no changed surface or tool event and allows finalization without subagent call evidence, watcher evidence, or anomaly trace.
- Risk: explicit subagent authorization becomes advisory only; the PM may not notice missing delegation or missing post-fix verification because the Stop hook reports `observed` instead of `not_ready`.
- Likely causes: Stop enforcement is gated on `hasSubstantiveActivity` only; watcher coverage accepts broad `subagent evidence` wording without `WATCHER_REPORT` or a complete `WATCHER_NOT_USED`; PostToolUse records subagent activity from plain text mentions such as `WATCHER_REPORT` in shell output.
- Fix playbook:
  1. Preserve the first mismatch with log ids, timestamps, prompt hash, Stop outcome, and state-file fields.
  2. Enforce L4 workflow evidence when `anomalyPauseExpected`, `subagentDecisionRequired`, or `watcherExpected` is true, even if no tool event or changed surface is present.
  3. Require concrete watcher coverage: `WATCHER_REPORT` plus accepted/rejected subagent evidence, or `WATCHER_NOT_USED` with reason, risk, substitute/direct check, and confidence impact.
  4. Record subagent events only from actual subagent tool names such as `spawn_agent`, `wait_agent`, `send_input`, `close_agent`, or `resume_agent`, not from read-only text mentions.
- Verification: `hook-policy-smoke` includes and passes `stop_enforces_l4_state_without_tool_events`, `stop_requires_concrete_watcher_artifact_or_omission_record`, and `posttooluse_text_mentions_do_not_create_subagent_events`.
- Do not claim: that a final report containing the right words proves the hook state was enforced.

### Synthetic Hook Smoke Pollutes Live State

- Type: `workflow_hook_issue`, `git_or_state_issue`
- Fingerprint: a synthetic `UserPromptSubmit` smoke test writes `hooks/state/lightweight-status.json`; a later real Stop hook treats the synthetic `taskClass`, `delegationAuthorized`, or `watcherExpected` as the current user prompt state.
- Risk: agents may satisfy a stale Stop reminder with final wording instead of tracing the control-plane mismatch, causing false workflow failures or false passes.
- Likely causes: smoke tests invoke the real hook script against the live CODEX_HOME state path and do not restore the previous state; Stop hook state is singleton and non-authoritative but still drives reminders.
- Fix playbook:
  1. Preserve the exact mismatch: original prompt classification, Stop-hook text, state file fields, and the smoke command/report timestamp.
  2. Make synthetic hook tests snapshot and restore the live state file, or run them against an isolated root/state path.
  3. Add a regression check that the state file is byte-for-byte restored after synthetic probes.
  4. Keep Stop-hook reminders narrow; do not treat restored or synthetic state as completion authority.
- Verification: `hook-policy-smoke` passes and includes `hook_policy_smoke_restores_live_state`; before/after state content is unchanged after the smoke run.
- Do not claim: that adding `WATCHER_NOT_USED` to final prose fixes a stale-state control-plane mismatch.

### Turn-Based Anomaly Calibration Missing

- Type: `workflow_hook_issue`, `validation_gap`
- Fingerprint: during one task turn, a hook, tool, report, or user observation contradicts the active workflow, but the agent continues the original build/ship path or patches the final report instead of pausing and tracing the first mismatch.
- Risk: the user sees process compliance theater: the system appears to satisfy wording while the workflow itself remains uncalibrated.
- Likely causes: hooks can enforce fixed checkpoints but not broad live judgment; agents do not reliably re-evaluate already-executed same-turn actions without an explicit pause/trace rule.
- Fix playbook:
  1. Pause the active path when an anomaly signal appears.
  2. Preserve the first mismatch and reclassify to debug/incident trace.
  3. Check overlap with Goal, Worker-Watcher, Stop hook, incident manual, and verification-loop processes before adding new governance.
  4. Resume only after root cause, bounded correction, direct verification, or blocked/continue status is recorded.
- Verification: L4 workflow/harness prompt reminders include anomaly calibration; hook state records `anomalyPauseExpected`; Stop requires pause/trace/root-cause and verification or blocked/continue language for active anomaly-calibration incidents.
- Do not claim: that feature correctness alone proves the user-facing workflow passed.

### Explicit Subagent Call Decision Missing

- Type: `workflow_hook_issue`, `subagent_drift`
- Fingerprint: the user authorizes or asks for subagents, but the final/status output does not state whether subagents were actually spawned or why they were not used.
- Risk: the user cannot tell whether delegation authorization changed execution, and agents may hide skipped subagent work behind generic completion language.
- Likely causes: subagent guidance is tied to task-class reminder text, or Stop only checks watcher coverage for L4 delegated incidents.
- Fix playbook:
  1. Persist a prompt-derived `subagentDecisionRequired` flag whenever delegation is authorized, independent of task class.
  2. Emit a final-evidence `SUBAGENT_CALL used` or `SUBAGENT_CALL not_used` requirement with reason, direct evidence or substitute check, and residual risk.
  3. Make Stop require the declaration for substantive work after explicit subagent authorization or an observed subagent tool event.
  4. Keep authorization detection narrow: `PM-led`, `team preset`, `workflow`, and `review` alone are not subagent authorization.
- Verification: synthetic delegated prompts include `Subagent call declaration required`; hook state records `subagentDecisionRequired`; Stop blocks final output missing exact `SUBAGENT_CALL used` or `SUBAGENT_CALL not_used` plus reason, evidence, and risk; PM-led/team preset wording alone does not set delegation authorization; an observed `spawn_agent`/subagent event also requires the final declaration.
- Limitation: if Stop receives no usable prior hook state and no prompt text, runtime enforcement cannot reconstruct explicit subagent authorization; the PM-facing AGENTS.md declaration remains the fallback contract.
- Do not claim: that enabled subagent capability or hook authorization proves subagents were called.

### Debugger Toolchain Ambiguity

- Type: `toolchain_issue`, `workflow_hook_issue`
- Fingerprint: a report says debugger support exists, but does not distinguish shim presence, current usability, and actual debugger invocation.
- Risk: agents may imply a debugger was used or is ready when only a wrapper file exists.
- Fix:
  1. Record debugger tools in `maintenance/AGENT_TOOL_REQUIREMENTS.md` and `toolchains/README.md` with active, conditional, or unavailable status.
  2. Verify active debugger wrappers with command evidence such as `gdb.cmd --version` and `cdb.cmd -version`.
  3. Treat `rust-gdb`/`rust-lldb` as conditional when Rustup reports `not applicable` for the active MSVC Rust toolchain.
  4. In final reports, say whether a debugger was used, available but not used, or conditional/unavailable.
- Verification: `check-toolchain-sources.ps1 -Json` includes debugger smoke checks for `gdb` and `cdb`, plus conditional Rust debugger wrapper checks.
- Do not claim: that a debugger was used unless a debugger command was invoked for the task evidence.

### Patch Grammar Failure

- Type: `tool_runtime_error`
- Fingerprint: `apply_patch` rejects input because the freeform patch does not match grammar.
- Fix:
  1. Retry with exact begin/end markers.
  2. Use one file operation hunk per target file where possible.
  3. Avoid JSON wrapping for the freeform patch.
- Verification: patch tool reports success and follow-up file read confirms content.

### Automation Scope Confusion

- Type: `codex_app_error`, `workflow_hook_issue`
- Fingerprint: a request to remind, monitor, or continue later is implemented as prose or a raw schedule string instead of an automation tool call.
- Fix:
  1. Use the automation tool for reminders, recurring runs, monitors, and thread wakeups.
  2. Prefer heartbeat for current-thread follow-ups, especially below one hour.
  3. Preserve existing automation fields when updating.
- Verification: automation create/update/view/delete result.

## Incident Record Template

Use this template when adding a new incident to this file or to another user-specified incident log.

```markdown
### YYYY-MM-DD short-title

- Status: open | mitigated | resolved | monitoring
- Type: primary_type
- Tags: secondary_tag, optional_tag
- Surface: agent role, tool, app area, file path, workflow, or repository
- Fingerprint: exact error fragment or concise symptom
- Impact: what was blocked or at risk
- Trigger: user action, command, tool call, or workflow step
- Root cause: confirmed cause, or `unknown` if not confirmed
- Fix: concrete steps taken
- Verification: command, tool result, diff, screenshot, or inspection used as proof
- Not run: skipped checks and exact reason
- Prevention: how future agents should avoid or recognize it
- Related: paths, commands, issue ids, or prior incident titles
```

## Seed Incident Records

### 2026-05-11 shell-command-wrapper-invalid-arguments

- Status: mitigated
- Type: `tool_runtime_error`
- Tags: `environment_path_issue`, `validation_gap`
- Surface: `shell_command` tool in Codex desktop session
- Fingerprint: `Io(Error { kind: InvalidInput, message: "batch file arguments are invalid" })` returned before execution for simple commands such as `pwd`, `Get-Location`, and `Get-Content`.
- Impact: normal shell-based file reads and validation could not be used.
- Trigger: attempting to read skill files and run simple PowerShell commands.
- Root cause: unknown; likely command transport or shell wrapper issue, not the command contents.
- Fix: used Node REPL for file reads and Python child-process validation; used `apply_patch` for file edits.
- Verification: Node REPL read files successfully, ran Python `quick_validate.py`, and the validator reported `Skill is valid!`.
- Not run: direct recovery of the `shell_command` runtime; root cause inside Codex desktop was not inspected.
- Prevention: if all shell commands fail before execution, treat it as a global tool/runtime issue and switch to another available read or execution surface while preserving the original failure.

## Pattern Entry Template

Use this when a single incident generalizes into a reusable pattern.

```markdown
### Pattern Name

- Type: primary_type
- Fingerprint: stable symptom or exact error fragment
- Risk: why this misleads agents or blocks work
- Likely causes: shortest useful list
- Fix playbook:
  1. First check
  2. Second check
  3. Patch or workaround
- Verification: direct evidence required before claiming completion
- Do not claim: tempting but invalid completion claim
```

## Update Rules

- Add a new pattern only after at least one concrete incident has evidence.
- Prefer updating an existing pattern over creating a near-duplicate.
- Keep entries short. Link to paths or commands instead of pasting long logs.
- Preserve failed attempts when they prevent future wasted work.
- Never mark an incident resolved only because a subagent, hook, or broad test said so.
- If a workaround is used, state whether the original failure remains unresolved.
- If the issue touches credentials, record metadata only unless the user explicitly allowed reading the secret file.

## Review Checklist

Before shipping an incident fix, answer these:

- Does the final claim match the user's original goal?
- Which exact evidence proves the behavior changed or the diagnosis is correct?
- Which checks were not run, and why?
- Did any fallback happen, and was it equivalent?
- Did any subagent claim require PM verification?
- Should the manual be updated with a new fingerprint, fix, or anti-pattern?
