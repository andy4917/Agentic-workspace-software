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
- `owner`: user-global Codex MCP config while ON; absent from config while OFF.
- `exact_path`: `%USERPROFILE%\.codex\toolchains\shims\npx.cmd`.
- `dependency_chain`: Codex official bundled Node through the `npx.cmd` local
  wrapper -> npm package `chrome-devtools-mcp@latest` -> Chrome stable.
- `scope`: Codex-global only during confirmed frontend work.
- `default_args`: slim, headless, isolated, usage-statistics off, performance
  CrUX off.
- `activation`: `maintenance\scripts\chrome-devtools-mcp-toggle.ps1 on`.
- `deactivation`: `maintenance\scripts\chrome-devtools-mcp-toggle.ps1 off`.
- `verification`: `maintenance\scripts\chrome-devtools-mcp-toggle.ps1 status`,
  `verify-package`, app tool discovery after reload, and one safe browser
  observation when the tools are exposed.
- `rollback`: run `off`; a pre-change config backup is stored under ignored
  local state at `%USERPROFILE%\.codex\state\mcp-toggle-backups`.

Do not directly edit `config.toml` for this toggle unless the Codex CLI command
itself is confirmed broken. If manual repair becomes necessary, document the
exact reason, restore a backup path, and update `MCP_RUNTIME_STATUS.md`.

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

## Default Checks

Run the smallest relevant set:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.codex\maintenance\scripts\check-toolchain-sources.ps1
git -C %USERPROFILE%\.codex status --short
```

When hooks, harness, or Codex global policy changed, also run:

```powershell
%USERPROFILE%\.codex\toolchains\shims\python.cmd %USERPROFILE%\.codex\maintenance\scripts\codex_agent_harness.py verify
```

## Completion Rule

Do not claim a workstation maintenance request is complete until the changed
source is named, the active path is explicit, dependencies are documented,
verification ran or has a concrete not-run reason, and handoff is current.
