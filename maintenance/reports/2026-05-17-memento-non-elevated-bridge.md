# Memento Non-Elevated Runtime Bridge - 2026-05-17

## Scope

Memento is the Codex-global PM memory MCP. PostgreSQL must remain owned by the
current non-elevated user token, while elevated Codex or PowerShell clients
should be able to request runtime start, repair, or verification without trying
to run PostgreSQL as administrator.

## Change

- `maintenance/scripts/memento-mcp-runtime.ps1` now bridges elevated `start`,
  `repair`, and `verify` flows to a non-elevated user PowerShell before
  PostgreSQL launch.
- The script reports `privilege_model=non_elevated_user_runtime` and
  `elevated_client_bridge=enabled` in `status`.
- Existing unhealthy Memento HTTP processes are recycled after PostgreSQL start
  if they do not recover health.
- `codex_agent_harness_lifecycle.py` treats
  `current_process_administrator=True` as context instead of a direct failure;
  the health gate remains `postgres_ready=True` and `memento_health=True`.

## Verification

Current non-elevated session checks passed:

- `memento-mcp-runtime.ps1 status`: `postgres_ready=True`,
  `memento_health=True`, `current_process_administrator=False`,
  `elevated_client_bridge=enabled`.
- `memento-mcp-runtime.ps1 verify`: `status=pass`; required MCP tools present;
  `context`, `recall`, and `tool_feedback` passed; working set stayed below the
  512 MB ceiling.
- `codex_agent_harness.py doctor --tier stress --json`: `status=pass`;
  `memento_runtime.status=pass`.
- `codex_agent_harness.py repo-verify`: `status=pass`.

Not run: elevated-client launch from a separate administrator session. The code
path is parser-verified and status reports the bridge as enabled, but a real
elevated-client bridge smoke still requires an elevated client session.

## Rollback

Revert this report plus the matching changes in:

- `maintenance/scripts/memento-mcp-runtime.ps1`
- `maintenance/scripts/codex_agent_harness_lifecycle.py`
- `maintenance/MCP_RUNTIME_STATUS.md`
- `maintenance/WORKSTATION_MAINTENANCE.md`
- `skills/resolve-agent-incidents/references/incident-manual.md`
