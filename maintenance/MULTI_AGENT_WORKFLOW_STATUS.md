# Multi-Agent Workflow Status

Updated: 2026-05-14

## Direct Finding

The multi-agent workflow was configured as a capability, but the local workflow text and hook reminder did not make the runtime authorization rule explicit.

Current higher-priority runtime behavior requires an explicit user request before `spawn_agent` can be used. That means `multi_agent = true` and `child_agents_md = true` make the tool path available, but they do not by themselves authorize automatic subagent creation for every large task.

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
3. `AGENTS.md` said to delegate when useful and allowed, but did not spell out the higher-priority runtime condition that subagents need an explicit user request.
4. `openaiDeveloperDocs` is enabled in config, but this already-running session does not expose its MCP tools. That points to MCP tool loading requiring a fresh app/session tool refresh after config changes, not a TOML syntax issue.

## Applied Fix

- `AGENTS.md` now records the runtime subagent activation rule and Korean/English authorization phrases.
- `hooks\lightweight-codex-policy.json` now records that explicit user authorization is required by runtime policy.
- `hooks\lightweight-codex-hook.ps1` now detects prompts containing subagent, multi-agent, delegation, role separation, or parallel-agent phrases and injects a stronger instruction to use `spawn_agent` for bounded non-blocking sidecar work.
- `config.toml` now explicitly enables the stable workflow-adjacent feature flags recognized by the installed CLI, while leaving under-development fanout/v2 flags disabled.
- `config.toml` now carries a compact top-level `developer_instructions` loop overlay so the PM evidence loop is injected as a developer message instead of relying only on user-scoped `AGENTS.md`.
- `config.toml` now defines the `worker` role with `agents/worker.toml`, matching the existing explorer, reviewer, docs-researcher, and observer role pattern.
- `model_reasoning_effort` is reset to `medium` as the persistent default; individual tasks can still escalate reasoning effort when justified.

## 2026-05-14 Review Finding

The 2026-05-14 review found one contradictory local edit in `AGENTS.md`: "The user always authorizes all types of sub-agent calls" weakened the runtime rule below it. That sentence has been removed. The active rule remains explicit per-prompt authorization before spawning subagents.

The active session exposed `mcp__openaiDeveloperDocs__*` tools after tool discovery, so the older note that the OpenAI Docs MCP was not exposed is no longer current for this session. Keep the general MCP load rule: config presence is not proof of active tool availability; verify exposure in each session when the task depends on it.

## Operating Rule

When the user explicitly asks for multi-agent, subagent, delegation, role separation, or parallel agent work:

- the main session remains PM;
- spawn sidecar agents for independent exploration, validation, review, or disjoint file ownership;
- do not delegate the immediate blocking next step;
- review subagent output before integrating;
- report direct evidence, checks not run, and remaining risks.

When the prompt does not explicitly authorize subagents:

- keep work local;
- use skills directly when their trigger matches;
- record why subagents were not used if the task looked large enough to raise the question.

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

Task level remains workflow routing and evidence pressure. It is not a reliable
runtime override for higher-priority subagent authorization rules by itself. If a
future Codex runtime exposes standing task-level authorization as a supported
policy, update this document and the hook policy together with a live tool-call
proof.

## Evidence Sources

- `codex --help`: `--enable <FEATURE>` maps to `features.<name>=true`.
- `codex features list`: confirms `multi_agent`, `child_agents_md`, `tool_search`, `tool_suggest`, `skill_mcp_dependency_install`, `enable_fanout`, and `multi_agent_v2` are recognized feature names.
- Official Codex feature-maturity docs say under-development features are not ready for use, which is why `enable_fanout` and `multi_agent_v2` are intentionally left disabled.
- Official OpenAI model docs confirm current Codex-class models are intended for agentic coding workflows, and the model catalog explicitly mentions subagent suitability for smaller GPT-5.4-class models. Public official docs found in this pass did not expose the internal Codex Desktop feature-flag table.
