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

- `no-mistakes` is now adopted as the workstation outer validation gate after
  the 2026-06-09T19:29:16Z follow-up. It is installed from the official
  `kunchenguid/no-mistakes` release and invoked through
  `.codex\toolchains\shims\no-mistakes.cmd` when related repository work needs
  non-self-certified verification.
- Full P0 loop previously reported only `scoop_health_current` as failing after
  the test-integrity commit. Follow-up remediation ran `scoop update`, after
  which `scoop status` reported `Scoop is up to date. Everything is ok!` and
  `scoop checkup` reported `No problems identified!`. The P0 loop was rerun
  with a temp `-ReportPath` to avoid mutating the tracked historical report and
  returned `status=pass`, `fail_count=0`.
- Plugin skills were intentionally excluded from this review.

## Follow-up Closure

Generated UTC: 2026-06-09T19:17:10.9031743Z

- Closed: `scoop_health_current` package-manager freshness warning.
- Verified: `validate-codex-scaffold.ps1 -Json` returned
  `overall_status=pass`, `fail_count=0`, `check_count=35`.
- Verified: `codex-p0-integrity-loop.ps1 -Json -ReportPath <temp>` returned
  `status=pass`, `fail_count=0`.
- Verified: no active `Code.exe` processes were present in the
  `Win32_Process` check during this follow-up.
- Superseded: `no-mistakes` was not installed in this first closure. A later
  follow-up adopted and installed the official gate.

## no-mistakes Adoption Follow-up

Generated UTC: 2026-06-09T19:29:16.2584172Z

- Adopted: `no-mistakes` is now mandatory when related repository work needs
  non-self-certified validation, especially test/TDD, push, PR, CI, release, or
  safe-shipping handoff.
- Installed: official `kunchenguid/no-mistakes` release `v1.26.0` under
  `%LOCALAPPDATA%\no-mistakes\no-mistakes.exe`; the downloaded asset checksum
  matched `checksums.txt`.
- Active entrypoint: `%USERPROFILE%\.codex\toolchains\shims\no-mistakes.cmd`.
  The wrapper sets `NO_MISTAKES_TELEMETRY=0` and
  `NO_MISTAKES_NO_UPDATE_CHECK=1` for deterministic Codex-managed runs.
  Follow-up integration testing showed the wrapper must also remove
  `%USERPROFILE%\.codex\toolchains\shims` from the child `PATH`; otherwise
  no-mistakes-spawned Codex agents resolve `pwsh.cmd` and every shell command
  fails before execution with `batch file arguments are invalid`.
  The PATH filter now normalizes `/` to `\` and removes trailing `\` before
  comparing entries, so benign spelling variants of the shim directory are
  filtered as well.
- no-mistakes review findings fixed during adoption: the installed skill
  mirrors now use the managed wrapper path instead of bare `no-mistakes`, do
  not treat `--yes` as standing consent, and restrict `skip` to an explicit
  run-specific waiver or inapplicable-step reason.
- User environment: `NO_MISTAKES_TELEMETRY=0` and
  `NO_MISTAKES_NO_UPDATE_CHECK=1` are set at User scope so daemon runs inherit
  the same privacy and determinism posture where Windows environment propagation
  allows it.
- Runtime state: `no-mistakes doctor` reported `git`, `gh`, data directory,
  database, daemon, and Codex agent as OK; `daemon status` reported running.
- Rejected package route remains valid: the npm package named `no-mistakes`
  points to a different `jonathanong/no-mistakes` project and must not be used
  for this gate.
