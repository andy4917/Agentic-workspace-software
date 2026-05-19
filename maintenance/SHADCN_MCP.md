# shadcn MCP

This is the managed record for the global shadcn/ui MCP server.
It records policy and setup rationale, not a guarantee that tools are exposed in
the current Codex session.

## Managed Capability

- `name`: `shadcn`
- `source_class`: `local-chain`
- `owner`: Codex user-global MCP config
- `exact_path`: `%USERPROFILE%\.codex\toolchains\shims\npx.cmd`
- `config_surface`: `%USERPROFILE%\.codex\config.toml`
- `dependency_chain`: Codex official bundled Node through `.codex\toolchains\shims\npx.cmd` -> npm package `shadcn@latest` -> shadcn/ui registries and project `components.json`
- `scope`: Codex-global frontend work; project registry behavior depends on the confirmed frontend root
- `default_args`: `-y shadcn@latest mcp`
- `default_status`: enabled in global Codex config; active tool exposure still
  depends on app/session reload and tool injection
- `rollback`: `codex mcp remove shadcn`

## Use Policy

Use shadcn MCP for frontend work that needs shadcn/ui registry browsing,
searching, component documentation, block discovery, or install planning.

Do not claim MCP capability from configuration alone. The active session must
expose shadcn MCP tools and complete one safe read-only registry call before the
status is `MCP_CONFIRMED`.

If MCP tools are not injected in the active session, use CLI fallback through the
same `.codex` `npx.cmd` wrapper:

```powershell
%USERPROFILE%\.codex\toolchains\shims\npx.cmd -y shadcn@latest docs button
%USERPROFILE%\.codex\toolchains\shims\npx.cmd -y shadcn@latest view button
```

Run `search --help` before using registry search because the current CLI reports
different argument requirements than the workstation control plan's example.

## Verification

Last checked on 2026-05-15:

- `codex mcp get shadcn --json` initially returned `enabled=false`; the
  2026-05-15 MCP active-use refresh changed global config to `enabled=true`.
- `codex mcp list` through
  `%USERPROFILE%\.codex\toolchains\shims\codex.cmd` succeeded after the change
  and showed `shadcn` with `Status enabled`.
- `codex mcp get shadcn --json` returned `enabled=true`.
- `shadcn@latest mcp --help` succeeded through the `.codex` `npx.cmd` wrapper.
- CLI fallback `shadcn@latest docs button` succeeded and returned the button
  docs and examples summary.
- CLI fallback `shadcn@latest view button` succeeded and returned the button
  registry item JSON.
- CLI fallback `shadcn@latest search --help` succeeded and confirmed the current
  search syntax requires one or more registry arguments, such as `@shadcn`, plus
  optional `--query`.

Not checked:

- The current already-running Codex session may not expose newly enabled shadcn
  MCP tools until reload. Restart or reload the app/session before expecting
  active `mcp__shadcn__...` tools, then perform one safe read-only registry
  call before claiming `MCP_CONFIRMED`.
- No project-local `components.json`, Storybook, or frontend observation gate was
  verified from this projectless thread.
