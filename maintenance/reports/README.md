# Maintenance Reports

Dated maintenance reports are reviewable historical evidence packets for the
managed Codex workstation.

Classification:

- Dated `*.md`, sanitized `*.json`, `.txt`, and `.reg` files here are
  managed-source historical evidence unless a current command generated and
  cited them in this turn.
- `*.latest.*` outputs remain ignored runtime output by `.gitignore`.
- Reports do not activate runtime config, MCP servers, hooks, shims, skills, or
  automation schedules.

Handling:

- Prefer current files, config, manifests, process state, and validation
  commands for completion claims.
- Keep historical reports when they explain a change, rollback, or failure.
- Quarantine or delete only in a separate cleanup pass with explicit ownership,
  sensitive-boundary review, and rollback notes.
