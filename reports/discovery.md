# Discovery

- generated_at: 2026-05-10T21:01:17+00:00
- project_type: Codex global state and local development-environment harness
- language_runtime: PowerShell, Python, TOML, JSON
- package_manager: toolchain shims under toolchains/shims; no repo package manager required
- proposed_harness_script_language: Python engine with PowerShell wrappers

## Existing Instruction Files
- AGENTS.md (13549 bytes)
- agent.md (341 bytes)

## Risks
- Already-running Codex sessions may not reload newly enabled MCP tools until restart.
- Sentinel blocker files intentionally cause PATH/temp creation warnings for commands that try to create blocked roots.
- SQLite runtime DB files are live and are audited metadata-only.
