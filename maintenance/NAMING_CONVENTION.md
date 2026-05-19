# Codex Home Naming Convention

This document is an audit rule for `%USERPROFILE%\.codex`.
It is not app configuration and it is not a completion gate.

Use `maintenance\CODEX_HOME_STRUCTURE_STATE.json` as the current normal-tree and
official/user ownership baseline before changing these names during
operating-level maintenance. This Markdown file records naming rationale only.

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

## Source Class Names

Use these terms in maintenance docs, reports, and review notes:

- `official-bundle`: files shipped by Codex Desktop, the WindowsApps Codex
  package, or the Codex primary workspace runtime. These are official runtime
  assets and should be preferred whenever the requested tool exists there.
- `app-bundle-bin`: the official Codex command bundle under
  `%LOCALAPPDATA%\OpenAI\Codex\bin` or the WindowsApps app resources.
- `workspace-runtime-bundle`: the official Codex primary runtime dependency
  bundle surfaced by `load_workspace_dependencies`.
- `local-wrapper`: a small `.cmd` or `.ps1` entry point owned by this `.codex`
  tree. Wrappers select a source class and must be easy to audit.
- `local-chain`: user-installed package manager, language runtime, compiler,
  SDK, or MCP server used because Codex does not bundle that capability.
- `runtime-cache`: app-generated cache that may be active but must not become a
  configured source of truth.
- `recycle-bin-removal`: Recycle Bin move or direct removal record for
  deprecated local tools, duplicate wrappers, and stale caches.
- `managed-install-record`: a durable maintenance note that names the exact
  active path, source class, owner, dependency chain, verification, rollback, and
  handoff update for a workstation-level install or configuration change.

Do not call a copied official bundle a local-chain package. Do not call a
package-manager shim an official-bundle tool just because Codex can execute it.
For bundled tools, local duplicate installs must be removed, moved to the
Recycle Bin, or explicitly marked unused by Codex wrappers.

When a user requests a future installation or configuration, add the resulting
surface to these source classes instead of leaving it as an unnamed local tool.
If it is only a support dependency, name the parent dependency chain that owns it.

## Encoding Rule

Operational files that can be parsed or executed by hooks, shells, MCP loaders,
or maintenance scripts must be ASCII English unless a format explicitly requires
Unicode data. This includes `hooks`, `toolchains`, `maintenance/scripts`,
`codex-goals` templates, config snippets, rules, and operational policy docs.
User-facing final responses may still be Korean.

## Forbidden Active Names

These names must not be active marketplace, plugin, toolchain, or config sources:

- `.tmp`
- `tmp`
- `vendor_imports`
- `bundled-marketplaces`
- `codex-runtimes`
- `plugins\cache\openai-primary-runtime`
- `plugins\plugins`
- `plugins\local-marketplaces`
- `skills\skills`
- `agents\agents`
- `wshobson-agents-scan`

## Duplicate Prevention Rule

No active directory may contain a direct child directory with the same name,
case-insensitively. This is a hard workstation-maintenance rule, not a style
preference. Examples that must stay absent:

- `skills\skills`
- `agents\agents`
- `plugins\plugins`
- `toolchains\toolchains`
- `local-environments\local-environments`
- any `<name>\<same-name>` pair under `%USERPROFILE%\.codex` or
  `%USERPROFILE%\.agents`

Do not solve a duplicate by leaving an empty placeholder, sentinel, hidden
folder, `.bak` folder, or "old/new/copy" sibling in an active lookup path. Pick
one canonical active owner and move the other copy to the Recycle Bin or to a
dated archive/quarantine root that is not used for runtime discovery.

Cross-root skill duplicates are also forbidden as active surfaces unless a
written transition record names the primary owner, the compatibility reason, and
the removal condition. The normal primary skill roots are:

- `%USERPROFILE%\.agents\skills`: shared user-global skills.
- `%USERPROFILE%\.codex\skills`: Codex-home-specific operational skills that do
  not duplicate a shared user-global skill.

If the same skill exists in both roots, prefer `%USERPROFILE%\.agents\skills`
unless a current config, hook, or skill loader requires the `.codex` copy. Do
not create new compatibility mirrors.

Run this check after directory-level maintenance:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.codex\maintenance\scripts\check-naming-conventions.ps1 -Json
```

The check is a guardrail for current and future work. A pass means no known
same-name nested active directory or forbidden duplicate root is present in the
checked roots; it does not prove every archived copy is semantically obsolete.

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

Do not block `.tmp`, `tmp`, or any other regeneration path with sentinel files.
Codex uses `.tmp/marketplaces` while registering and loading plugin marketplaces,
so file sentinels at those paths break the plugin UI. Audit these paths for size
and active references instead.

Exact stale names such as `vendor_imports` or `plugins\plugins` must stay absent.
If they reappear inside `%USERPROFILE%\.codex`, remove them or move them to the
Recycle Bin after confirming the resolved path stays under `.codex`. Do not leave
placeholder files or managed empty directories as blockers.

Do not block `plugins\cache` with a sentinel file: Codex loads installed plugins
from that runtime cache path. Treat `plugins\cache` as an allowed runtime cache,
audit its contents for unexpected plugin IDs, and remove stale cache entries that
are not present in the active official marketplace when safe.

Do not use read-only attributes as a routine guard for `config.toml` or
`.codex-global-state.json`. Make intentional edits with a backup, verify the
loaded state, and keep the files writable for the official app unless the user
explicitly asks for a temporary read-only investigation.

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
