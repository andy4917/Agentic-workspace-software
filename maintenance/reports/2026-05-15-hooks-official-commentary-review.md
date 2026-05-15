# Hooks Official Commentary Review

## Scope

Reviewed the local Codex hook setup against the current OpenAI Codex Hooks
documentation and the developer commentary that hooks are best used for
validators, prompt secret scans, structured logging, memory support, and
directory- or repository-specific behavior.

## Finding

The workstation already uses all lifecycle events through `hooks.json`:

- `SessionStart`
- `UserPromptSubmit`
- `PreToolUse`
- `PermissionRequest`
- `PostToolUse`
- `Stop`

The hook already injects workflow reminders, blocks direct secret-file reads,
blocks destructive actions, blocks hook weakening without explicit scope,
records structured metadata, tracks changed surfaces, and requests final audit
evidence at Stop.

One gap was confirmed with a synthetic `UserPromptSubmit` payload: prompt text
containing a secret-like API key value was not blocked before model dispatch.
This review added a prompt-level secret-like value scanner to
`hooks/lightweight-codex-hook.ps1` and added `prompt_secret_scan` to
`hooks/lightweight-codex-policy.json`.

## Verification Plan

- PowerShell parser check for `hooks/lightweight-codex-hook.ps1`.
- Synthetic `UserPromptSubmit` with a fake secret-like value must block.
- Synthetic `PreToolUse` direct `auth.json` read must still block.
- `hook-policy-smoke` eval must pass.
- Full `codex_agent_harness.py verify` must pass after the hook update.

## Residual Risks

- Hook interception is a guardrail, not a complete security boundary. Official
  docs note that some tool paths are not intercepted.
- The prompt secret scanner intentionally targets high-confidence secret-like
  values. It may block pasted examples that resemble real credentials; use
  redacted placeholders instead.
- Automatic memory creation was not added. Memento remains support-only and
  memory writes still require PM write-gate judgment.
