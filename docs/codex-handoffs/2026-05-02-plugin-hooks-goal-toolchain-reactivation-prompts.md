# Plugin, Hook, Goal, Toolchain Reactivation Prompts - 2026-05-02

## General Reactivation Prompt

```text
We are continuing Codex local-state work from preserved handoffs. Read C:\Users\anise\.codex\Dev_Codex_App_GlobalSSOT\docs\codex-handoffs\2026-05-02-active-repo-chats-index.md and this document first. Inspect the current files before editing. Continue only inside the user's stated scope, preserve continuity before archiving sessions, and report direct evidence.
```

## Plugin / Hook Blocker Continuation

Covered sessions:

- `019de482-0c60-7b83-8c1c-30c815b0e97a` - global settings verification and plugin 403 investigation
- `019de50a-159e-7c40-a4a0-a344e99487a2` - plugin 3-limit and hook overblocking check
- `019de4ee-ca88-7b41-bf81-54cd487d8bb3` - root split investigation

Reactivation prompt:

```text
Continue the plugin/hook blocker investigation from this handoff. Verify the current Browser Use, GitHub, and Spreadsheets plugin configuration, inspect hooks.json and codex-ssot-hook.ps1, then reproduce or disprove whether features.plugins=true still triggers chatgpt.com/backend-api/plugins/featured and recreates .codex\.tmp\plugins. Do not treat hook PASS or any test PASS as completion. If the blocker remains outside local control, keep runtime state as blockers and document exact evidence.
```

Important context:

- The user wanted the active plugin surface limited to Browser Use, GitHub, and Spreadsheets.
- Local plugin marketplace/cache was reduced to those three, but Codex's built-in featured plugin warm may still fetch remote featured metadata.
- The local remediation was considered real but not sufficient to mark the whole state complete because the remote 403 and shell snapshot limitations remained.
- A previous overblocking guard treated valid SSOT work as `path_outside_active_scope`; later work adjusted the guard model toward effect-aware checks.
- If editing guard logic, check both declarative config and actual hook runner behavior.

Files to inspect:

- `C:\Users\anise\.codex\hooks.json`
- `C:\Users\anise\.codex\config.toml`
- `C:\Users\anise\.codex\plugins\local-marketplaces`
- `C:\Users\anise\.codex\.tmp`
- `C:\Users\anise\.codex\Dev_Codex_App_GlobalSSOT\Settings\Dev_Codex_HOOKS\codex-ssot-hook.ps1`
- `C:\Users\anise\.codex\Dev_Codex_App_GlobalSSOT\Settings\Codex_App_RUNTIME\active_contract.json`
- `C:\Users\anise\.codex\Dev_Codex_App_GlobalSSOT\CHANGELOG.md`

Checks already used:

- `codex --version`
- `codex exec` with plugins enabled and disabled
- PowerShell folder and config inspection
- Local marketplace folder listing
- Hook dry-run/root resolution checks

## `/goal` Command and Toolchain Continuation

Covered session:

- `019de826-b37b-7d20-9718-72660a905c22` - `/goal` command activation and toolchain usage discussion

Reactivation prompt:

```text
Continue the /goal and toolchain standardization work from this handoff. Verify that /goal is enabled in the active Codex config and mirrored in the SSOT declarative config. Then document or refine the standard toolchain policy without moving global runtime binaries into the SSOT folder. Use the appropriate verifier for each file type: TOML parser for TOML, JSON parser or Biome for JSON, ruff for Python, tsc/Biome for TypeScript, and project scripts when present.
```

Important context:

- `/goal` was enabled in active Codex config and mirrored in `clean-slate.agent.config.toml`.
- The user challenged why tools such as `ruff`, `biome`, and `tsc` were not visibly used more often.
- The working answer was that recent changes were mostly TOML/YAML/JSON/Markdown config edits, where parser validation and targeted `rg` checks were more appropriate than broad formatters.
- Toolchain binaries were not moved into the SSOT folder because they are managed by Windows/global package managers and PATH/shim mechanisms.
- The useful SSOT action is to record the standard toolchain policy and detection results, not physically relocate global runtimes.

Known tool guidance:

- Python code: `ruff check`, optionally `ruff format`, and project tests when present.
- JavaScript/TypeScript: `biome check` or project script, plus `tsc --noEmit` when project config exists.
- JSON: parser validation or `biome check`.
- TOML/YAML: parser validation.
- Settings/config: config load verification plus targeted `rg` checks.
- Frontend/app work: build, typecheck, and browser verification when relevant.

## Long-Term Memory Continuation

Covered session:

- `019de56b-1067-7203-bcc7-4f415d5754c9` - long-term memory addition

Reactivation prompt:

```text
Continue from the long-term memory handoff. Inspect the current relevant workspace and the preserved LONG_TERM_MEMORY.md/AGENTS.md files if they still exist, then decide whether the memory belongs in the active SSOT or should remain as historical context. Do not silently promote a temporary projectless memory file into global active policy without explicit user scope.
```

Important context:

- A temporary projectless workspace stored `LONG_TERM_MEMORY.md` and `AGENTS.md` under `C:\Users\anise\Documents\Codex\2026-05-02\my-purpose-is-to-complete-the`.
- That folder was not a Git repo and should be treated as a generated workspace unless the user explicitly makes it canonical.
- If the content is still needed, convert it into a scoped SSOT document after inspecting it, rather than assuming the old thread context.

## Archive Gate for These Chats

Do not archive the covered sessions until:

- This document and the active chats index exist and are readable.
- The replacement thread has read the relevant handoff.
- The user has not marked the old session as still active.
- A fresh `keep-codex-fast` report shows the session is a cleanup candidate or the user explicitly asks to archive it.
- Codex is closed or cleanup is run with the script's explicit wait behavior.

