# shadcn MCP

This is the managed record for the global shadcn/ui MCP server.

## Managed Capability

- `name`: `shadcn`
- `source_class`: `local-chain`
- `owner`: Codex user-global MCP config
- `exact_path`: `%USERPROFILE%\.codex\toolchains\shims\npx.cmd`
- `config_surface`: `%USERPROFILE%\.codex\config.toml`
- `dependency_chain`: Codex official bundled Node through `.codex\toolchains\shims\npx.cmd` -> npm package `shadcn@latest` -> shadcn/ui registries and project `components.json`
- `scope`: Codex-global frontend work; project registry behavior depends on the confirmed frontend root
- `default_args`: `-y shadcn@latest mcp`
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

Last checked on 2026-05-13:

- `codex mcp get shadcn --json` returned `enabled=true`.
- `codex mcp list` showed `shadcn` with `Status enabled`.
- `shadcn@latest mcp --help` succeeded through the `.codex` `npx.cmd` wrapper.
- CLI fallback `shadcn@latest docs button` succeeded and returned the button
  docs and examples summary.
- CLI fallback `shadcn@latest view button` succeeded and returned the button
  registry item JSON.
- CLI fallback command `shadcn@latest search @shadcn -q "button"` and the
  reordered `search --query button @shadcn` form both failed in this environment
  with `missing required argument 'registries'`; do not claim search fallback is
  verified until this is rechecked against the active CLI version.

Not checked:

- The current already-running Codex session does not expose newly added shadcn
  MCP tools. Restart or reload the app/session before expecting active
  `mcp__shadcn__...` tools.
- No project-local `components.json`, Storybook, or frontend observation gate was
  verified from this projectless thread.
