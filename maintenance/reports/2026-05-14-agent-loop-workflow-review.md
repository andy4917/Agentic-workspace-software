# Agent Loop Workflow Review

Date: 2026-05-14
Scope: `%USERPROFILE%\.codex` workflow/config design plus read-only analysis of `codex://threads/019e25a0-fcd3-7090-abf3-f50a8ca4668f`.

## Source-Backed Basis

- Source links:
  - `https://openai.com/ko-KR/index/unrolling-the-codex-agent-loop/`
  - `https://developers.openai.com/api/docs/guides/text#message-roles-and-instruction-following`
  - `https://developers.openai.com/api/docs/guides/latest-model#using-reasoning-models`
  - `https://developers.openai.com/codex/config-reference#configtoml`
  - `https://developers.openai.com/codex/concepts/customization#skills`

- OpenAI Codex agent loop article: Codex sends Responses API requests, uses `instructions`, `tools`, and `input`, and appends model output items plus tool results across loop iterations.
- OpenAI Codex agent loop article: Codex inserts optional `developer_instructions` from `~/.codex/config.toml` as a `role=developer` message.
- OpenAI Codex agent loop article: prompt caching depends on stable prefixes; changing tools, model, sandbox, approval mode, or cwd can cause cache misses.
- OpenAI Codex agent loop article: Codex currently keeps requests stateless for ZDR compatibility instead of relying on `previous_response_id`.
- OpenAI docs, text generation guide: `instructions` is high-authority for the current response request, and developer messages are prioritized ahead of user messages.
- OpenAI docs, latest model guide: long-running agents should preserve completed actions, assumptions, IDs, tool outcomes, blockers, and next goal during compaction.
- OpenAI Codex config reference: `developer_instructions`, `model_reasoning_effort`, `agents.<name>.config_file`, `agents.max_threads`, and `agents.max_depth` are config-level controls.
- OpenAI Codex customization docs: skills are the reusable workflow layer and use progressive disclosure; they should not be copied wholesale into the base prompt.

## Thread Evidence

Thread file:
`%USERPROFILE%\.codex\sessions\2026\05\14\rollout-2026-05-14T17-36-08-019e25a0-fcd3-7090-abf3-f50a8ca4668f.jsonl`

Observed summary:

- The thread targeted `C:\Users\anise\code\Dev-Product\입실퇴실 안내문 생성기`.
- It used frontend-specific skills including `impeccable`, `incremental-implementation`, `test-driven-development`, `code-review-and-quality`, and later the Chrome skill.
- It produced product changes in UI routing, Svelte components, CSS, tests, Storybook, and bundled fonts.
- It ran `npm run typecheck`, `npm test`, `npm run build`, `npm run verify`, `npm run build-storybook`, and Storybook/Chrome render checks.
- It attempted direct Chrome extension side panel verification, but the `chrome-extension://.../sidepanel.html` path was blocked by browser policy.
- It reported a final goal audit after hook preflight.

Objective status:

- Flow intent was mostly achieved for evidence-driven work: read context, classify, implement in slices, test, attempt browser verification, and report not-run/blocked items.
- It was not fully achieved for frontend workflow-chain strictness: the global directive existed at `%USERPROFILE%\.codex\docs\codex_frontend_quality_directive.md`, but the thread checked only the product repo's `docs/codex_frontend_quality_directive.md`, recorded it as missing, and proceeded.
- It was not fully complete for product repository hygiene: generated Storybook artifacts/logs remained in the product workspace because deletion was blocked pending explicit approval.
- It was not complete for direct extension runtime verification: Storybook verified the UI, but the actual Chrome extension side panel URL was not visually verified due to policy block.
- It did not record `WATCHER_NOT_USED` for PM-only work. Because the user had not explicitly authorized subagents in that frontend thread, this is residual reporting risk rather than a confirmed delegation violation.

## Workspace Design Judgment

Status: `continue`

The workspace design is directionally correct but was only partially realized before this pass.

Strengths:

- PM-led workflow exists in `AGENTS.md`, hook policy, and maintenance runbooks.
- Multi-agent capability is configured, bounded, and explicit-authorization-aware.
- Role separation exists for explorer, reviewer, docs-researcher, and observer.
- Hooks are framed as reminders and narrow safety checks, not completion authority.
- OpenAI Developer Docs MCP is configured and was usable in this session after tool discovery.

Gaps corrected in this pass:

- Added top-level `developer_instructions` so the durable loop contract is injected as a developer message instead of relying only on user-scoped `AGENTS.md`.
- Reset persistent `model_reasoning_effort` from `xhigh` to `medium` to match local policy; use per-task escalation for genuinely hard work.
- Removed the contradictory `AGENTS.md` line that implied blanket subagent authorization.
- Added an explicit `worker` role config to complete the PM-selected role set for implementation work.

Remaining risks:

- This pass did not mutate the product repository or remove its generated Storybook artifacts.
- Config changes require a fresh session or app reload before every runtime surface reflects them.
- The official Codex config documentation and installed `codex features list` use different naming for some features, such as `codex_hooks` in docs versus `hooks` in the installed runtime. The local runtime evidence was kept unchanged for feature names already recognized by the installed CLI.

## Placement Rules

- Keep short, stable loop invariants in `config.toml` `developer_instructions`.
- Keep project-specific and detailed workflow rules in scoped `AGENTS.md`.
- Keep thresholds, block/observe behavior, and hook strictness in `hooks/lightweight-codex-policy.json`.
- Keep role-specific behavior in `agents/*.toml`.
- Keep repeatable procedures in skills, using progressive disclosure.
- Keep source-backed audit records under `maintenance/reports`.

## Rollback

- Remove `developer_instructions` from `config.toml` to return loop guidance to `AGENTS.md` only.
- Change `model_reasoning_effort` back to the prior value if persistent high effort is intentionally desired.
- Remove `[agents.worker]` from `config.toml` and delete `agents/worker.toml` to return to the prior configured role set.
