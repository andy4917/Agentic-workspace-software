# Codex Workflow Applied Review

Date: 2026-05-10

Source decision document:

- `C:\Users\anise\Downloads\codex_workflow_configuration_interview_completed_reviewed.md`

Adopted profile:

- `anti_reward_pm_workflow_v1`

## Applied Surfaces

### AGENTS.md

Purpose:

- Keep the global operating contract high level.
- State that the user is the reviewer, not the operator.
- Keep PM-led workflow, role separation, evidence-first completion, and anti-fake-success rules.
- Do not store numeric thresholds or hook strictness in `AGENTS.md`.

Applied:

- Added the active profile name and its high-level intent.
- Added `migration` as a team preset.
- Kept the rest of the file as scoped project guidance.

### config.toml

Purpose:

- Store runtime-supported Codex settings only.
- Avoid treating unsupported policy tables as active configuration.

Applied locally:

- `[features].codex_hooks = true`
- `[features].multi_agent = true`
- `[agents].max_threads = 8`
- `[agents].max_depth = 1`
- `[projects.'c:\users\anise\.codex'].trust_level = "trusted"`
- Existing MCP, plugin, memory, marketplace, model, Windows sandbox, and project trust settings were preserved.

Notes:

- `config.toml` is intentionally ignored by Git because it is user-local Codex state.
- Policy values removed from `config.toml` now live in `hooks/lightweight-codex-policy.json` or `AGENTS.md`.

### hooks.json

Purpose:

- Use one official Codex hook lifecycle wiring surface.
- Keep lifecycle behavior lightweight.

Applied:

- `SessionStart`
- `UserPromptSubmit`
- `PreToolUse`
- `PermissionRequest`
- `PostToolUse`
- `Stop`

All hook events call `hooks/lightweight-codex-hook.ps1`.

### hooks/lightweight-codex-policy.json

Purpose:

- Store accepted interview thresholds and strictness as machine-readable hook policy.

Applied:

- Subagent budget: `max_parallel = 8`, `max_depth = 1`.
- Work-size thresholds: tiny, normal, large, and multi-surface values from the completed interview.
- Hook strictness: observe/warn/not_ready/hard_block split.
- Validation, contamination, research, Git, reporting, and security decisions from the completed interview.

### hooks/lightweight-codex-hook.ps1

Purpose:

- Inject workflow reminders.
- Observe ordinary work.
- Warn for large/multi-surface work.
- Block only immediate high-risk actions.
- Mark finalization as not ready when evidence is missing.

Applied:

- Reads `hooks/lightweight-codex-policy.json`.
- Injects active profile and subagent budget into prompt reminders.
- Blocks secret content access, destructive actions, hook/multi-agent weakening, and fake-success style control-code edits.
- Detects large patch thresholds and records validation reminders.
- Keeps policy/fixture/documentation text from being treated as fake-success contamination.

## Official Format Check

Reference points used:

- Codex config precedence: user config and project config loading order.
  Source: `https://developers.openai.com/codex/config-basic`
- Codex `features.codex_hooks` loads lifecycle hooks from `hooks.json` or inline `[hooks]`.
  Source: `https://developers.openai.com/codex/config-reference`
- Codex hook config shape: top-level `hooks` object, event groups, matcher groups, command handlers, timeout/statusMessage.
  Source: `https://developers.openai.com/codex/hooks`
- Codex subagents: global settings under `[agents]` with `agents.max_threads` and `agents.max_depth`.
  Source: `https://developers.openai.com/codex/subagents`

## Validation Checklist

Required for this change:

- TOML parse for `config.toml`.
- JSON parse for `hooks.json`.
- JSON parse for `hooks/lightweight-codex-policy.json`.
- PowerShell parse for `hooks/lightweight-codex-hook.ps1`.
- Hook sample allow case.
- Hook sample deny case.
- Hook sample prompt reminder case.
- `codex features list` confirms `hooks` and `multi_agent` are active.
- Git status and relevant diff review before commit.

## Residual Risk

- Hook trust can still be affected by external app/session trust state, but `config.toml` explicitly marks `C:\Users\anise\.codex` trusted.
- `config.toml` is local ignored state, so this repository commit records the policy and hook implementation, not the private local config file.
- Unknown future Codex config keys should be rechecked against official docs before being treated as active configuration.
