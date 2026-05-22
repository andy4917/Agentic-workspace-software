# Multi-Agent Workflow Status

This Markdown file records workflow rationale and historical status. Treat live
subagent authorization, hook state, and current tool exposure as runtime facts
that must be verified from the active session or current JSON state.

Updated: 2026-05-21

## Direct Finding

The multi-agent workflow was configured as a capability, but local workflow text
and hook reminders must distinguish three cases: standing configured
authorization, explicit current-prompt authorization, and actual subagent tool
use.

Current config carries standing user authorization in `developer_instructions`.
When the active runtime exposes `spawn_agent`, this supports bounded sidecar
delegation when it materially reduces risk. Current prompts that explicitly say
`subagent`, `spawn_agent`, `multi-agent`, `delegation`, or localized equivalents
are not blocked by the old "no subagent before explicit request" rationale; they
enter the stricter subagent evidence path.

L3/L4 raises delegation priority and evidence pressure. It is not a blanket
mandate to spawn for tiny or immediate-blocking work, but it should no longer be
worded as a reason to avoid subagents when the task is parallelizable,
workflow-sensitive, security-sensitive, or ambiguity-heavy.

## Current Config

`%USERPROFILE%\.codex\config.toml` now explicitly enables:

- `features.multi_agent = true`
- `features.child_agents_md = true`
- `features.tool_search = true`
- `features.tool_suggest = true`
- `features.skill_mcp_dependency_install = true`

`enable_fanout` and `multi_agent_v2` are listed by the installed `codex features list` command as under development. The official Codex feature-maturity documentation says under-development features are not ready for use, so these stay disabled.

## Root Cause

1. `config.toml` already had the stable `multi_agent` flag enabled, so missing stable feature activation was not the primary blocker.
2. `hooks\lightweight-codex-hook.ps1` only injected a generic "conditional use" reminder. It did not distinguish explicit authorization from ordinary large-task context.
3. `AGENTS.md` said to delegate when useful and allowed. The current config now
   provides standing user authorization, while PM judgment still decides whether
   delegation is useful for the specific task.
4. `openaiDeveloperDocs` is enabled in config, but this already-running session does not expose its MCP tools. That points to MCP tool loading requiring a fresh app/session tool refresh after config changes, not a TOML syntax issue.

## Applied Fix

- `AGENTS.md` now records the runtime subagent activation rule and Korean/English authorization phrases.
- `hooks\lightweight-codex-policy.json` now records that standing user authorization from `developer_instructions` satisfies the runtime authorization path when delegation is useful.
- `hooks\lightweight-codex-hook.ps1` now detects prompts containing subagent, multi-agent, delegation, role separation, or parallel-agent phrases and injects a stronger instruction to use `spawn_agent` for bounded non-blocking sidecar work.
- `config.toml` now explicitly enables the stable workflow-adjacent feature flags recognized by the installed CLI, while leaving under-development fanout/v2 flags disabled.
- `config.toml` now carries a compact top-level `developer_instructions` loop overlay so the PM evidence loop is injected as a developer message instead of relying only on user-scoped `AGENTS.md`.
- `config.toml` now records standing explicit user authorization for bounded
  sidecar subagents when useful. Hook policy mirrors this as
  `standing_user_authorization_from_developer_instructions=true` and
  `standing_user_authorization_satisfies_runtime_policy=true`.
- `config.toml` now defines the `worker` role with `agents/worker.toml`, matching the existing explorer, reviewer, docs-researcher, and observer role pattern.
- `model_reasoning_effort` is reset to `medium` as the persistent default; individual tasks can still escalate reasoning effort when justified.

## 2026-05-14 Review Finding

The 2026-05-14 review found one contradictory local edit in `AGENTS.md`: "The user always authorizes all types of sub-agent calls" weakened the runtime rule below it. That sentence was removed at the time. On 2026-05-20 the user explicitly requested standing authorization in `config.toml`; the active rule is now standing authorization with PM judgment, not mandatory spawning.

The active session exposed `mcp__openaiDeveloperDocs__*` tools after tool discovery, so the older note that the OpenAI Docs MCP was not exposed is no longer current for this session. Keep the general MCP load rule: config presence is not proof of active tool availability; verify exposure in each session when the task depends on it.

## Operating Rule

When standing authorization is configured, or when the user explicitly asks for
multi-agent, subagent, delegation, role separation, or parallel agent work:

- the main session remains PM;
- spawn sidecar agents for independent exploration, validation, review, or disjoint file ownership;
- do not delegate the immediate blocking next step;
- review subagent output before integrating;
- report direct evidence, checks not run, and remaining risks.

When the prompt is tiny, immediate-blocking, or does not benefit from parallel
work:

- keep work local;
- use skills directly when their trigger matches;
- record why subagents were not used if the task looked large enough to raise
  the question or if the final gate requires `SUBAGENT_CALL`.

## 2026-05-18 Follow-Up

Thread `019e35aa-326c-7673-9379-8454e8411a34` did use parent-level
`spawn_agent` after a later prompt explicitly requested subagents. The confusing
`SUBAGENT_CALL not_used` fragments in that rollout were subagent close/status
payloads describing the child agents' own nested delegation, not proof that the
parent PM never spawned agents.

One hook gap was confirmed: `PostToolUse` detected direct `spawn_agent` tool
names, but missed `functions.spawn_agent` nested inside `multi_tool_use.parallel`.
That made `hooks/state/lightweight-status.json` underreport actual parent-level
subagent activity for parallel dispatch. The hook now detects nested parallel
subagent recipient names, and `hook-policy-smoke` includes a regression check for
that path.

A second hook gap was confirmed by `OBS-PRESHIP-SPARK`: when governance/incident
evidence raised a tool event to L4, a later nested subagent signal could overwrite
the candidate adjustment back to L3. `Get-ToolTaskAdjustment` now selects the
higher task level instead of assigning levels in last-match order, and
`hook-policy-smoke` covers the nested-subagent-plus-L4 case.

Task level remains workflow routing and evidence pressure. Standing
authorization and explicit prompt authorization allow bounded sidecar delegation
when useful. L3/L4 should trigger a PM delegation decision and prefer sidecars
for parallelizable, ambiguity-heavy, or independently reviewable work; keep work
local only when the immediate next step is tightly coupled, tiny, or delegation
would not improve evidence.

## Best-Of-N Use

Best-of-N is now an explicit comparison option for ambiguity-heavy L3/L4 work.
Use it for complex refactor direction comparisons, Memento auth/memory design
changes, and test strategy design when multiple plausible approaches exist.

Allowed forms:

- local bounded sidecars with separate hypotheses or review dimensions;
- PM-created candidate sketches followed by direct comparison;
- Codex Cloud `--attempts` in the documented 1-4 range when a cloud environment
  is available and the task is suitable for cloud execution.

Best-of-N output is candidate evidence only. The PM must select or reject
approaches with direct evidence, acceptance criteria, maintenance cost,
rollback impact, and residual risk.

## Evidence Sources

- `codex --help`: `--enable <FEATURE>` maps to `features.<name>=true`.
- `codex features list`: confirms `multi_agent`, `child_agents_md`, `tool_search`, `tool_suggest`, `skill_mcp_dependency_install`, `enable_fanout`, and `multi_agent_v2` are recognized feature names.
- Official Codex feature-maturity docs say under-development features are not ready for use, which is why `enable_fanout` and `multi_agent_v2` are intentionally left disabled.
- Official OpenAI model docs confirm current Codex-class models are intended for agentic coding workflows, and the model catalog explicitly mentions subagent suitability for smaller GPT-5.4-class models. Public official docs found in this pass did not expose the internal Codex Desktop feature-flag table.
