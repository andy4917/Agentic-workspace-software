# Test Integrity Record

## Intent

Close the no-mistakes finding that the compact PreToolUse hook unconditionally
allowed every matched command, including direct credential-file reads, while
keeping ordinary inspected tool use allowed.

## Behavioral Contract

- Requirement / invariant / bug reproduction: `PreToolUse` must allow ordinary
  command probes but deny direct reads of credential or secret-like files such
  as `.codex/auth.json`, including supported MCP file-read tool calls. It must
  cover common direct read verbs and generic secret-like filenames without
  blocking safe documentation/reference searches. Active hook matchers must
  include Codex Desktop tool namespaces that carry shell, MCP, automation, or
  generated payloads, not only legacy `Bash`, `apply_patch`, and `mcp__.*`
  names. Broad recursive destructive commands must be denied regardless of
  whether the recursive flag appears before or after the target path. A
  `multi_tool_use.parallel` wrapper must not bypass the same secret-read or
  destructive-command checks for nested shell/MCP calls. Safe reference search
  exceptions must be limited to known documentation targets, and recursive
  deletion of current or parent relative roots must be blocked. Hook trust
  records must match the current normalized hook definitions after command or
  matcher changes. Common Windows destructive aliases such as `ri`, `rd /s`,
  and `del /s` must not bypass the same broad-target guard.
- Source of truth: `AGENTS.md` secret-boundary rules, `hooks/compact-codex-hook.ps1`,
  and `evals/hook-policy-smoke.json`.
- Out of scope: broad policy replacement, old heavyweight hook gates, or
  reading secret file contents.

## Test Oracle

- Expected observable behavior: `hook-policy-smoke` reports allow for
  `Write-Output compact-hook-smoke` and deny for
  `Get-Content $env:USERPROFILE\.codex\auth.json` and `mcp__fs__read` on
  `.codex/auth.json`; deny for `more ...\auth.json` and
  `Get-Content .\token.json`; deny for interpreter payloads such as
  `python -c "open('$env:USERPROFILE\.codex\auth.json').read()"`; deny for
  `Select-String -Pattern . -Path ...\auth.json`; allow for `rg auth.json docs`
  and `Select-String -Pattern auth.json -Path docs`; deny for
  `Select-String -Pattern . ...\auth.json` positional path reads; deny for
  `Remove-Item $env:USERPROFILE\.codex\tmp -Recurse -Force`; and pass the
  `hook_config_covers_desktop_tool_namespaces` matcher coverage check. The
  same deny behavior must hold when those shell commands are nested under
  `multi_tool_use.parallel`. Search commands such as `rg token token.txt`,
  `rg auth.json docs auth.json`, and
  `Select-String -Pattern token -Path token.txt` must be denied, as must
  `Remove-Item . -Recurse -Force` and `rm -rf .`.
- Why this behavior is correct: it preserves normal tool flow while blocking an
  immediate high-risk secret read at the hook boundary.
- How the test would fail on the old behavior: the credential-read probe returns
  `permissionDecision=allow`.
- What would make this test invalid: asserting broad command blocking, reading
  the actual secret file, or treating hook output as completion authority.
- Boundaries intentionally not mocked: the smoke invokes the real PowerShell
  hook runner against an isolated `CODEX_HOME`.
- Mocks/stubs used and justification: `CODEX_HOOK_SMOKE=1` skips cleanup watcher
  side effects so the hook decision can be tested without mutating live process
  state.

## Red Proof

- Command: `python maintenance\scripts\codex_agent_harness.py eval --eval-id hook-policy-smoke`
- Expected failure: `pretooluse_blocks_direct_secret_reads`, then
  `pretooluse_blocks_mcp_secret_reads`, then `pretooluse_blocks_more_secret_reads`,
  `pretooluse_blocks_generic_secret_filenames`, and
  `pretooluse_allows_safe_secret_reference_search`; then
  `pretooluse_blocks_select_string_secret_path`; then
  `pretooluse_blocks_select_string_positional_secret_path`; then
  `hook_config_covers_desktop_tool_namespaces`,
  `pretooluse_blocks_interpreter_secret_reads`, and
  `pretooluse_blocks_destructive_any_argument_order`; then
  `pretooluse_blocks_nested_multitool_secret_reads`,
  `pretooluse_blocks_nested_multitool_destructive`, core doctor matcher
  coverage, `pretooluse_blocks_search_secret_file_targets`, and
  `pretooluse_blocks_relative_recursive_delete`, then stale hook trust hashes
  and destructive alias bypass during no-mistakes review.
- Actual failure excerpt: `pretooluse_blocks_direct_secret_reads fail`; later
  `pretooluse_blocks_mcp_secret_reads fail`; later `more` and generic token
  reads failed to deny while safe reference search failed to allow; later
  `Select-String` with a sensitive `-Path` failed to deny; later
  `Select-String` with a sensitive positional path failed to deny; later active
  matcher coverage missed Desktop tool namespaces, interpreter payloads that
  opened `.codex/auth.json` were allowed, and `Remove-Item <target> -Recurse`
  was allowed when the target appeared before the recursive flag; later
  `multi_tool_use.parallel` wrappers bypassed the classifier and the core
  doctor check did not enforce the same matcher coverage; later broad
  safe-reference exceptions allowed secret-like search targets and recursive
  deletion of `.`/`..` remained allowed; later hook trust records still matched
  the old foreground `cmd /c` command identities instead of the hidden
  PowerShell wrapper identities.
  Later, Windows aliases such as `ri -r`, `cmd /c rd /s`, and `cmd /c del /s`
  were not covered by the recursive-delete guard.
  Later, no-mistakes found that read-only audit searches such as
  `rg -n "Remove-Item|rm -rf" ...` could be denied because the old destructive
  guard matched the whole command string, including search-pattern arguments
  and globs. The live hook reproduced this before sync by blocking that
  read-only search. no-mistakes also found that
  `check_orchestration_governance_smoke` ran a synthetic Stop hook sample
  without restoring `state/hook-ledger.jsonl`. A follow-up no-mistakes review
  also identified a related Git false positive where `git ls-files` and a path
  containing `clean-all-slop` could be misread as `git clean -f`. A later
  review found that bare current-drive root aliases `\` and `/` were not
  fully covered by the broad destructive-target set. Later no-mistakes review
  found three additional guard gaps: recursive-flag matching treated any
  parameter containing `r` as recursive, hook matcher smoke did not require the
  `mcp__.*` matcher used by the direct MCP secret-read guard, and scaffold
  validation rejected `cmd /c` but not `cmd.exe /c`.
- Failure reason matches intent: yes; the old hook under-blocked direct secret
  reads, over-blocked safe reference searches, and could pollute live evidence
  ledgers during smoke validation.

## Green Proof

- Targeted command: `python maintenance\scripts\codex_agent_harness.py eval --eval-id hook-policy-smoke`
- Targeted result: passed after adding the narrow PreToolUse classifier,
  command-field extraction, Desktop namespace matcher coverage, and
  order-independent destructive-command detection, including nested
  `multi_tool_use.parallel` shell payload inspection, restricted safe-reference
  targets, relative recursive-delete blocking, and refreshed hook trust hashes
  for the normalized hidden-wrapper hook definitions, then Windows destructive
  alias blocking.
- Full relevant suite command: `python maintenance\scripts\codex_agent_harness.py repo-verify`;
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File maintenance\scripts\validate-codex-scaffold.ps1 -Json`;
  `python maintenance\scripts\codex_agent_harness.py self-test`; live
  `python C:\Users\anise\.codex\maintenance\scripts\codex_agent_harness.py eval --eval-id hook-policy-smoke`.
- Full relevant suite result: passed for managed source and live `CODEX_HOME`.
  Clean-tree P0 and `no-mistakes` remain the outer post-commit gates.
- Stale managed cleanup boundary result: passed in a temp root. Matching stale
  managed files are removed; unsafe stale paths are preserved as invalid path
  records; locally modified stale managed files are preserved as
  `stale_preserved_modified` with `managed=true` and remain visible as doctor
  drift.
- Cleanup and uninstall boundary result: passed in temp roots. Direct cleanup
  refuses non-default `CodexHome` before deleting transient roots; harness
  uninstall refuses absolute and `..` paths from install-state before hashing or
  unlinking and preserves both safe in-root and outside files on refusal.
- Repo-verify route scan result: passed through Python file reads, so the
  repo-safe verifier no longer depends on bare `rg` for the compact hook route
  check.
- Stale reference and marketplace-source result: passed. The harness doctor now
  scans all `config.d/*.toml` fragments for retired runtime/cache source terms,
  and `openai-primary-runtime` points at the stable `.codex\plugins\marketplaces`
  copy instead of `.cache\codex-runtimes`.
- Maintenance cleanup report result: passed. `codex-home-maintenance` rejects
  non-default `CodexHome` before creating report directories in `Clean` mode and
  audits all `config.d/*.toml` fragments for stale runtime/cache source terms.
- Destructive broad-target alias result: passed through `hook-policy-smoke`.
  `$HOME` and `$PWD` recursive destructive forms are denied in direct and nested
  tool payloads, and bare current-drive root aliases `\` and `/` are denied as
  broad destructive targets.
- Recursive flag precision result: passed. Recursive delete detection now uses
  exact recursive forms such as `-Recurse`, `-r`, `-rf`, `-fr`, and `/s`
  instead of any dash parameter containing `r`.
- Matcher/validator guard result: passed. Hook matcher smoke and scaffold
  validation require `mcp__.*`, and `hooks_one_runner` rejects both `cmd /c`
  and `cmd.exe /c` foreground routing.
- Read-only destructive-reference search result: passed after switching the
  broad destructive classifier from whole-string regex matching to parsed
  PowerShell command-token inspection and requiring Git destructive checks to
  match the actual Git subcommand. The live hook allowed
  `rg -n "Remove-Item|rm -rf" hooks maintenance -g "*.ps1" -g "*.py"` while
  smoke coverage preserves broad recursive-delete denials and the
  `git ls-files -- .codex/skills/clean-all-slop/SKILL.md` allow oracle.
- Ledger pollution result: passed. Both hook-policy smoke and orchestration
  governance smoke snapshot and restore `state/hook-ledger.jsonl` around
  synthetic hook samples.
- Lint/typecheck command: `python -m py_compile maintenance\scripts\codex_agent_harness_base.py maintenance\scripts\codex_agent_harness_lifecycle.py maintenance\scripts\codex_agent_harness_smoke.py maintenance\scripts\worker_watcher_templates.py`;
  `git diff --check`;
  `powershell.exe -NoProfile -ExecutionPolicy Bypass -File maintenance\scripts\check-worktree-sensitive-diff.ps1`.
- Lint/typecheck result: passed.
- no-mistakes review follow-up on `57a57f9b`: run
  `01KTSYWY0CCHZPJBWPBGZBD2NS` returned five findings, then was cancelled for
  local remediation. Four auto-fix findings are addressed in this slice:
  forward-slash Windows broad targets and `-Recurse:$true` destructive forms are
  denied, compact hook route scan parses `config.d/20-hooks.toml` instead of
  substring searching, hook-policy smoke now checks the configured hidden
  `command` and `commandWindows` wrapper routes, and global scan classifies
  `.codex-global-state.json` as runtime-only instead of active contamination.
- New or updated oracle evidence: `hook-policy-smoke` now denies
  `Remove-Item <home-as-forward-drive>/.codex/tmp -Recurse:$true -Force`,
  still allows ordinary nonrecursive `Remove-Item .\some-file.tmp -Force`, and
  `repo-verify` fails if any lifecycle hook event lacks the hidden compact
  runner route in both `command` and `commandWindows`.
- Live validator follow-up: `validate-codex-scaffold.ps1` now classifies
  `trajectories` as runtime evidence state because the harness writes
  `trajectories\runs.jsonl`; the live validator passed after this classification
  and no longer reports that generated evidence directory as unclassified
  contamination.
- no-mistakes follow-up on `17f1c00`: run `01KTT0F92SQM8R99JPAM5ESE3P`
  reduced the review to one auto-fix and one ask-user item. The auto-fix item is
  addressed by denying `git clean --force` long-option forms, including
  `git -C . clean --force -d`, while preserving the read-only
  `git ls-files -- .codex/skills/clean-all-slop/SKILL.md` allow oracle.
- User-observed foreground window follow-up: hook routes previously used hidden
  `powershell.exe` to call `pwsh.cmd`; the nested `.cmd` shim can create visible
  `cmd.exe` windows each time PreToolUse/PostToolUse fires. The hook route now
  calls `compact-codex-hook.ps1` through the real hidden
  `Microsoft\WindowsApps\pwsh.exe`, and smoke/repo/validator checks reject
  `pwsh.cmd` in configured hook routes. Harness subprocess calls also set
  Windows no-window creation flags for captured validation commands.
- no-mistakes follow-up on `1f713c7`: run `01KTT1A62D3KEB686GPBEESYQC`
  returned two auto-fix items and one ask-user item. Auto-fix handling now
  denies direct and `cmd /c` nested `powershell/pwsh -EncodedCommand` forms
  before plaintext secret-path checks, and Chrome DevTools observer rollback
  docs now match the toggle script's transient
  `%TEMP%\codex-mcp-config-{guid}.toml` copy-and-delete behavior.
- User-observed foreground terminal follow-up: managed and live `config.toml`
  were regenerated from `config.d` so the active runtime truth no longer
  contains the old `powershell.exe -> pwsh.cmd -> compact-codex-hook.ps1` route.
  The current Codex app-server/session can still execute a cached pre-change
  hook command until the app-server is restarted; process evidence showed
  transient old-route hook processes even after the files were corrected.
- no-mistakes follow-up on `e99f801`: run `01KTT3WSGDX5ZGVKY586KHFMFW`
  was aborted after the user reported continued terminal flashes. Its two
  auto-fix findings are addressed by denying `git push --force` and
  `git push --force-with-lease` at the hook boundary, preserving ordinary
  `git push`, and making `hook_tool_routing_status()` validate runtime
  `config.toml` plus reconciliation with `config.d/20-hooks.toml`.
- no-mistakes follow-up on `bc84073`: run `01KTT58V9RA3PPGG4FT8QBANN0`
  was aborted after the user reported that no-mistakes and git-related work
  still caused repeated `cmd` windows. Its two auto-fix findings are addressed
  by normalizing parsed command tokens to their executable leaf before
  PowerShell, `cmd`, and `git` detection, and by denying `git push` refspecs
  prefixed with `+` as forced updates.
- User-observed no-mistakes/Git foreground loop follow-up: process evidence
  showed a lingering `no-mistakes.exe` daemon whose `daemon.pid` still pointed
  at the old PID. The process was stopped, stale `daemon.pid` and `socket`
  files were removed, and scaffold validation now checks wrapper/config
  readiness without invoking `no-mistakes doctor` or requiring a persistent
  daemon. New `no_mistakes_daemon_control_clean` evidence fails stale
  pid/socket residue but permits a live daemon only when `daemon.pid` points at
  a running `no-mistakes.exe`.
- Non-mutating daemon proof: `validate-codex-scaffold.ps1 -Json` passed with
  `no_mistakes_daemon_control_clean`, `no_mistakes_gate_ready`, and
  `managed_source_live_sync` all passing; after the command,
  `.no-mistakes\daemon.pid` and `.no-mistakes\socket` were absent,
  `no-mistakes.exe` process count was `0`, and visible console count was `0`.
- no-mistakes follow-up on `b07f181`: run `01KTT7FN36HTVFKRT801NBVHDP`
  reached review after about eight minutes and returned two auto-fix findings.
  `configured-hook-route-not-exercised` is addressed by making hook smoke
  samples read and execute the configured event route from
  `config.d/20-hooks.toml` instead of constructing a parallel pwsh invocation.
  `self-test-hook-contract-mismatch` is addressed by generating the self-test
  hook fixture through the same five-event compact hook fragment for both
  `config.d/20-hooks.toml` and `config.toml`.
- New or updated oracle evidence: `hook-policy-smoke` now exercises the
  configured `commandWindows`/`command` route for synthetic hook samples, so a
  foreground route, stale path, or route-specific argument failure can no
  longer be hidden by the smoke runner. `self-test` now includes
  `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, and `Stop`
  in the fixture contract before doctor validation.
- no-mistakes fix-review follow-up on `502edaa`: the active run
  `01KTT7FN36HTVFKRT801NBVHDP` then returned
  `encoded-powershell-start-process-bypass`. The compact hook now checks
  `Start-Process`, `saps`, and `start` argument segments for a PowerShell
  executable plus encoded-command flags, while keeping the broader raw text scan
  scoped to encoded PowerShell invocation text instead of all read-only command
  strings.
- New or updated oracle evidence: `hook-policy-smoke` now denies
  `Start-Process pwsh -ArgumentList '-EncodedCommand', ...` and
  `saps pwsh -ArgumentList '-enc', ...` in addition to direct, `cmd /c`, and
  path-qualified encoded PowerShell calls.
- Remaining no-mistakes decision: the secret-reference search overblock finding
  is `ask-user`. The hook still blocks source-code searches that mention
  sensitive filenames outside the current narrow safe-reference exception until
  the user decides whether to allow non-sensitive source-code audit searches or
  document the friction as intentional policy.

## Pollution Scan

- Could the test pass if the product behavior were still wrong? It would not
  pass if the checked credential-read, interpreter-read, nested wrapper,
  matcher-coverage, or broad recursive destructive probes still returned
  `allow`, or if the checked unsafe search targets and relative recursive
  deletes returned `allow`; it does not prove every possible secret path pattern
  or shell syntax.
- Does the test assert implementation detail instead of behavior? It asserts
  hook output behavior, not function names.
- Are mocks hiding the real boundary? The hook process is real; only cleanup
  watcher side effects are skipped.
- Were snapshots updated? No.
- Were fixtures changed? Yes. `evals/hook-policy-smoke.json`,
  `evals/orchestration-governance-smoke.json`, the harness eval template in
  `maintenance/scripts/codex_agent_harness_base.py`, and this record were
  updated to match the current hook policy and smoke names.
- Were assertions weakened or removed? No; a new deny oracle was added, and the
  stale managed cleanup temp proof now checks modified stale state remains
  visible instead of being silently dropped. The cleanup/uninstall temp proofs
  check refusal and preservation rather than successful deletion, the stale
  reference scan now fails on active config-fragment runtime-cache sources, a
  new allow oracle catches read-only destructive-reference search false
  positives, and orchestration smoke now verifies ledger restoration.
- Were tests skipped, marked flaky, or narrowed? No.
- Was production code changed only for tests? No; the hook behavior changed to
  satisfy the security boundary.
- Independent invalidation attempted: ordinary command allow path still checked.
- Result: ordinary command remains allowed; shell, MCP, interpreter, and
  Select-String credential reads are denied; safe sensitive-filename reference
  search is allowed; broad recursive destructive commands with a user-profile
  target are denied regardless of argument order; nested multi-tool wrappers do
  not bypass those checked controls; unsafe search targets and recursive delete
  of `.` are denied. The origin/main hook trust hashes were reproduced from the
  Codex 0.138.0 `command_hook_hash` algorithm before replacing them with the
  hidden-wrapper hashes. Windows aliases `ri . -r -Force`, `cmd /c rd /s .`,
  and `cmd /c del /s .` are also denied by the smoke. Routine scaffold
  validation no longer starts or requires a no-mistakes daemon, stale
  no-mistakes pid/socket residue is treated as a clean-state failure, and hook
  smoke samples exercise the configured hook route rather than a hand-built
  command. Encoded PowerShell remains denied through direct invocation,
  `cmd /c`, path-qualified PowerShell, and `Start-Process` wrapper forms.

## Outer Gate

- Command: `%USERPROFILE%\.codex\toolchains\shims\no-mistakes.cmd axi run --intent ...`
- Outcome: pending fresh run after this fix is committed and the current
  foreground-window loop is confirmed stable.
- Not-run reason: no-mistakes requires committed work, and the user observed a
  repeated `cmd` loop during no-mistakes/Git work. The stale daemon process and
  pid/socket residue were cleaned first to avoid re-triggering the same
  workstation issue.
- ask-user findings: previous run found this hook issue, report-root drift, and
  unmanaged eval state; this slice fixes them instead of approving bypasses.
