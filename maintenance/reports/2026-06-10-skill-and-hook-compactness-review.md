# Skill And Hook Compactness Review

Generated UTC: 2026-06-09T18:59:58.7936137Z

## Scope

- Included: user-managed skills under `Documents\Codex\skills` and live user
  skills under `.codex\skills`.
- Excluded: plugin-provided skills under plugin caches and platform-managed
  `.system` skills.
- Checked: active skill config, managed/live sync, compact hook behavior,
  scaffold validation, and command availability relevant to the current
  workstation workflow.

## Findings

| ID | Priority | Finding | Evidence | Action |
|---|---|---|---|---|
| F1 | P1 | `git-easy-korean` existed only in managed source while `AGENTS.md` instructs Git/GitHub work to use it when available. | `Documents\Codex\skills\git-easy-korean\SKILL.md` existed; live `.codex\skills` and active config did not include it. | Activated the skill, copied it to live runtime, added it to keep-set, and added it to managed/live sync validation. |
| F2 | P2 | Compact hook recorded `UserPromptSubmit` but emitted no `additionalContext`, which explains why hook reminders were not visible as prompt context in app turns. | `compact-codex-hook.ps1` emitted `additionalContext` only for `SessionStart`; source inspection showed no `UserPromptSubmit` output path before the change. | Added one compact `UserPromptSubmit` additionalContext message. |
| F3 | P2 | The skill inventory is intentionally compact, but inactive managed skills should remain candidates rather than silently becoming active context. | 25 managed user skills, 20 active before this review; several managed-only skills are not in live runtime or config. | Left inactive candidates disabled to preserve context compactness. |
| F4 | P3 | One inactive managed skill is over the 500-line skill-creator guideline. | `ts-structure-code-review` is 525 lines and inactive. | Report only; no live impact while inactive. |

## Skill Inventory

- Managed user skills scanned: 25.
- Active live/configured skills before this review: 20.
- Active live/configured skills after this review: 21.
- Frontmatter issues found: none.
- `skill-creator` quick validation: `git-easy-korean` pass,
  `test-integrity-gate` pass.

## Hook And Pipeline Check

- Active hook config uses one compact runner:
  `.codex\hooks\compact-codex-hook.ps1`.
- Configured events: `SessionStart`, `UserPromptSubmit`, `PreToolUse`,
  `PostToolUse`, and `Stop`.
- Hook behavior after this review:
  - `SessionStart`: emits minimal scaffold context.
  - `UserPromptSubmit`: emits compact workflow context.
  - `PreToolUse`: emits allow decision and reason.
  - `PostToolUse` and `Stop`: record ledger evidence without chat-facing
    context unless future policy changes reintroduce stricter gating.
- Note: hook `additionalContext` is runtime/model context, not guaranteed to
  render as ordinary user-visible chat text. The live ledger remains
  `.codex\state\hook-ledger.jsonl`.

## Validation Targets

- `config.toml` must be regenerated from live `config.d`.
- `validate-codex-scaffold.ps1 -Json` must pass with:
  - `skills_exact_user_set=pass`
  - `managed_source_live_sync=pass`
  - `config_fragment_reconcile_match=pass`
- Direct hook samples should show JSON output for `SessionStart`,
  `UserPromptSubmit`, and `PreToolUse`.

## Residual Risks

- `no-mistakes` is not currently installed on PATH.
- Full P0 loop previously reported only `scoop_health_current` as failing after
  the test-integrity commit; this is a workstation package-manager freshness
  warning and was not remediated in this scoped change.
- Plugin skills were intentionally excluded from this review.
