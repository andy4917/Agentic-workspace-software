# Workstation Maintenance Protocol

This file governs future user requests to install, configure, enable, disable,
upgrade, remove, or repair workstation-level tools and Codex support surfaces.

## Managed Change Trigger

Apply this protocol when the user asks for any of these:

- tool, runtime, package manager, language SDK, compiler, CLI, or local library;
- MCP server, plugin, connector, app bundle, skill, agent definition, or shim;
- profile script, PATH-like source, config file, native host, browser extension,
  cache, local environment, or maintenance automation;
- performance, cleanup, repair, hygiene, or workstation reliability work.

## First-Pass Classification

Before mutating files, installing tools, changing config, moving logs, or
publishing externally, classify the request by workstation surface and risk
level. Use `maintenance/WORKSTATION_CONTROL_RUNBOOK.md` for the full taxonomy.
When the request is specifically about control-plane drift, duplication,
contradictions, stale guidance, hidden fallback, or workflow bloat, use that
runbook's Control-Plane Alignment section instead of creating a separate
workflow.

Required first-pass fields:

- `goal`: what the user is trying to accomplish.
- `surfaces`: affected surface classes, such as `active-runtime`,
  `managed-source`, `toolchain`, `logs-records`, `secrets-credentials`,
  `project-repository`, `cache-generated-state`, or `external-publish`.
- `risk_level`: `observe`, `draft`, `controlled-change`, or
  `high-risk-change`.
- `first_pass`: read-only, draft-only, or scoped mutation.
- `approval_boundary`: any trust, irreversible, secret, active-runtime,
  toolchain, deletion, or external-publish decision.
- `evidence_needed`: direct checks or documented not-run reasons.

Do not turn a meta-prompting plan into hooks, active config, scripts, package
operations, or deletion behavior unless the user separately requests that
implementation surface.

## Required Record

Every managed change must leave enough metadata for a future agent to maintain
it without rediscovery.

Record:

- `name`: stable English name.
- `source_class`: one of the source class names from
  `maintenance/NAMING_CONVENTION.md`.
- `owner`: official bundle, local package manager, user-local config, app cache,
  plugin marketplace, MCP config, or project-specific owner.
- `exact_path`: absolute path when practical, or a documented official runtime
  locator such as `load_workspace_dependencies`.
- `config_surface`: file, registry key, environment variable, or app setting that
  makes it active.
- `dependency_chain`: runtime, wrapper, package manager, credential source, and
  parent bundle dependencies.
- `scope`: global workstation, Codex-global, project-local, session-only, or
  out-of-scope.
- `verification`: command or tool result that proves it is usable.
- `rollback`: uninstall, restore from canonical source, or explicit no-rollback
  note for deleted retired residue.
- `handoff_update`: file or report updated for future maintenance.

## Global Project Chain Rule

Workstation-level tools make capabilities available; they do not by themselves
make any individual project ready for disciplined work. When a project task
depends on a workflow chain that is missing, stale, or mismatched, Codex must
follow `maintenance/PROJECT_WORKFLOW_CHAIN.md` and scaffold the smallest
project-local chain first.

This rule applies beyond frontend and backend work. It also covers data,
automation, CLI, browser extension, infrastructure, integration, documentation,
and maintenance projects.

## Source And Dependency Rules

- Prefer `official-bundle` and `workspace-runtime-bundle` assets when Codex
  provides the capability.
- Use `local-chain` only for capabilities Codex does not bundle or when the user
  explicitly requests a separate local install.
- Do not let a local package-manager shim hide an official bundle tool.
- Do not call bare commands when both a local install and an official bundle can
  satisfy the name.
- Assign dependencies explicitly. Example: an npm-backed MCP server depends on
  the `npx` local-chain wrapper, which must prefer bundled Node.
- Keep unrelated installs out of the active chain. If a tool exists but should
  not be used by Codex, mark it unused by Codex wrappers or quarantine it.

## Frontend-Only MCP Toggle Rule

MCP servers that are expensive, noisy, or only useful for a narrow workflow must
not be left always-on just because they are useful sometimes.

`chrome-devtools` is the managed frontend browser-observation example:

- `source_class`: `local-chain`.
- `owner`: user-global Codex MCP config; registered for app UI visibility and
  disabled while OFF.
- `exact_path`: `%USERPROFILE%\.codex\toolchains\shims\npx.cmd`.
- `dependency_chain`: Codex official bundled Node through the `npx.cmd` local
  wrapper -> npm package `chrome-devtools-mcp@latest` -> Chrome stable.
- `scope`: visible in Codex-global MCP settings; active only during confirmed
  frontend observation work.
- `default_args`: slim, headless, isolated, usage-statistics off, performance
  CrUX off.
- `activation`: `maintenance\scripts\chrome-devtools-mcp-toggle.ps1 on`.
- `deactivation`: `maintenance\scripts\chrome-devtools-mcp-toggle.ps1 off`.
- `verification`: `maintenance\scripts\chrome-devtools-mcp-toggle.ps1 status`,
  `verify-package`, app tool discovery after reload, and one safe browser
  observation when the tools are exposed.
- `rollback`: run `off` to restore `enabled = false`; use `codex mcp remove
  chrome-devtools` only when the settings entry should disappear completely.
  Any pre-change config copy is a transient `%TEMP%\codex-mcp-config-{guid}.toml`
  file and is deleted after success or rollback handling, not retained runtime
  fallback state.

Other frontend registry tools, including shadcn, are CLI or project-local
fallbacks under the current minimal MCP baseline. Do not add them as global MCPs
without a future current user instruction.

Do not directly edit `config.toml` for this toggle unless the Codex CLI command
itself is confirmed broken. If manual repair becomes necessary, document the
exact reason, sync from managed `config.d`, and update `MCP_RUNTIME_STATUS.md`.

`context7` is uninstalled from the active global MCP baseline:

- remove the MCP registration from managed and live config;
- stop any `@upstash/context7-mcp` process before treating runtime cleanup as
  complete;
- use official project documentation, an installed task-specific documentation
  MCP, or web search for version-sensitive third-party library facts.

`memento` is retired from the active Codex PM memory baseline:

- remove or disable the MCP registration in live config;
- stop any local Memento/PostgreSQL support process before deleting runtime
  source/state;
- keep historical reports as evidence, not active health checks;
- do not recreate legacy `memsearch`, raw `memories`, or Memory/RAG fallback
  surfaces.

## Handoff Requirement

For every non-trivial workstation maintenance pass, update at least one durable
handoff surface:

- the current thread `COMPACT_HANDOFF.md` when working inside a thread workspace;
- `maintenance/MCP_RUNTIME_STATUS.md` for MCP behavior or scope;
- `maintenance/AGENT_TOOL_REQUIREMENTS.md` for tool source policy;
- `maintenance/NAMING_CONVENTION.md` for source class or naming rules;
- a current local report under ignored `reports/*.latest.*` when recording
  inventory.

The handoff must include accepted evidence, not-run checks, residual risks, and
the next verification command.

For cache, log, memory, folder, file, or live-copy synchronization work, also use
`maintenance/CODEX_STATE_MANAGEMENT.md` as the management map. That document
defines the active cache/log/memory classes, the repo-to-runtime sync direction,
and the Codex self-inspection loop that verifies the current environment.

For Computer Use, Chrome Use, Browser Use, Chrome DevTools MCP, plugin native
host, or browser/desktop automation target issues, also use
`maintenance/AUTOMATION_TARGET_BOUNDARY.md`. Treat those tools as one
automation-risk family for target classification, and prefer structured routes
over GUI control-plane automation.

For memory, recall, remembered preferences, or global/project boundary issues,
also use `maintenance/MEMORY_BOUNDARY_POLICY.md`. Do not persist or generalize
memory-like information until it is classified as `global-settings` or
`project-scope`.

## Verification Layers

Use `maintenance/WORKSTATION_LAYERING.md` to avoid making optional local
runtime substrates block unrelated managed-source checks.

- `repo`: `python maintenance/scripts/codex_agent_harness.py repo-verify`
  checks tracked source quality and is suitable for CI or clean checkouts.
- `scaffold`: `validate-codex-scaffold.ps1 -Json` checks live `.codex`
  scaffold health without reviving retired MCP runtimes.
- `p0`: `codex-p0-integrity-loop.ps1 -Json` runs the full control-plane closure
  loop from a clean tree.
- `compat`: `codex_agent_harness.py verify` runs the current compatibility
  wrapper across repo verification, tier smoke, live scaffold validation, P0
  report-only, MCP list, and `codex doctor`.
- `no-mistakes`: repository handoff outer gate for non-self-certified
  validation, safe push, PR, CI, release, merge handoff, and test/TDD handoff.
  Use `%USERPROFILE%\.codex\toolchains\shims\no-mistakes.cmd` after the
  relevant local checks are coherent, but do not invoke it recursively from
  inside a no-mistakes-spawned gate worktree or agent step.

Hook route reload boundary:

- When hook command routes change in `config.d/20-hooks.toml`, regenerate both
  managed and live `config.toml`, then treat the current Codex app-server as
  potentially stale until direct process evidence or an app-server restart shows
  it is no longer launching the previous hook command.
- Do not run no-mistakes, broad Git publishing, or other hook-heavy workflows
  while current process evidence shows
  `.codex\toolchains\shims\pwsh.cmd` launching `compact-codex-hook.ps1`.
  This is a session-cache/runtime-reload issue, not a source-file pass.
- Before resuming a hook-heavy workflow after a hook route change, check for
  stale route processes and visible terminal windows. If stale route processes
  appear only transiently during the current session, restart Codex Desktop or
  the active app-server before claiming the foreground-terminal issue fixed for
  the user's current session.

Choose the smallest layer that proves the task. Escalate to `full` whenever
hooks, MCP baseline, toolchains, browser/native host state, Goal governance,
Worker-Watcher, or release handoff is touched.

For workflow-governance or multi-agent control-plane changes, also update the
worker-watcher surfaces when applicable:

- `maintenance/WORKER_WATCHER_NORMALIZED_HANDOFF.md`
- `maintenance/GOAL_INTEGRITY_GATE.md`
- `maintenance/templates/*` handoff and gate templates
- the matching smoke eval under `evals/`

## Default Checks

Run the smallest relevant set:

```powershell
%USERPROFILE%\.codex\toolchains\shims\python.cmd %USERPROFILE%\.codex\maintenance\scripts\codex_agent_harness.py repo-verify
powershell.exe -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.codex\maintenance\scripts\check-toolchain-sources.ps1
%USERPROFILE%\.codex\toolchains\shims\python.cmd %USERPROFILE%\.codex\maintenance\scripts\codex_agent_harness.py doctor --json
powershell.exe -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.codex\maintenance\scripts\validate-codex-scaffold.ps1 -Json
powershell.exe -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.codex\maintenance\scripts\codex-p0-integrity-loop.ps1 -Json -ProcessTimeoutSeconds 120
powershell.exe -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.codex\maintenance\scripts\codex-home-maintenance.ps1 -Mode Report -ReportRoot %USERPROFILE%\Documents\Codex\reports
powershell.exe -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.codex\maintenance\scripts\check-staged-sensitive-diff.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.codex\maintenance\scripts\check-worktree-sensitive-diff.ps1
git -C %USERPROFILE%\.codex status --short
```

Use report-only P0 runs only for read-only audits or while intentionally keeping
the worktree dirty. Before publishing a control-plane change, run the full P0
loop from a clean managed-source tree so dead app-server cleanup and Scoop health
are current evidence, not skipped residual risk. `-SkipScoop` is not a closure
mode; it records a failed evidence gap.

When hooks, harness, or Codex global policy changed, also run the compatibility
verify wrapper after the direct validator/P0 checks:

```powershell
%USERPROFILE%\.codex\toolchains\shims\python.cmd %USERPROFILE%\.codex\maintenance\scripts\codex_agent_harness.py verify
```

The compatibility wrapper must run the current control-plane stack
(`repo-verify`, tier smoke, live scaffold validation, P0 report-only, MCP list,
and `codex doctor`). Use the full P0 loop separately from a clean tree before
publishing.

## Completion Rule

Do not claim a workstation maintenance request is complete until inspected and
changed surfaces are named, the risk level is stated, the changed source is
named, the active path is explicit when applicable, dependencies are documented,
verification ran or has a concrete not-run reason, and handoff is current.
