# Codex Home Naming Convention

This document is an audit rule for `C:\Users\anise\.codex`.
It is not app configuration and it is not a completion gate.

## Active Names

Use these names only for live, intentionally managed surfaces:

- `maintenance\scripts`
- `maintenance\reports`
- `toolchains\shims`
- `config.toml`
- `.codex-global-state.json`
- `skills`
- `agents`
- `cache\codex_apps_tools`
- `local-environments`
- `profile.d`

## Forbidden Active Names

These names must not be active marketplace, plugin, toolchain, or config sources:

- `.tmp`
- `tmp`
- `vendor_imports`
- `bundled-marketplaces`
- `codex-runtimes`
- `openai-primary-runtime`
- `plugins\cache`
- `plugins\plugins`
- `skills\skills`
- `agents\agents`
- `wshobson-agents-scan`
- `quarantine`
- `quarantined`

## Visibility Rule

Tool, package, plugin, cache, skill, agent, and local-environment surfaces must
not be hidden by `.gitignore` purely because they are noisy. If they are active,
they should be visible during audit. If they are transient, they should be absent
or moved to the Recycle Bin.

Keep secrets, sessions, logs, SQLite databases, browser state, and hook state
ignored because they contain private or live app state.

## Runtime Rule

Runtime-generated temporary directories may exist only while the creating process
is using them. They must not be persisted in config, native messaging manifests,
marketplace sources, PATH, or hook policy.

Do not block `.tmp` or `tmp` with sentinel files. Codex uses `.tmp/marketplaces`
while registering and loading plugin marketplaces, so file sentinels at those
paths break the plugin UI. Audit these paths for size and active references
instead.

Exact path-name sentinel blockers may be used for confirmed non-runtime roots
only:

- `vendor_imports`
- `plugins\plugins`

These blockers are files or managed empty directories, not active sources.
Do not block `plugins\cache` with a sentinel file: Codex loads installed
plugins from that runtime cache path. Treat `plugins\cache` as an allowed
runtime cache and audit its contents for unexpected connectors instead.

When blocking a confirmed runtime recontamination path, `config.toml` may be kept
read-only after verified edits. Remove the read-only bit only for intentional app
configuration changes, then re-run the maintenance report.

If the app rewrites global runtime flags that control bundled auto-install or WSL
usage, `.codex-global-state.json` may also be kept read-only after verified edits.
This is a guard state, not a normal app preference editing mode.

## Archive Rule

Archives must use explicit archive names and must not be referenced as active
sources:

- `archived_*`
- `runtime-repair-*`
- `codex-logs-*`
- `keep-codex-fast-*`

## Recycle Rule

Deprecated tool, package, plugin, or cache directories should be moved to the
Recycle Bin first. Permanent deletion requires an explicit user instruction.
