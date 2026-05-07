# Active Repo Chats Index - 2026-05-02

Reactivation prompt:

```text
We are continuing Codex local-state and Dev_Codex_App_GlobalSSOT work from preserved handoffs. Read this index and the linked handoff documents first, inspect the current filesystem state, verify what still applies, and continue without relying on the old chat context.
```

## Scope

- Canonical working folder: `C:\Users\anise\.codex\Dev_Codex_App_GlobalSSOT`
- Codex home inspected for session continuity: `C:\Users\anise\.codex`
- Handoff folder: `C:\Users\anise\.codex\Dev_Codex_App_GlobalSSOT\docs\codex-handoffs`
- Date inspected: 2026-05-02

## Keep-Codex-Fast Report

- Mode run: report-only
- Backup created by the report run: `C:\Users\anise\Documents\Codex\codex-backups\keep-codex-fast-20260502-192409`
- Active sessions size: about 0.012 GB
- Old session candidates: 0
- Old session candidate size: 0.000 GB
- Stale worktree candidates: 0
- Config prune candidates: 0
- Windows extended path candidates in thread cwd fields: 7
- Log size: about 85.5 MB
- Top Node process report: skipped because the bundled PowerShell process query returned a non-zero exit status

No session archive was applied during this pass. Codex is active, the report found no old session archive candidates, and continuity preservation was the priority.

## Active Chats Worth Preserving

| Thread | Session id | Size | Original cwd | Continuity action |
| --- | --- | ---: | --- | --- |
| `전역 설정 적용 검증` | `019de482-0c60-7b83-8c1c-30c815b0e97a` | 5504 KB | `C:\Users\anise\Documents\Codex\2026-05-02\dev-codex-app-globalssot-codex-codex` | Covered by `2026-05-02-dev-codex-app-globalssot-handoff.md` |
| `Update AGENTS.md contract` | `019de39e-c0c9-79b2-b605-e353c8b198b4` | 1062 KB | `C:\Users\anise\Documents\Codex\2026-05-01\agents-md-config-replacement-user-frame` | Covered by `2026-05-02-dev-codex-app-globalssot-handoff.md` |
| `Dev_Codex_App_GlobalSSOT 고정` | `019de474-a195-7283-99e2-f4e0ba2a8b2c` | 885 KB | `C:\Users\anise\Documents\Codex\2026-05-02\dev-codex-app-globalssot-canonical-root` | Covered by `2026-05-02-dev-codex-app-globalssot-handoff.md` |
| `Install Vowline` | `019de445-23ce-7bc3-b2bc-08a83f517508` | 825 KB | `C:\Users\anise\Documents\Codex\2026-05-02\install-vowline-for-yourself-by-following` | Covered by `2026-05-02-dev-codex-app-globalssot-handoff.md` |
| `Codex 앱 루트 표준화` | `019de413-0a61-7613-a804-2aed3dd1aa45` | 752 KB | `C:\Users\anise\Documents\Codex\2026-05-02\powershell-dev-codex-app-globalssot-maintainence` | Covered by `2026-05-02-dev-codex-app-globalssot-handoff.md` |
| `/goal 명령어 활성화` | `019de826-b37b-7d20-9718-72660a905c22` | 544 KB | `C:\Users\anise\Documents\Codex\2026-05-02\config-goal-true` | Covered by `2026-05-02-plugin-hooks-goal-toolchain-reactivation-prompts.md` |
| `플러그인 3개 제한 확인` | `019de50a-159e-7c40-a4a0-a344e99487a2` | 265 KB | `C:\Users\anise\Documents\Codex\2026-05-02\codex-threads-019de474-a195-7283-99e2` | Covered by `2026-05-02-plugin-hooks-goal-toolchain-reactivation-prompts.md` |
| `조사 경로 이원화 원인` | `019de4ee-ca88-7b41-bf81-54cd487d8bb3` | 254 KB | `C:\Users\anise\Documents\Codex\2026-05-02\dev-codex-app-globalssot-codex-codex` | Covered by `2026-05-02-dev-codex-app-globalssot-handoff.md` |
| `장기 메모리 추가` | `019de56b-1067-7203-bcc7-4f415d5754c9` | 193 KB | `C:\Users\anise\Documents\Codex\2026-05-02\my-purpose-is-to-complete-the` | Covered by `2026-05-02-plugin-hooks-goal-toolchain-reactivation-prompts.md` |

## Archive Gate

Before archiving any listed session, verify:

- The linked handoff documents still exist.
- The target continuation thread has read the relevant handoff.
- Any session marked as still active by the user is left active.
- Codex is closed or cleanup is run with the explicit wait behavior supported by `keep-codex-fast`.
- The cleanup script is run in report mode again immediately before any mutating cleanup.

Recommended next command before a future cleanup:

```powershell
python C:\Users\anise\.codex\skills\keep-codex-fast\scripts\keep_codex_fast.py
```

