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

Deferred JS that must not be forced in this slice:

- `plugins/patched/openai-bundled/plugins/browser-use/scripts/browser-client.mjs`
- `plugins/patched/openai-bundled/plugins/chrome/scripts/*`
- `plugins/patched/openai-bundled/plugins/latex-tectonic/scripts/tectonic-path.mjs`

## Compatibility Impact

- Hooks: no hook runtime was changed.
- MCP routes: no MCP server config was changed.
- Toolchain shims: no shim command target was changed.
- Plugin cache: `.gitattributes` now marks `plugins/patched/openai-bundled/**`
  as vendored for GitHub Linguist only; runtime files are unchanged.
- Skills: the OpenAI docs helper is now Python; its command reference was
  updated in `skills/.system/openai-docs/SKILL.md` and its bundled upgrade
  guide.
- Rollback: remove the `.gitattributes` vendored marker and regenerate the
  inventory if this language-stat treatment is rejected.

## Checks

Run before final handoff:

- Python scanner unit tests.
- Python compile check for the scanner.
- Python compile check for the OpenAI docs helper.
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
