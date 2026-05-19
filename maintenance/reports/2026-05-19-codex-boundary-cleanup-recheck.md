# Codex Boundary Cleanup Recheck - 2026-05-19

## Scope

Rechecked the Codex Desktop official bundle versus `%USERPROFILE%\.codex`
managed-source boundary after the browser/plugin cleanup. The cleanup standard
for this incident is removal or Recycle Bin movement, not quarantine, sentinel
blockers, or long-lived local fallback copies.

## Actions

- Confirmed stale `plugins\patched`, `vendor_imports`, `plugins\plugins`,
  `plugins\cache\openai-bundled\browser-use`, `plugins\cache\openai-primary-runtime`,
  and `maintenance\scripts\repair-browser-use-extension-url-policy.ps1` are absent.
- Moved these obsolete state backup or fallback roots to the Windows Recycle Bin:
  `state\browser-extension-url-policy`, `state\browser-plugin-ui-repair`,
  `state\mcp-toggle-backups`, and `state\official-user-boundary`.
- Patched `maintenance\scripts\chrome-devtools-mcp-toggle.ps1` so the `off`
  action stops stale `chrome-devtools-mcp` Node processes after keeping the MCP
  entry registered with `enabled=false`.
- Removed the `.tmp\bundled-marketplaces` fallback branch from
  `maintenance\scripts\ensure-chrome-extension-origin.ps1`; official bundled
  marketplace discovery now fails closed instead of promoting `.codex` copies
  when WindowsApps discovery fails.
- Clarified that `plugins\cache\openai-primary-runtime` is forbidden as an
  active source under `.codex`; the official `openai-primary-runtime`
  marketplace name remains valid when loaded from Codex-managed runtime source.
- Recorded the result to Memento through the local HTTP MCP because the active
  Codex session did not expose `mcp__memento__...` tools even though the
  configured runtime could be made healthy.

## Verification

- `chrome-devtools-mcp-toggle.ps1 off`: `state=off`,
  `stopped_stale_processes=2`.
- `memento-mcp-runtime.ps1 verify`: `status=pass`, required tools present,
  `context=pass`, `recall=pass`, `tool_feedback=pass`.
- `Memento remember`: `remember_success_count=3`.
- Removed state roots: all returned `ExistsAfter=False`.
- Watcher P2 findings were accepted and addressed: `.tmp` fallback roots and
  `.codex-global-state.json.bak` were moved to the Recycle Bin, and the
  `openai-primary-runtime` policy conflict was corrected.
- `.tmp\plugins.sha` and the stale `.tmp\imagegen-batch-smoke.jsonl` smoke
  artifact were also moved to the Recycle Bin; `.tmp\marketplaces` remains only
  as an empty runtime work directory.

## Residual Risk

Historical reports can still mention old paths such as `browser-use` or
`vendor_imports`; those are provenance records, not active sources. Current
Codex app sessions may still require reload before newly healthy MCP tools are
exposed in the tool namespace.
