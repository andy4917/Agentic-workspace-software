# 2026-05-21 Workflow Policy Alignment

## Scope

User requested control-plane alignment for Codex instruction discovery casing,
L3/L4 subagent policy, Best-of-N usage, weekly Memento MCP security-contract
checks, and configured trusted project paths.

## Official Source Checks

- Codex instruction discovery checks `AGENTS.override.md`, then `AGENTS.md`,
  then names in `project_doc_fallback_filenames`.
- Codex fallback filenames require `project_doc_fallback_filenames` and a new
  Codex command/session restart to load changed configuration.
- Codex Cloud supports `--attempts` in the 1-4 range for best-of-N runs.
- OpenAI "How OpenAI uses Codex" describes Best-of-N as generating multiple
  responses for one task to compare solutions and choose the best one.

## Changes

- `config.toml`: added `agent.md` to `project_doc_fallback_filenames` beside
  `CALIBRATION.md`; added Best-of-N guidance to `developer_instructions`.
- `AGENTS.md`: clarified official casing/discovery behavior for
  `AGENTS.override.md`, `AGENTS.md`, and fallback names; added Best-of-N
  comparison workflow guidance.
- `maintenance/MULTI_AGENT_WORKFLOW_STATUS.md`: replaced stale wording that
  implied L3/L4 or explicit subagent prompts should avoid subagents; added
  Best-of-N usage guidance.
- `maintenance/PM_WORKSPACE_ALIGNED_DESIGN.md`: aligned subagent authorization
  wording with standing authorization plus active runtime boundary.
- Hooks: adjusted prompt reminders so standing/current authorization can require
  a delegation decision; added Best-of-N reminder for ambiguity-heavy L3/L4.
- `maintenance/scripts/memento-security-contract-check.ps1`: added weekly-safe
  check for RBAC default-deny, tenant isolation forbidden SQL patterns,
  README/package script drift, migration lint, and `test:ci`.
- `automations/weekly-workstation-workflow-health-check`: updated existing
  weekly automation prompt to include the Memento security-contract script.
- `tools/memento-mcp/docs/configuration.md`: corrected stale `test:ci`
  documentation to `npm test && npm run test:integration`.
- Active stale cache cleanup: moved `vendor_imports`,
  `.tmp/bundled-marketplaces`, `.tmp/plugins`, `.tmp/plugins-clone-*`, and
  `.tmp/plugins.sha` to
  `%USERPROFILE%\.codex-archives\2026-05-21-workflow-policy-alignment-stale-active`.

## Direct Evidence

- Trusted project paths in `config.toml`: all 31 `[projects.'...']` entries
  exist by `Test-Path`; no nonexistent trusted paths were removed.
- Memento security-contract script:
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File maintenance/scripts/memento-security-contract-check.ps1 -Json`
  returned `status=pass`, including `migration_lint=pass` and `test_ci=pass`.
- Existing weekly automation updated in the app and reflected in
  `automations/weekly-workstation-workflow-health-check/automation.toml`.
- Naming check after quarantine returned `status=pass`, `finding_count=0`.
- Native alignment after quarantine returned only the known Codex CLI mismatch:
  shell wrapper `codex-cli 0.132.0` vs installed Store app bundle
  `codex-cli 0.131.0`.

## Residual Risk

- `config.toml` changes require a fresh Codex session or command for official
  instruction fallback changes to be fully reloaded.
- The trusted path set is valid by existence, but it still includes many dated
  scratch workspaces; no trust removal was performed because the user asked to
  verify correctness and all listed paths exist.
- `codex-harness-doctor.ps1 --json` still fails only on pre-existing
  `skills/.system/imagegen/scripts/image_gen.py` file-size policy, unrelated to
  this workflow-policy change.
- Full `codex_agent_harness.py verify` still exits non-zero because `doctor`
  inherits the same pre-existing imagegen file-size issue and `audit` expects a
  fresh benchmark results digest. Benchmark mode was not run because this task
  did not explicitly request benchmark work.
