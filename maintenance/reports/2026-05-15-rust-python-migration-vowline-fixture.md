# Rust/Python Migration And Vowline Fixture Handoff

Date: 2026-05-15

## Scope

- Root: `%USERPROFILE%\.codex`
- Requested plan: `%USERPROFILE%\Downloads\rust-python-migration-meta-plan.md`
- Risk level: controlled-change
- Memento MCP: excluded from migration and verified through the existing managed
  runtime path.

## Changed Surfaces

- `runtime-migration/`: compact first-slice inventory, contracts, Python
  scanner, and Memento exclusion tests.
- `hooks/lightweight-codex-hook.ps1`: subagent Vowline startup fixture now
  includes workspace scope, `AGENTS.md`, toolchain policy, lifecycle, and
  Memento support-only boundary.
- `maintenance/scripts/codex_agent_harness_workflows.py`: hook smoke now checks
  the subagent `SessionStart` Vowline fixture.
- Existing workstation stability edits remain in scope: doctor Memento runtime
  coverage, workstation report resilience, and related maintenance docs.

## Evidence

- Python compile: pass.
- Runtime migration unit tests: pass.
- Harness doctor: pass.
- Hook policy smoke: pass.
- Memento verify: pass.
- Worktree sensitive diff scan: pass.

## Rollback

- No active runtime was switched.
- Remove `runtime-migration/` and revert the Vowline fixture additions if this
  migration slice is rejected.
- Memento runtime rollback remains
  `maintenance\scripts\memento-mcp-runtime.ps1 stop` only after explicit user
  request; preserve state by default.

## Residual Risk

- Inventory is intentionally compact and excludes generated state, caches,
  plugin caches, and full Memento internals. A later replacement decision must
  run a deeper surface-specific contract capture before rewriting anything.
