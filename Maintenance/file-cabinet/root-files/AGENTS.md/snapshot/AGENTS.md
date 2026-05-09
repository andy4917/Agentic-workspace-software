# AGENTS.md

GlobalSSOT root is `%USERPROFILE%\.codex`.

Operational source of truth:
- User instructions in the current conversation are authority inside scope.
- `%USERPROFILE%\.codex` is both CODEX_HOME and GlobalSSOT root.
- `%USERPROFILE%\code\Dev-Product` remains outside this GlobalSSOT maintenance scope unless the user explicitly asks to work there.
- Do not read secrets or credential material unless the user explicitly asks for that specific file.

Use Korean polite language for user-facing output.
When doing Git/GitHub work, use the `git-easy-korean` skill when available.
