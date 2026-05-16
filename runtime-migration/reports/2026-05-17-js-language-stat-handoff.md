# JS Language Stat Handoff

Date: 2026-05-17

## Scope

- Repository: `andy4917/Agentic-workspace-software`
- Local root: `%USERPROFILE%\.codex`
- Request: restart the Rust/Python migration work after GitHub still reports
  JavaScript above 70%.
- Boundary: Memento MCP remains excluded from rewrite decisions.

## Evidence

- GitHub languages API before this branch:
  - `JavaScript`: `1546827`
  - `Python`: `459171`
  - `PowerShell`: `189800`
  - `Batchfile`: `9932`
  - Total: `2205730`
  - JavaScript share: `70.13%`
- Local tracked JS/TS scan before committing this slice:
  - JS/TS tracked bytes before deleting the local skill helper: `1548856`
  - `plugins/patched/openai-bundled/**` bytes marked vendored by
    `.gitattributes`: `1545246`
  - remaining counted JS bytes after vendored marker and Python rewrite: `0`

## Decision

The GitHub language-stat mismatch is caused by plugin-owned app-cache JavaScript,
not by owned runtime-migration source. This slice does not rewrite those plugin
files. It classifies them as handoff surfaces and marks the OpenAI-bundled
patched plugin cache as `linguist-vendored` so GitHub does not present vendored
plugin code as project-owned JavaScript.

The one small local skill helper that was still counted as project JavaScript was
rewritten from Node to Python:

- removed: `skills/.system/openai-docs/scripts/resolve-latest-model-info.js`
- added: `skills/.system/openai-docs/scripts/resolve_latest_model_info.py`
- updated caller docs: `skills/.system/openai-docs/SKILL.md`
  and `skills/.system/openai-docs/references/upgrade-guide.md`

## Handoff

Detailed deferred surfaces are recorded in
`runtime-migration/inventory/js-language-handoff.yaml`.

Deferred JS that must not be forced without a separate plugin/native-host
contract:

- `plugins/patched/openai-bundled/plugins/browser-use/scripts/browser-client.mjs`
- `plugins/patched/openai-bundled/plugins/chrome/scripts/browser-client.mjs`
- `plugins/patched/openai-bundled/plugins/chrome/scripts/installManifest.mjs`
- `plugins/patched/openai-bundled/plugins/chrome/scripts/installed-browsers.js`
- `plugins/patched/openai-bundled/plugins/chrome/scripts/open-chrome-window.js`

Follow-up helper migrations completed after the first language-stat handoff:

- removed: `plugins/patched/openai-bundled/plugins/chrome/scripts/chrome-is-running.js`
- added: `plugins/patched/openai-bundled/plugins/chrome/scripts/chrome_is_running.py`
- removed: `plugins/patched/openai-bundled/plugins/chrome/scripts/check-extension-installed.js`
- added: `plugins/patched/openai-bundled/plugins/chrome/scripts/check_extension_installed.py`
- removed: `plugins/patched/openai-bundled/plugins/chrome/scripts/check-native-host-manifest.js`
- added: `plugins/patched/openai-bundled/plugins/chrome/scripts/check_native_host_manifest.py`
- added shared helper: `plugins/patched/openai-bundled/plugins/chrome/scripts/chrome_common.py`
- removed: `plugins/patched/openai-bundled/plugins/latex-tectonic/scripts/tectonic-path.mjs`
- added: `plugins/patched/openai-bundled/plugins/latex-tectonic/scripts/tectonic_path.py`

## Compatibility Impact

- Hooks: no hook runtime was changed.
- MCP routes: no MCP server config was changed.
- Toolchain shims: no shim command target was changed.
- Plugin cache: `.gitattributes` marks `plugins/patched/openai-bundled/**`
  as vendored for GitHub Linguist, and compact diagnostic/path helpers have now
  been rewritten to Python where their contracts are fixture-testable.
- Skills: the OpenAI docs helper is now Python; its command reference was
  updated in `skills/.system/openai-docs/SKILL.md` and its bundled upgrade
  guide.
- Rollback: remove the `.gitattributes` vendored marker and regenerate the
  inventory if this language-stat treatment is rejected.

## Worktree Skill Cleanup

The previously dirty `skills/clean-all-slop/*` changes are retained and tracked
as a failure-aware review workflow update. The previously untracked
`skills/roast-feedback-to-goal-hardening/` and
`skills/technical-system-roast-review/` directories are retained and tracked as
complete skill packages rather than discarded, because their `SKILL.md`,
`agents/openai.yaml`, and reference templates form coherent active skill
surfaces with no secret material observed in the inspected files.

## Admin Session Runtime Calibration

This pass was run from an elevated administrator Codex app session, as the user
explicitly stated. The Memento runtime verifier intentionally rejects elevated
administrator tokens because the managed PostgreSQL runtime is designed to run
from the current non-elevated user token. For this migration slice,
`doctor --tier core --json` and `repo-verify` are the clean managed-source
checks. Full/stress Memento runtime health remains a separate non-admin runtime
check, not a reason to weaken the Memento launch guard.

## Checks

Run before final handoff:

- Python scanner unit tests.
- Python compile check for the scanner.
- Python compile check for the OpenAI docs helper.
- Python compile check for migrated plugin helper scripts.
- Fixture tests for Chrome diagnostic helpers and the Tectonic path helper.
- Old JS helper versus new Python helper CLI parity on a safe local fixture.
- Scanner regeneration of `inventory/node-js-surfaces.yaml`.
- `git check-attr linguist-vendored` for representative plugin JS files.
- Sensitive diff check before commit.
- Memento verifier remains required because the migration boundary references
  the support-only Memento runtime.

Not run / blocked:

- Temporary parity fixture cleanup was not run because the cleanup command was
  blocked by the safety hook as destructive. The leftover file is outside the
  repository under `%TEMP%`.
