---
name: no-mistakes
description: Validate your code changes through the no-mistakes pipeline - automated code review, tests, lint, docs, push, PR, and CI - before they reach upstream. Use when the user asks to run no-mistakes, gate or ship or validate their changes, push safely, or invokes /no-mistakes.
user-invocable: true
---

# no-mistakes

`no-mistakes` is a local gate that validates your code changes through a pipeline
(intent, rebase, review, test, document, lint, push, PR, CI) before they reach
upstream. You drive it through the managed wrapper's `axi` command family, which
prints machine-readable [TOON](https://toonformat.dev) to stdout and progress to
stderr.
On this workstation, invoke it through the managed wrapper
`%USERPROFILE%\.codex\toolchains\shims\no-mistakes.ps1` from PowerShell/Codex-managed runs; do not call bare
`no-mistakes`, because the wrapper disables telemetry/update checks and fixes
the child PATH used by no-mistakes-spawned Codex agents. The `.cmd` wrapper is
kept only for cmd.exe compatibility.

When you are already running inside a no-mistakes-spawned gate worktree or agent
step, do not invoke `no-mistakes` again, including `--version`, `doctor`, `axi`,
`daemon`, or this wrapper. Recursive no-mistakes CLI calls can interfere with
the active pipeline daemon. Use project-native checks, scaffold validator output,
or fake-binary wrapper probes instead.

When the user invokes `/no-mistakes`, validate the changes and report the outcome.
If the user asks for something specific, translate that request into the matching
`axi run` flags yourself - for example, "skip the lint step" becomes `--skip=lint`.
Run `& "$env:USERPROFILE\.codex\toolchains\shims\no-mistakes.ps1" axi run --help` to
see the available flags.

## Before you start

- The work you want validated must be **committed** on a branch. The gate
  validates committed history, not your uncommitted working tree.
- You must be on a **feature branch**, not the repository's default branch.
- The repository must already be initialized with `no-mistakes init`.

If any of these is not met, `axi run` returns an `error:` with the exact command
to fix it - read it and act on it (commit your work, or create a branch).

## Intent is required

When you start a run you must pass `--intent`: **what the user set out to
accomplish** - the goal or request behind this work, in their terms. This is not
a description of the diff or the files you changed; it is the objective the
change is meant to achieve. You know it from the conversation, so pass it
directly - no-mistakes uses it verbatim instead of inferring it from local agent
transcripts (slower and flakier).

Err on the side of completeness, not brevity. The review step uses `--intent`
to tell a deliberate decision apart from a mistake, so a thin one-line summary
makes it flag things the user already chose. Capture the nuance: the user's
goal, the specific decisions and tradeoffs they made along the way, any
constraints or approaches they ruled in or out, and anything they explicitly
asked for that might otherwise look surprising in the diff. A few sentences to a
short paragraph is normal - write down what you learned from the conversation
that a reviewer reading only the diff would not know.

## Validate and decide

Run the pipeline and decide on its findings as they come up:

1. Start the run. It blocks until the first decision point or the end:
   ```sh
   & "$env:USERPROFILE\.codex\toolchains\shims\no-mistakes.ps1" axi run --intent "<what the user set out to accomplish>"
   ```
2. If the output contains a `gate:` object, the pipeline is waiting on you.
   Read its `findings` table. Each finding has an `id`, `severity`,
   `file`, `description`, and an `action` that tells you how the
   pipeline classified it:
   - `auto-fix` - a mechanical, low-risk fix you can safely make yourself.
   - `no-op` - informational only; nothing to do.
   - `ask-user` - the finding challenges the user's deliberate intent or
     touches product behavior. This is a call only the user can make - see
     [Escalate `ask-user` findings](#escalate-ask-user-findings) below.

   Choose one response:
   ```sh
   # accept the step as-is and continue
   & "$env:USERPROFILE\.codex\toolchains\shims\no-mistakes.ps1" axi respond --action approve

   # have the agent fix specific findings, then continue
   & "$env:USERPROFILE\.codex\toolchains\shims\no-mistakes.ps1" axi respond --action fix --findings <id1,id2> --instructions "<optional guidance>"

   # skip this step only with an explicit run-specific waiver or inapplicable-step reason
   & "$env:USERPROFILE\.codex\toolchains\shims\no-mistakes.ps1" axi respond --action skip
   ```
    Each `respond` blocks until the next `gate:`, `checks-passed` decision point, or final outcome.
   Do not use `skip` as a convenience bypass. Record the waiver or exact
   inapplicable-step reason before using it.
3. Repeat step 2 until the output has an `outcome:` instead of a `gate:`. The
   outcomes are:
   - `checks-passed` - the change is validated and CI is green, but the PR is
     not merged yet. **You are done driving the pipeline.** Do not wait for the
     merge: tell the user the PR is ready and ask them to review and merge it
     (the PR link is in the `help` line). no-mistakes keeps monitoring the PR
     in the background, so a human can watch it in the TUI.
   - `passed` - the changes cleared the gate and the PR was merged or closed.
   - `failed` or `cancelled` - they did not; read the output and address it.

The CI step deliberately watches the PR until it is merged or closed, so
`axi run` returns `checks-passed` the moment checks are green rather than
blocking on the human merge. Never poll or re-run waiting for the merge yourself.

## Escalate `ask-user` findings

A gate whose findings are all `auto-fix` or `no-op` is safe to drive on your
own judgment: fix or approve as appropriate. But a finding marked
`ask-user` is a decision that belongs to the user, not you - the pipeline
flagged it because it challenges their deliberate intent or changes product
behavior. Do not approve, fix, or skip it on your own. Instead, stop and bring
it to the user before you respond:

- Relay each `ask-user` finding to them as the pipeline wrote it - its
  `id`, `file`, and full `description` verbatim. Do not paraphrase,
  summarize away the detail, or pre-judge the answer.
- Ask how they want to proceed, then translate their decision into the matching
  `respond` call: `--action fix` (pass their guidance through
  `--instructions`), `--action approve`, or `--action skip`.

Do not pass `--yes` by default. On this workstation, `--yes` is allowed only
after the user gives an explicit waiver for the current run that covers
unattended approval, including `ask-user` findings. Without that waiver,
surface `ask-user` findings to the user and wait for their decision.

## Inspecting state

```sh
& "$env:USERPROFILE\.codex\toolchains\shims\no-mistakes.ps1" axi               # home view: active run, recent runs, next steps
& "$env:USERPROFILE\.codex\toolchains\shims\no-mistakes.ps1" axi status        # full detail of the active (or most recent) run
& "$env:USERPROFILE\.codex\toolchains\shims\no-mistakes.ps1" axi logs --step <name> --full   # full log output of one step
& "$env:USERPROFILE\.codex\toolchains\shims\no-mistakes.ps1" axi abort         # cancel the active run
```

## Reading the output

- Output is TOON: `key: value` pairs, `name[N]{cols}:` tables, and `help[N]:` hints.
- The `help` list at the bottom of most responses tells you the next commands to run.
- Errors are printed as `error: ...` on stdout with a `help` list; act on the suggestion.
- Exit codes: `0` success, no-op, or normal decision gates, `1` failed or cancelled final outcomes, `2` bad usage.
