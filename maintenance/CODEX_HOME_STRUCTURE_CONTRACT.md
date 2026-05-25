# Codex Home Structure Contract

This Markdown file is intentionally stale-tolerant. It records the maintenance
principle for `%USERPROFILE%\.codex`, not the current path inventory.

Freshness-sensitive structure data lives in:

```text
maintenance\CODEX_HOME_STRUCTURE_STATE.json
```

Generated current observations live in:

```text
maintenance\reports\codex-native-alignment.latest.json
```

## Rule

- Markdown is for principles, rationale, historical reports, and human handoff
  notes that can age without breaking the workstation.
- JSON is for current expected paths, forbidden active paths, enabled official
  plugin ids, toolchain alignment criteria, automation schedules, and latest
  observed native alignment status.
- Root `maintenance\*.md` classification is a current operational fact. Keep
  the classification in `maintenance\CODEX_HOME_STRUCTURE_STATE.json`; do not
  create a second Markdown inventory for it.
- Official Codex Desktop and primary runtime files stay app-owned. `.codex`
  records policy, wrappers, user settings, and checks; it does not mirror or
  patch official bundles.
- Official marketplace path checks validate enabled configured plugins. Disabled
  or unconfigured official manifest entries are not local `.codex` drift.
- App-generated `.tmp` runtime state is not all equivalent:
  `.tmp\bundled-marketplaces` and `.tmp\marketplaces` can be bounded app-owned
  runtime state. Their contents may be removed when they grow stale or large;
  leaving an empty placeholder directory is acceptable when current checks do
  not repopulate it. `.tmp\plugins`, `.tmp\plugins.sha`, `vendor_imports`, and
  incomplete `.tmp\plugins-clone-*` directories are cleanup targets.
- If an MD file and a JSON file disagree on a current operational fact, treat the
  JSON file as the maintenance baseline and update the MD only if the principle
  changed.

## Maintenance Entry Point

Before operating-level cleanup, plugin cache work, official app/runtime
alignment, or toolchain repair:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.codex\maintenance\scripts\check-codex-native-alignment.ps1 -Json -WriteReport
```

Use `-CheckStoreUpgrade` when Store update availability matters.

## Update Rule

- Update `maintenance\CODEX_HOME_STRUCTURE_STATE.json` when the current expected
  root shape, active source boundary, official plugin ids, forbidden path set,
  recurring automation schedule, toolchain criteria, root maintenance Markdown
  classification, or official native-alignment criteria change.
- Leave historical Markdown reports as provenance unless they are actively
  misleading a current workflow.
- Do not add another Markdown inventory when a JSON field can carry the current
  state.
