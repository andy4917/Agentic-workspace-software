# Inventory

- `clean-slate.agent.config.toml`: clean-slate machine-readable policy layer.
- `workflow-orchestration.agent.config.yaml`: frame, guard, plan, execute, evidence, review, report flow.
- `state-machine.agent.config.yaml`: completion states and transition rules.
- `retry-recovery-policy.agent.config.yaml`: retry, recovery, no-fallback policy.
- `agent-reliability-tests.agent.config.yaml`: negative-only reliability fixtures.
- `reward-signal-filter.agent.config.yaml`: rulebase for filtering frequent work command PASS signals as uncontrolled slop risk until counterexample review.
- `control-plane-change-policy.agent.config.yaml`: policy for scoped hook, authority, operating-value, and runtime schema changes with post-change review.
- `cost-latency-policy.agent.config.yaml`: fast path and protected path policy.
- `human-in-the-loop.agent.config.yaml`: user and agent responsibility boundaries.
- `reporting-ssot-bookkeeping.agent.config.yaml`: reporting and SSOT bookkeeping policy.
- `tool-skill-subagent-mcp-usage.agent.config.yaml`: actual-use policy for tools, skills, hook-routed Spark inspectors, subagents, MCP, and official OpenAI Codex repo workflows.
- `required-tool-routes.json`: Stop-only required capability route table plus task classification and need resolution resolver policy for tools, skills, MCP servers, checks, and hook-routed subagent inspection routes.
- `repo-gate-adoption.agent.config.yaml`: actual hook wiring adoption policy for repo/session gate verification.
- `warp-assistant-terminal.agent.config.yaml`: auxiliary Warp + PowerShell adoption policy and Warp-managed agent restrictions.
