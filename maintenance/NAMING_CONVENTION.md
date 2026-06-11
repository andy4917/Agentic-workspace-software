# Codex Home Naming Convention

This document is an audit rule for `%USERPROFILE%\.codex`.
It is not app configuration and it is not a completion gate.

## Active Names

Use these names only for live, intentionally managed surfaces:

- `maintenance\scripts`
- `reports\*.latest.*`
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
- `retired-residue`: deprecated, disabled, archived, or backup surfaces that are
  not active runtime truth and should not be restored without current evidence.
- `managed-install-record`: a durable maintenance note that names the exact
  active path, source class, owner, dependency chain, verification, rollback, and
  handoff update for a workstation-level install or configuration change.

Do not call a copied official bundle a local-chain package. Do not call a
package-manager shim an official-bundle tool just because Codex can execute it.
For bundled tools, local duplicate installs must be removed, quarantined, or
explicitly marked unused by Codex wrappers.

When a user requests a future installation or configuration, add the resulting
surface to these source classes instead of leaving it as an unnamed local tool.
If it is only a support dependency, name the parent dependency chain that owns it.

## Behavioral Naming Rule

Names borrowed from public software folklore or naming catalogs are allowed only
when the name maps to observable behavior in this workstation. The name must help
an auditor predict ownership, lifecycle, risk, or boundary behavior without
reading unrelated history.

Use these metaphor names narrowly:

- `root`, `tree`, `leaf`: real hierarchy or process ownership only.
- `adapter`, `facade`, `wrapper`, `shim`: boundary translation only.
- `heartbeat`, `canary`: active liveness or regression signal only.
- `breadcrumb`: intentional trace evidence left for later audit only.
- `sandbox`: isolated work that cannot mutate the active runtime by accident.
- `retired-residue`: explicit classification for suspicious or deprecated
  surfaces after they are proven inactive.
- `cache`: generated data that must not become the configured source of truth.

Avoid clever names for operational surfaces. Terms such as `magic`, `god`,
`spaghetti`, `slop`, or joke names may appear in review prose or external skill
names, but active files and directories should use the concrete failure class:
`stale-state`, `unsupported-success`, `hidden-fallback`, `duplicate-root`,
`orphan-process`, `runtime-cache`, or `retired-residue`.

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
or removed after classification.

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

- `plugins\plugins`

These blockers are files or managed empty directories, not active sources.
Do not block `vendor_imports` or `plugins\cache` with a sentinel file: Codex may
create `vendor_imports` for curated skill or onboarding cache metadata and loads
installed plugins from `plugins\cache`. Treat both as allowed runtime cache paths
and audit their contents for unexpected active sources instead.

When blocking a confirmed runtime recontamination path, `config.toml` may be kept
read-only after verified edits. Remove the read-only bit only for intentional app
configuration changes, then re-run the maintenance report.

If the app rewrites global runtime flags that control bundled auto-install or WSL
usage, `.codex-global-state.json` may also be kept read-only after verified edits.
This is a guard state, not a normal app preference editing mode.

## Retired Residue Rule

Archived, disabled, backup, or retired roots must not be referenced as active
sources and should not remain as fallback state after the user authorizes
cleanup:

- `archived_*`
- `runtime-repair-*`
- `codex-logs-*`
- `retired-tool-*`

## Delete Rule

Deprecated tool, package, plugin, or cache directories may be deleted directly
after explicit user authorization, path-boundary verification, and reparse-point
descendant scanning. If the target or any descendant is a junction, symlink, or
other reparse point, or if the descendant scan fails, stop at classification
instead of deleting or creating another archive.
