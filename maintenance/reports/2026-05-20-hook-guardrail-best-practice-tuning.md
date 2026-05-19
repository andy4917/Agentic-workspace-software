# Hook Guardrail Best-Practice Tuning

- Date: 2026-05-20 KST
- Scope: `%USERPROFILE%\.codex` hook policy, active hook scripts, smoke tests,
  and workstation handoff docs.

## Source-Backed Best Practices

- Hooks are useful for deterministic lifecycle actions, but they should be used
  for rules that are actually deterministic. Source: Claude Code hooks guide,
  `https://code.claude.com/docs/en/hooks-guide`.
- Session-start hooks run on every session and should stay fast; static context
  belongs in normal instruction files instead of hook scripts. Source: Claude
  Code hooks reference, `https://code.claude.com/docs/en/hooks`.
- Tool hooks should be filtered narrowly with matchers. A broad matcher fires
  too often and turns a guardrail into overhead. Source: Claude Code hooks
  guide, matcher section.
- Prompt hooks may inject context, but injected text should be compact. Long
  workflow contracts belong in scoped instruction files and skills, not every
  prompt.
- Hooks can block narrow unsafe actions such as destructive commands or
  protected-file access, but broad quality judgment and completion authority
  should remain with the PM workflow and explicit verification.

## Local Problem

The previous local hook posture mixed two different concerns:

- live guardrails: active `SessionStart` and `UserPromptSubmit`;
- dormant contract tests: disabled `PreToolUse`, `PermissionRequest`,
  `PostToolUse`, and `Stop`.

The dormant paths were still described and tested like active heavy gates. That
created pressure to repeat long final markers, rely on Stop-hook-style closure,
and run heavyweight checks from hook code. This was inconsistent with the user's
current workstation preference: hooks should keep essential rails visible but
stay light.

## Local Tuning

- Kept active runtime hooks limited to `SessionStart` and `UserPromptSubmit`.
- Reduced `SessionStart` injected context to a compact guardrail note.
- Kept bounded Memento health ensure during `SessionStart`, because Memento is
  support infrastructure, but removed unrelated Chrome extension repair from
  hook startup.
- Reduced `UserPromptSubmit` output to compact class, route, memory, goal, and
  hard-block hints.
- Changed prompt classification so standing subagent config does not by itself
  create delegation authorization or final `SUBAGENT_CALL` pressure.
- Limited persisted Goal suggestion to L4, long-running, or explicitly stateful
  work instead of all L3 workflow-sensitive prompts.
- Removed autonomous `doctor`/`verify` execution from dormant `PostToolUse`.
  If re-enabled, it records/reminds only; explicit verification stays outside
  hook execution.
- Renamed the remaining control-plane edit state from autonomous harness
  evidence to `controlPlaneReminders` so state names match the lighter role.
- Updated hook smoke criteria to check compact guardrails and no autonomous
  heavyweight verification.
- Reduced active hook timeouts in `hooks.json` from 30 seconds to 10 seconds.

## Direct Checks

- `python maintenance/scripts/codex_agent_harness.py eval --eval-id hook-policy-smoke`
  passed.
- `python maintenance/scripts/codex_agent_harness.py verify` passed.
- `python maintenance/scripts/codex_agent_harness.py benchmark` passed.
- `python maintenance/scripts/codex_agent_harness.py audit --json` passed with
  score `100.0`.
- `powershell.exe -NoProfile -ExecutionPolicy Bypass -File maintenance/scripts/memento-mcp-runtime.ps1 verify`
  passed.
- `powershell.exe -NoProfile -ExecutionPolicy Bypass -File maintenance/scripts/check-naming-conventions.ps1 -Json`
  passed.
- PowerShell parser check for `hooks\lightweight-codex-hook.ps1` and
  `hooks\lib\*.ps1` passed.
- `python -m json.tool` passed for `hooks\lightweight-codex-policy.json`,
  `hooks.json`, and `evals\hook-policy-smoke.json`.

## Residual Risk

- Disabled lifecycle hook code still exists for future opt-in use and contract
  tests. It is not active runtime enforcement.
- Memento tools may still require a session reload before MCP tools are exposed
  to an already-running Codex session.
- The active `UserPromptSubmit` reminder is intentionally advisory; it cannot
  replace PM judgment, direct verification, or scoped instructions.
