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
- `rollback`: uninstall, restore, quarantine, or Recycle Bin note.
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

`chrome_devtools_observe` is the managed frontend browser-observation example:

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
  chrome_devtools_observe` only when the settings entry should disappear
  completely. A pre-change config backup is stored under ignored local state at
  `%USERPROFILE%\.codex\state\mcp-toggle-backups`.

`shadcn` is the managed frontend registry MCP:

- `source_class`: `local-chain`.
- `owner`: user-global Codex MCP config.
- `exact_path`: `%USERPROFILE%\.codex\toolchains\shims\npx.cmd`.
- `dependency_chain`: Codex official bundled Node through the `npx.cmd` local
  wrapper -> npm package `shadcn@latest` -> shadcn/ui registry and project
  `components.json`.
- `scope`: Codex-global frontend work; project-specific registry behavior still
  depends on the confirmed frontend root and its `components.json`.
- `default_args`: `-y shadcn@latest mcp`.
- `verification`: `codex mcp list`, `codex mcp get shadcn --json`, active-session
  MCP tool injection after app/session reload, and one safe read-only registry
  call. If MCP is not injected, use CLI fallback such as `shadcn docs button` or
  `shadcn view button` through the `.codex` `npx.cmd` wrapper.
- `rollback`: `codex mcp remove shadcn` if the global settings entry is no
  longer wanted.

Do not directly edit `config.toml` for this toggle unless the Codex CLI command
itself is confirmed broken. If manual repair becomes necessary, document the
exact reason, restore a backup path, and update `MCP_RUNTIME_STATUS.md`.

`memento` is the managed Codex PM memory MCP:

- `source_class`: `local-chain`.
- `owner`: user-global Codex MCP config plus a clean local source checkout.
- `exact_path`: `%USERPROFILE%\.codex\tools\memento-mcp`.
- `dependency_chain`: Codex official bundled Node -> local `memento-mcp`
  checkout -> dedicated PostgreSQL 18 cluster under
  `%USERPROFILE%\.codex\state\memento-mcp\pgdata` -> pgvector extension.
- `scope`: Codex-global PM memory support only; not project completion
  authority and not a replacement for AGENTS, hooks, scorecard, Memento gates,
  tests, runtime output, or PM verification.
- `verification`:
  `maintenance\scripts\memento-mcp-runtime.ps1 verify`.
- `rollback`: stop with `maintenance\scripts\memento-mcp-runtime.ps1 stop`,
  remove or disable the `memento` MCP registration with Codex CLI only when the
  user explicitly asks, and preserve the ignored state directory unless the user
  explicitly requests destructive cleanup.
- `legacy_boundary`: `toolchains\shims\memsearch.*` and
  `maintenance\scripts\check-memory-rag-status.ps1` are retired legacy
  Memory/RAG surfaces and must not be treated as active fallback.

## Handoff Requirement

For every non-trivial workstation maintenance pass, update at least one durable
handoff surface:

- the current thread `COMPACT_HANDOFF.md` when working inside a thread workspace;
- `maintenance/MCP_RUNTIME_STATUS.md` for MCP behavior or scope;
- `maintenance/AGENT_TOOL_REQUIREMENTS.md` for tool source policy;
- `maintenance/NAMING_CONVENTION.md` for source class or naming rules;
- a maintenance report under `maintenance/reports` when recording inventory.

The handoff must include accepted evidence, not-run checks, residual risks, and
the next verification command.

For workflow-governance or multi-agent control-plane changes, also update the
worker-watcher surfaces when applicable:

- `maintenance/WORKER_WATCHER_NORMALIZED_HANDOFF.md`
- `maintenance/GOAL_INTEGRITY_GATE.md`
- `maintenance/templates/*` handoff and gate templates
- the matching smoke eval under `evals/`

## Default Checks

Run the smallest relevant set:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.codex\maintenance\scripts\check-toolchain-sources.ps1
%USERPROFILE%\.codex\toolchains\shims\python.cmd %USERPROFILE%\.codex\maintenance\scripts\codex_agent_harness.py doctor --json
powershell.exe -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.codex\maintenance\scripts\memento-mcp-runtime.ps1 verify
powershell.exe -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.codex\maintenance\scripts\codex-home-maintenance.ps1 -Mode Report
powershell.exe -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.codex\maintenance\scripts\check-staged-sensitive-diff.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.codex\maintenance\scripts\check-worktree-sensitive-diff.ps1
git -C %USERPROFILE%\.codex status --short
```

When hooks, harness, or Codex global policy changed, also run:

```powershell
%USERPROFILE%\.codex\toolchains\shims\python.cmd %USERPROFILE%\.codex\maintenance\scripts\codex_agent_harness.py verify
```

The harness defaults to its installed CODEX_HOME root when invoked by absolute
script path, so this command does not require the shell current directory to be
`%USERPROFILE%\.codex`. Use `--root` only when intentionally verifying another
harness root.

## Completion Rule

Do not claim a workstation maintenance request is complete until inspected and
changed surfaces are named, the risk level is stated, the changed source is
named, the active path is explicit when applicable, dependencies are documented,
verification ran or has a concrete not-run reason, and handoff is current.
