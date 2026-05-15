# Code Size, Toolchain, And MCP Simplification

Date: 2026-05-16 KST
Scope: Codex GlobalSSOT harness and hook control scripts under
`%USERPROFILE%\.codex`.

## Objective

Use the code-simplification workflow to reduce recently worked oversized code
surfaces, verify required toolchain and MCP usage clarity, and leave no scoped
residual oversized list before review, commit, and push.

## Size Changes

- Split `hooks/lightweight-codex-hook.ps1` into a compact entrypoint plus:
  - `hooks/lib/lightweight-codex-core.ps1`
  - `hooks/lib/lightweight-codex-workflow.ps1`
  - `hooks/lib/lightweight-codex-guards.ps1`
- Moved harness status checks from
  `maintenance/scripts/codex_agent_harness_lifecycle.py` to
  `maintenance/scripts/codex_agent_harness_status.py`.
- Moved smoke/eval helper checks from
  `maintenance/scripts/codex_agent_harness_workflows.py` to
  `maintenance/scripts/codex_agent_harness_smoke.py`.
- Lowered the managed harness/control-script line limit from 1000 to 800 and
  made doctor check both harness Python files and lightweight hook files.

## Direct Size Evidence

All scoped harness/control files are now under the 800-line threshold:

- `maintenance/scripts/codex_agent_harness_lifecycle.py`: 772
- `maintenance/scripts/codex_agent_harness_base.py`: 739
- `maintenance/scripts/worker_watcher_templates.py`: 717
- `maintenance/scripts/codex_agent_harness_workflows.py`: 567
- `maintenance/scripts/codex_agent_harness_smoke.py`: 446
- `hooks/lib/lightweight-codex-workflow.ps1`: 596
- `hooks/lib/lightweight-codex-core.ps1`: 392
- `hooks/lib/lightweight-codex-guards.ps1`: 300
- `hooks/lightweight-codex-hook.ps1`: 321
- `maintenance/scripts/codex_agent_harness_status.py`: 221

## Toolchain And MCP Clarity

- Toolchain source policy is documented in
  `maintenance/AGENT_TOOL_REQUIREMENTS.md`, `maintenance/MCP_RUNTIME_STATUS.md`,
  and `toolchains/README.md`.
- `check-toolchain-sources.ps1 -Json` passed with `failures=0` and
  `warnings=0`.
- Memento MCP was used for support-only context and verified with
  `maintenance/scripts/memento-mcp-runtime.ps1 verify`; status was `pass`.
- Context7, OpenAI Developer Docs, shadcn, Chrome DevTools MCP, and node_repl
  were not used because this task did not require current external docs,
  frontend registry/browser observation, or JavaScript execution. Their routing
  and fallback rules remain documented in `maintenance/AGENT_TOOL_REQUIREMENTS.md`
  and `maintenance/MCP_RUNTIME_STATUS.md`.

## Residual List

- Scoped oversized harness/hook files: none.
- Toolchain source ambiguity detected by the managed check: none.
- MCP runtime blocker for this task: none.

## Rollback

Revert the commit containing this report to restore the prior monolithic hook
and harness module layout. The change is structural; no runtime secrets or
external services were modified.
