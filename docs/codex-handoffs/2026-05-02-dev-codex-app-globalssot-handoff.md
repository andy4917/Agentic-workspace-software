# Dev_Codex_App_GlobalSSOT Handoff - 2026-05-02

Reactivation prompt:

```text
We are continuing from this handoff. Read this document first, inspect C:\Users\anise\.codex\Dev_Codex_App_GlobalSSOT and the relevant Codex local-state files, verify what still applies, and continue from the next steps without assuming the old chat context is available.
```

## Repo / Path

- Canonical folder: `C:\Users\anise\.codex\Dev_Codex_App_GlobalSSOT`
- Not a Git repository at handoff time: `git status --short` returned `fatal: not a git repository`.
- Historical generated working folders were under `C:\Users\anise\Documents\Codex\2026-05-01` and `C:\Users\anise\Documents\Codex\2026-05-02`.
- The old dated canonical-root folder was identified as a generated working copy and root-split artifact, not the desired canonical SSOT root.

## Covered Sessions

- `019de39e-c0c9-79b2-b605-e353c8b198b4` - `Update AGENTS.md contract`
- `019de413-0a61-7613-a804-2aed3dd1aa45` - `Codex 앱 루트 표준화`
- `019de445-23ce-7bc3-b2bc-08a83f517508` - `Install Vowline`
- `019de474-a195-7283-99e2-f4e0ba2a8b2c` - `Dev_Codex_App_GlobalSSOT 고정`
- `019de482-0c60-7b83-8c1c-30c815b0e97a` - `전역 설정 적용 검증`
- `019de4ee-ca88-7b41-bf81-54cd487d8bb3` - read-only root split investigation

## Current Goal

Maintain one clear Codex App SSOT for local agent behavior, hook behavior, contract state, naming, and local-state maintenance while avoiding false completion, hidden fallback, stale global control-plane rules, and accidental out-of-scope mutation.

## Completed Work

- Established `C:\Users\anise\.codex\Dev_Codex_App_GlobalSSOT` as the canonical SSOT folder.
- Retargeted `C:\Users\anise\.codex\hooks.json` to use the hook runner under the canonical SSOT folder.
- Removed the dated Documents canonical-root copy after identifying it as the root-split source.
- Added and maintained SSOT documentation and registry files: `AGENT.md`, `AGENTS.md`, `AGENTS.override.md`, `CHANGELOG.md`, `MANIFEST.json`, `ROOT_MAP.json`, `README.md`, `VERSION.md`, `WINDOWS_DEV_TERMS.md`, and folder inventories.
- Created clean-slate declarative config under `Settings\Codex_App_DECLARATIVE`.
- Created runtime contract files under `Settings\Codex_App_RUNTIME`.
- Created hook config and runner files under `Settings\Dev_Codex_HOOKS`.
- Added consolidated hook behavior for `SessionStart`, `UserPromptSubmit`, `PreToolUse`, and `Stop`.
- Moved Vowline startup context into the SSOT SessionStart hook output and removed the duplicate `.codex\skills\vowline` copy after matching it to the canonical `.agents` skill by SHA256.
- Reduced plugin config/cache to the requested plugin set: Browser Use, GitHub, and Spreadsheets.
- Enabled `/goal` in the active Codex config and mirrored that intent into `Settings\Codex_App_DECLARATIVE\clean-slate.agent.config.toml`.
- Added the English `AGENT.md` proactive-need sentence.

## Files Touched or Investigated

- `C:\Users\anise\.codex\Dev_Codex_App_GlobalSSOT\AGENT.md`
- `C:\Users\anise\.codex\Dev_Codex_App_GlobalSSOT\AGENTS.md`
- `C:\Users\anise\.codex\Dev_Codex_App_GlobalSSOT\CHANGELOG.md`
- `C:\Users\anise\.codex\Dev_Codex_App_GlobalSSOT\MANIFEST.json`
- `C:\Users\anise\.codex\Dev_Codex_App_GlobalSSOT\ROOT_MAP.json`
- `C:\Users\anise\.codex\Dev_Codex_App_GlobalSSOT\Settings\Codex_App_DECLARATIVE\clean-slate.agent.config.toml`
- `C:\Users\anise\.codex\Dev_Codex_App_GlobalSSOT\Settings\Dev_Codex_HOOKS\codex-ssot-hook.ps1`
- `C:\Users\anise\.codex\Dev_Codex_App_GlobalSSOT\Settings\Codex_App_RUNTIME\active_contract.json`
- `C:\Users\anise\.codex\hooks.json`
- `C:\Users\anise\.codex\config.toml`
- `C:\Users\anise\.codex\plugins\local-marketplaces`
- `C:\Users\anise\.codex\.tmp`
- `C:\Users\anise\.codex\memories`
- `C:\Users\anise\.codex\session_index.jsonl`
- `C:\Users\anise\.codex\sessions`

## Evidence and Commands Already Run

- `codex --version` showed `codex-cli 0.128.0-alpha.1`.
- Hook dry-runs showed the root resolving to `C:\Users\anise\.codex\Dev_Codex_App_GlobalSSOT`.
- Hook registration was checked for one command each on `SessionStart`, `UserPromptSubmit`, `PreToolUse`, and `Stop`.
- Local marketplace folders were checked and reduced to Browser Use, GitHub, and Spreadsheets.
- `rg` and PowerShell inspection were used repeatedly to verify stale root references and config state.
- TOML parsing was used to verify `/goal` config changes.
- `git status --short` in the canonical folder confirmed it is not currently a Git repository.
- `keep-codex-fast` report-only run created a backup and found no old session/archive candidates.

## Known Errors / Warnings / Blockers

- Codex 0.128.0-alpha.1 still performs a built-in remote featured plugin warm request when `features.plugins = true`; this can return Cloudflare 403 and recreate `.tmp\plugins` with unrequested remote marketplace entries.
- `codex exec --disable plugins` suppresses that plugin warm behavior, but it disables the user-requested plugin capability too.
- PowerShell shell snapshot limitations remain in Codex 0.128.
- The top Node process report in the keep-codex-fast script failed due to a non-zero PowerShell process query exit.
- The canonical SSOT folder is not a Git repository, so use filesystem evidence rather than Git history unless a repository is intentionally initialized later.
- Old archive folders intentionally retain historical content; do not treat archive presence as active-state contamination without checking whether it is referenced by live config.

## Constraints and Preferences

- User-facing output should be Korean polite language unless explicitly requested otherwise.
- The user is the Production Owner; the agent should handle ordinary implementation and validation without making the user the operator.
- Do not treat scores, tests, PASS, hook PASS, package verification, final output, or self-certification as authority or completion.
- Do not add fallback, legacy bridge, compatibility path, fake success, or hidden dead path unless the user explicitly scopes that work.
- Block only real risk operations and continue in-scope safe work.
- Preserve continuity before archiving chats or moving local state.

## Next Steps

1. Re-run `keep-codex-fast` in report-only mode before any cleanup.
2. Verify whether `features.plugins = true` still triggers remote featured plugin warm and `.tmp\plugins` recreation in the current Codex build.
3. Inspect `C:\Users\anise\.codex\hooks.json` and `Settings\Dev_Codex_HOOKS\codex-ssot-hook.ps1` together before changing hook behavior.
4. Keep `Settings\Codex_App_RUNTIME\active_contract.json` aligned with the current blocker state.
5. Add any future local-state cleanup result to `CHANGELOG.md` and this handoff folder.
6. Do not archive the covered sessions until this handoff has been read by the replacement thread and the user confirms the old chat is no longer needed.

