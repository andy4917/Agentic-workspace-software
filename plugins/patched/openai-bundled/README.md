# Historical OpenAI Bundled Snapshot

This tree is a historical patched snapshot, not the current OpenAI bundled
plugin runtime.

Source marker:

- `.codex-patched-source.txt` points to a Codex app bundle from `26.506.3741`.

Current runtime evidence lives under `%USERPROFILE%\.codex\plugins\cache` and
must be checked with `maintenance\scripts\validate-codex-scaffold.ps1`,
`maintenance\scripts\check-automation-plugin-health.ps1`, plugin manifests, or
fresh tool calls.

Do not compare this snapshot to current Browser, Chrome, or Computer Use
behavior as a PASS/FAIL source unless a task explicitly asks to audit this
historical snapshot.
