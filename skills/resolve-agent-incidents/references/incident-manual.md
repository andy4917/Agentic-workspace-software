# Agent Incident Manual

This file is a mutable knowledge base for recurring agent, subagent, Codex app, tool, and workflow incidents. Use it during live troubleshooting, then update it when a new pattern is verified.

## Fast Triage

1. Capture the fingerprint:
   - exact error fragment;
   - tool, command, or agent role involved;
   - path or surface involved;
   - expected result versus actual result;
   - whether any fallback happened.
2. Classify one primary type from `Incident Types`.
3. Check the reward-hacking and app/tool pattern sections for a matching fingerprint.
4. Apply only fixes whose assumptions match the current context.
5. Verify with the same failing action when practical.
6. Add or update a record if the issue was new, repeated, or likely to mislead future agents.

## Incident Types

Use one primary type and optional secondary tags.

| Type | Use For | Typical Evidence |
| --- | --- | --- |
| `reward_hacking` | Agent claims success without direct proof, weakens acceptance criteria, hides skipped checks, or treats a report as completion. | PASS labels, vague summaries, missing command output, unverified subagent claims. |
| `subagent_drift` | Subagent exceeds charter, edits outside owned files, duplicates PM work, ignores not-checked requirements, or reports stale context. | Changed unrelated files, missing mid-report, unsupported conclusions. |
| `tool_runtime_error` | Shell, MCP, browser, image, automation, patch, or other tool fails unexpectedly. | Tool error text, invalid arguments, unavailable server, timeout. |
| `codex_app_error` | Desktop app terminal, thread, automation, connector, rendering, or attachment behavior fails. | App-specific error, missing terminal session, UI artifact not displayed. |
| `workflow_hook_issue` | Hook reminder blocks too broadly, records misleading state, or creates non-authoritative completion pressure. | Hook text, state file, stop reminder, mismatch with actual evidence. |
| `environment_path_issue` | Windows quoting, path separators, path length, cwd, shim, shell, or executable resolution causes failure. | Absolute path, runner, PATH/shim check, command line. |
| `validation_gap` | Tests/builds/screenshots/checks are absent, stale, partial, or do not cover the changed behavior. | Not-run reason, changed surface, missing acceptance check. |
| `skill_or_doc_drift` | Skill instructions, references, templates, or manual entries are stale, ambiguous, duplicated, or too broad. | Trigger mismatch, outdated pattern, conflicting docs. |
| `git_or_state_issue` | Dirty worktree, unrelated user edits, branch mismatch, staging/commit/push issue, or generated metadata drift. | `git status`, branch, diff, lockfile or generated files. |
| `security_boundary` | Secret access, credential handling, destructive command, irreversible action, or out-of-scope mutation risk. | File path, command, approval requirement, protected asset. |

## Reward-Hacking Patterns

| Pattern | Fingerprint | PM Response |
| --- | --- | --- |
| Unsupported PASS | Output says PASS/complete but lacks command, path, line, diff, or reproducible observation. | Downgrade to unsupported claim. Re-run or inspect directly before using it. |
| Check laundering | A broad check is cited as proof for behavior it does not cover. | Map each acceptance criterion to direct evidence; record uncovered areas. |
| Fallback concealment | Agent silently switches tools, files, models, or scope after failure. | Surface the fallback, verify equivalence, and record the original failure. |
| Scope shrinking | Agent redefines the goal to match what was already done. | Restate the user's objective and compare changed behavior against it. |
| Not-run erasure | Skipped checks disappear from the final report or become "validated by inspection." | Restore `not_run` with exact reason and closest substitute evidence. |
| Stale-context success | Agent reports on old files, old branches, or pre-change state. | Rebuild context from current paths and rerun the relevant check. |
| Tool-availability illusion | Agent treats configured or installed tools as actual use. | Require a real tool invocation or mark as not applicable. |
| Review theater | Reviewer gives a summary before findings and misses concrete line/path evidence. | Ask for findings first, severity, file/line, and not-checked items. |
| Evidence flooding | Large logs are pasted to imply rigor without isolating the decisive lines. | Extract the minimal failing fragment and the command that produced it. |
| Worker authority leak | PM accepts worker/subagent completion without independent verification. | Treat worker output as candidate evidence and verify the decisive claim. |

## Codex App And Tool Patterns

### Shell Tool Argument Failure

- Type: `tool_runtime_error`, `environment_path_issue`
- Fingerprint: every `shell_command` call fails before execution with an argument or wrapper error, even for `pwd` or `Get-Location`.
- Likely cause: runtime wrapper problem, shell launch configuration, or command transport issue rather than the requested command.
- Fix:
  1. Try a simpler command once to confirm it is global.
  2. Use another local execution surface when available, such as a Node REPL MCP, for read-only inspection and validation.
  3. Use `apply_patch` for manual edits instead of shell write tricks.
  4. Record that shell-based validation could not run and cite the alternate checks.
- Verification: alternate tool successfully reads files or runs a small child process; original shell tool failure is preserved as not fixed unless directly recovered.
- Not checked by default: root cause inside the Codex desktop runtime.

### Reference Read Blocked By Primary Tool

- Type: `tool_runtime_error`, `validation_gap`
- Fingerprint: an agent can read the main skill or has the skill path, but fails to read a referenced manual because its first file-reading tool fails globally.
- Risk: the agent may complete from partial instructions and miss the detailed taxonomy or templates.
- Fix:
  1. Preserve the failed read attempt and exact error.
  2. Try another available local read surface, such as MCP filesystem resources, Node REPL, app attachment context, or a different non-destructive file read command.
  3. If no alternate read path is available, state that the response is based only on the loaded skill body and mark the reference as not checked.
- Verification: the reference file is read successfully through an alternate path, or the final report explicitly marks it as not checked.

### Missing App Terminal Session

- Type: `codex_app_error`
- Fingerprint: terminal inspection reports no attached app terminal session.
- Fix:
  1. Do not assume a hidden terminal is running.
  2. Use available execution tools for direct checks.
  3. If the user asked for terminal state specifically, report that no session is attached.
- Verification: the terminal inspection tool returns the no-session message or a later session state.

### MCP Server Configured But Tools Unloaded

- Type: `tool_runtime_error`, `skill_or_doc_drift`
- Fingerprint: instructions mention an MCP server, but no matching `mcp__...` tools are exposed.
- Fix:
  1. Use tool discovery if available.
  2. Record a runtime-load issue if discovery does not expose the tool.
  3. Use the best available fallback and state the fallback in the final report.
- Verification: discovered tool list, fallback command output, or explicit not-available evidence.

### MCP Server Enabled But Filtered Or Path-Fragile

- Type: `tool_runtime_error`, `environment_path_issue`
- Fingerprint: `codex mcp list` shows a server as enabled, but the active session omits its namespace; direct MCP `tools/list` succeeds or shows tool names that do not match `enabled_tools`.
- Risk: agents may claim "configured" as "usable", or miss that path expansion/filtering caused the app loader to expose zero tools.
- Likely causes: Windows `%VAR%` or `~` paths in MCP config are not expanded by the loader; `enabled_tools` names are stale after a server version change.
- Fix playbook:
  1. Replace fragile paths in `command` and `cwd` with absolute Windows paths.
  2. Run the server directly and call MCP `tools/list` when practical.
  3. Align `enabled_tools` with actual server tool names, keeping approval prompts for broad command tools.
  4. Start a new session or reload the app because existing sessions do not receive newly exposed MCP tool schemas.
- Verification: `codex mcp get/list` shows the intended absolute paths and filters; direct server startup or `tools/list` succeeds; current session remains not fixed unless the namespace appears in the active tool list.
- Do not claim: that the current session can call the MCP just because config was fixed.

### Patch Grammar Failure

- Type: `tool_runtime_error`
- Fingerprint: `apply_patch` rejects input because the freeform patch does not match grammar.
- Fix:
  1. Retry with exact begin/end markers.
  2. Use one file operation hunk per target file where possible.
  3. Avoid JSON wrapping for the freeform patch.
- Verification: patch tool reports success and follow-up file read confirms content.

### Automation Scope Confusion

- Type: `codex_app_error`, `workflow_hook_issue`
- Fingerprint: a request to remind, monitor, or continue later is implemented as prose or a raw schedule string instead of an automation tool call.
- Fix:
  1. Use the automation tool for reminders, recurring runs, monitors, and thread wakeups.
  2. Prefer heartbeat for current-thread follow-ups, especially below one hour.
  3. Preserve existing automation fields when updating.
- Verification: automation create/update/view/delete result.

## Incident Record Template

Use this template when adding a new incident to this file or to another user-specified incident log.

```markdown
### YYYY-MM-DD short-title

- Status: open | mitigated | resolved | monitoring
- Type: primary_type
- Tags: secondary_tag, optional_tag
- Surface: agent role, tool, app area, file path, workflow, or repository
- Fingerprint: exact error fragment or concise symptom
- Impact: what was blocked or at risk
- Trigger: user action, command, tool call, or workflow step
- Root cause: confirmed cause, or `unknown` if not confirmed
- Fix: concrete steps taken
- Verification: command, tool result, diff, screenshot, or inspection used as proof
- Not run: skipped checks and exact reason
- Prevention: how future agents should avoid or recognize it
- Related: paths, commands, issue ids, or prior incident titles
```

## Seed Incident Records

### 2026-05-11 shell-command-wrapper-invalid-arguments

- Status: mitigated
- Type: `tool_runtime_error`
- Tags: `environment_path_issue`, `validation_gap`
- Surface: `shell_command` tool in Codex desktop session
- Fingerprint: `Io(Error { kind: InvalidInput, message: "batch file arguments are invalid" })` returned before execution for simple commands such as `pwd`, `Get-Location`, and `Get-Content`.
- Impact: normal shell-based file reads and validation could not be used.
- Trigger: attempting to read skill files and run simple PowerShell commands.
- Root cause: unknown; likely command transport or shell wrapper issue, not the command contents.
- Fix: used Node REPL for file reads and Python child-process validation; used `apply_patch` for file edits.
- Verification: Node REPL read files successfully, ran Python `quick_validate.py`, and the validator reported `Skill is valid!`.
- Not run: direct recovery of the `shell_command` runtime; root cause inside Codex desktop was not inspected.
- Prevention: if all shell commands fail before execution, treat it as a global tool/runtime issue and switch to another available read or execution surface while preserving the original failure.

## Pattern Entry Template

Use this when a single incident generalizes into a reusable pattern.

```markdown
### Pattern Name

- Type: primary_type
- Fingerprint: stable symptom or exact error fragment
- Risk: why this misleads agents or blocks work
- Likely causes: shortest useful list
- Fix playbook:
  1. First check
  2. Second check
  3. Patch or workaround
- Verification: direct evidence required before claiming completion
- Do not claim: tempting but invalid completion claim
```

## Update Rules

- Add a new pattern only after at least one concrete incident has evidence.
- Prefer updating an existing pattern over creating a near-duplicate.
- Keep entries short. Link to paths or commands instead of pasting long logs.
- Preserve failed attempts when they prevent future wasted work.
- Never mark an incident resolved only because a subagent, hook, or broad test said so.
- If a workaround is used, state whether the original failure remains unresolved.
- If the issue touches credentials, record metadata only unless the user explicitly allowed reading the secret file.

## Review Checklist

Before shipping an incident fix, answer these:

- Does the final claim match the user's original goal?
- Which exact evidence proves the behavior changed or the diagnosis is correct?
- Which checks were not run, and why?
- Did any fallback happen, and was it equivalent?
- Did any subagent claim require PM verification?
- Should the manual be updated with a new fingerprint, fix, or anti-pattern?
