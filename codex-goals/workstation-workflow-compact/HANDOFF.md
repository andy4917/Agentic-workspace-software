# Handoff: Workstation Workflow Compact Control Plane

## Current Slice

Compact the `.codex` control plane without weakening evidence, subagent, memory,
hook, or secret-boundary rules.

## Accepted Evidence

- Uploaded docs recommend compact `AGENTS.md`, detailed compact workflow runbook,
  one hook representation per layer, support-only Memento, official custom-agent
  paths, subagent evidence-only policy, and bounded `GOAL_SPEC`.
- Local config already enables hooks, multi-agent, goals, child agent docs,
  tool search, tool suggest, skill MCP dependency install, and workspace
  dependencies.
- Local config has `agents.max_threads = 8` and `agents.max_depth = 1`.
- Local hook state intentionally keeps `SessionStart` and `UserPromptSubmit`
  active while lifecycle hooks remain inactive.
- Reappeared forbidden transient roots were compressed to
  `maintenance/compressed/*-20260525-151109.zip` and sent to Windows Recycle Bin:
  `vendor_imports`, `.tmp/plugins`, `.tmp/plugins.sha`, and
  `maintenance/quarantine`.
- After app restart, `vendor_imports`, `.tmp/plugins`, `.tmp/plugins.sha`, and
  stale `.tmp/plugins-backup-vtjxt8` were again checked, compressed to
  `maintenance/compressed/*-20260525-153837.zip` or
  `maintenance/compressed/*-20260525-154258.zip`, and sent to Windows Recycle
  Bin. Active state now keeps only `.tmp/bundled-marketplaces` and
  `.tmp/marketplaces` under `.tmp`.
- Active roast `SKILL.md` packages were removed from
  `skills/technical-system-roast-review` and
  `skills/roast-feedback-to-goal-hardening`. The integrated roast procedure now
  lives in `maintenance/CODEX_DESKTOP_COMPACT_WORKFLOW.md` plus the uploaded
  `workstation-workflow-full-review` source. `clean-all-slop` remains active.
- Added managed templates:
  `maintenance/templates/FINAL_HANDOFF.md` and
  `maintenance/templates/config.codex.example.toml`.
- Memento was unhealthy before this slice and passed `memento-mcp-runtime.ps1
  verify` after managed start.

## Suspect Or Rejected Evidence

- Subagent final text saying `SUBAGENT_CALL not_used` refers to the child
  agent's nested delegation, not the PM's parent-level spawning.
- Configured Memento is not proof that Memento tools are exposed in the active
  session.
- `SKILL_INDEX.md` is harness-managed and intentionally compact; it should be
  treated as an inventory aid, not full skill-discovery authority.

## Next Verification Step

Run `git diff --check`, parse `config.toml`, parse
`maintenance/CODEX_HOME_STRUCTURE_STATE.json`, parse the sanitized config
example, and run naming, native-alignment, Memento, and harness checks when the
next slice touches `.codex` control-plane state.
