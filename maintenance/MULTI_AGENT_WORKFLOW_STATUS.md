# Multi-Agent Workflow Status

Updated: 2026-06-11

## Direct Finding

The multi-agent workflow is configured as a capability, and the current
authorization source is the scoped `AGENTS.md` plus mirrored `config.toml`
developer instructions. Legacy hook reminders are no longer part of the active
subagent control surface.

The user has approved a standing workspace authorization for bounded subagent
calls on repo, workstation, workflow, toolchain, review, remediation, and
verification goals. The reviewed source is `AGENTS.md`; `config.toml`
`developer_instructions` mirrors it into runtime context. Feature flags only
make the tool path available and do not make subagent reports completion
authority.

## Current Config

The reviewed source for this worktree keeps the active managed config narrow:

- `model_reasoning_effort = "xhigh"` in `config.d/00-policy.toml`;
- `features.hooks = true`;
- `features.goals = true`;
- `features.memories = true`;
- `features.js_repl = false`;
- `config.d/20-hooks.toml` covers `multi_agent.*`, `tool_search.*`,
  `multi_tool_use.*`, MCP, web, image, and Desktop tool namespaces for compact
  hook routing.

Runtime feature flags and tool namespaces are capability only. Standing
subagent authorization comes from `AGENTS.md` and mirrored developer
instructions, not from a feature flag by itself. `enable_fanout` and
`multi_agent_v2` remain disabled unless a future current instruction reopens
that boundary.

## Root Cause

1. Feature or namespace activation is capability only and not a completion
   claim.
2. `AGENTS.md` now carries the standing authorization and final-evidence rule.
3. `config.d/20-hooks.toml` routes lifecycle events to the compact hook only.
4. `openaiDeveloperDocs` remains the only always-on MCP; tool exposure must
   still be verified in each active session before use.

## Applied Fix

- `AGENTS.md` records the runtime subagent activation rule and final-evidence
  reporting requirement.
- `config.d/20-hooks.toml` routes hook events to `hooks\compact-codex-hook.ps1`.
- `hooks\compact-codex-hook.ps1` injects compact workflow calibration reminders
  without becoming completion authority.
- `config.d/00-policy.toml` carries a compact `developer_instructions` loop
  overlay for the compiled runtime config so the PM evidence loop is injected
  as a developer message instead of relying only on user-scoped `AGENTS.md`.
- `agents/worker.toml` exists as the worker role definition, matching the
  existing explorer, reviewer, docs-researcher, and observer role pattern.
- `model_reasoning_effort` remains `xhigh` as the persistent workstation
  default; individual tasks can still choose a lower-effort path when justified.

## 2026-05-26 Review Finding

The previous explicit-per-prompt rule is now stale for this workstation. The active rule is standing user authorization recorded in `AGENTS.md` and mirrored through `config.toml` `developer_instructions`, with prompt phrases still treated as current-goal authorization. This permits autonomous bounded sidecar delegation when useful, but it does not require subagents for tiny tasks and does not let subagents define parent-goal completion.

The active session exposed `mcp__openaiDeveloperDocs__*` tools after tool discovery, so the older note that the OpenAI Docs MCP was not exposed is no longer current for this session. Keep the general MCP load rule: config presence is not proof of active tool availability; verify exposure in each session when the task depends on it.

## Operating Rule

When standing authorization applies or the user explicitly asks for multi-agent, subagent, delegation, role separation, or parallel agent work:

- the main session remains PM;
- spawn sidecar agents for independent exploration, validation, review, or disjoint file ownership;
- do not delegate the immediate blocking next step;
- review subagent output before integrating;
- report direct evidence, checks not run, and remaining risks.

When standing authorization does not apply and the prompt does not explicitly authorize subagents:

- keep work local;
- use skills directly when their trigger matches;
- record why subagents were not used if the task looked large enough to raise the question.

## Evidence Sources

- `codex --help`: `--enable <FEATURE>` maps to `features.<name>=true`.
- `config.d/00-policy.toml`: records the managed public-safe feature baseline
  and default reasoning effort.
- `config.d/20-hooks.toml`: records current Desktop tool namespace matcher
  coverage for compact hook routing.
