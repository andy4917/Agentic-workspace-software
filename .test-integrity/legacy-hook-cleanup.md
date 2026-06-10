# Test Integrity Record

## Intent

Remove retired hook/archive/backup surfaces from the Codex global scaffold and
keep the active hook validation aligned to the compact hook route.

## Behavioral Contract

- Requirement / invariant / bug reproduction: active hooks must route only to
  `hooks/compact-codex-hook.ps1` through `config.d/20-hooks.toml`; retired
  `hooks.json` and `lightweight-codex-*` wiring must not be active evidence.
- Source of truth: `AGENTS.md`, `config.d/20-hooks.toml`,
  `hooks/compact-codex-hook.ps1`, and live scaffold validator output.
- Out of scope: testing Codex Desktop proprietary hook internals beyond the
  documented command route exposed in config.

## Test Oracle

- Expected observable behavior: `hook-policy-smoke` fails when the compact hook
  sample cannot emit the configured context, and passes when the smoke runner
  executes the same `pwsh.cmd` route used by live config.
- Why this behavior is correct: live hook config invokes
  `%USERPROFILE%\.codex\toolchains\shims\pwsh.cmd`; sampling with
  `powershell.exe` is not the active runtime route.
- What would make this test invalid: accepting legacy hook names, ignoring hook
  stdout, or treating a different shell runtime as equivalent without evidence.
- Boundaries intentionally not mocked: the smoke uses the real PowerShell hook
  script and real configured shim path.
- Mocks/stubs used and justification: synthetic hook payloads only, to avoid
  mutating real prompt/tool content.

## Red Proof

- Command: `python maintenance\scripts\codex_agent_harness.py eval --eval-id hook-policy-smoke`
- Actual failure excerpt: `user_prompt_submit_emits_compact_context`,
  `session_start_emits_minimal_scaffold_context`, and
  `pretooluse_allows_and_records` failed.
- Failure reason matches intent: yes. The smoke used `powershell.exe`, while the
  active hook route uses `pwsh.cmd`.

## Green Proof

- Targeted command: `python maintenance\scripts\codex_agent_harness.py eval --eval-id hook-policy-smoke`
- Targeted result: pass after switching the smoke runner to `pwsh.cmd`.
- Full relevant suite command: `python maintenance\scripts\codex_agent_harness.py repo-verify`
- Full relevant suite result: pass.
- Lint/typecheck command: `python -m py_compile` for touched harness modules.
- Lint/typecheck result: pass.

## Pollution Scan

- Could the test pass if retired hook routing were still active? No, it scans
  `config.d/20-hooks.toml` for the compact route and rejects legacy hook names.
- Does the test assert implementation detail instead of behavior? It asserts the
  configured command route and emitted hook contract, which are public scaffold
  behavior for this repo.
- Are mocks hiding the real boundary? No external boundary is mocked; only hook
  event payloads are synthetic.
- Were snapshots updated? No.
- Were fixtures changed? Only the eval definition text was updated to describe
  the compact hook contract.
- Were assertions weakened or removed? No. Assertions were moved from legacy
  heavyweight hook behavior to the current compact hook behavior.
- Were tests skipped, marked flaky, or narrowed? No.
- Was production code changed only for tests? No. The compact hook stdin reader
  was hardened and the smoke runner was aligned with live config.
- Independent invalidation attempted: searched managed and live active surfaces
  for retired hook names and archive-first routes.
- Result: no active live matches for retired hook names after cleanup.

## Outer Gate

- Command: pending `no-mistakes` after commit on feature branch.
- Outcome: not run at record creation time.
- Not-run reason: no-mistakes validates committed branch history, so final gate
  evidence is recorded in the completion report after staging and commit.
- ask-user findings: none yet.
