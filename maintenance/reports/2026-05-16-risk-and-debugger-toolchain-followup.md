# Risk And Debugger Toolchain Follow-Up

Date: 2026-05-16 KST
Scope: Codex GlobalSSOT workflow/hook/toolchain maintenance under
`%USERPROFILE%\.codex`.

## Objective

Close the residual risks from the turn-based anomaly calibration pass and make
task-level escalation plus debugger-toolchain status explicit enough for future
agents to verify from direct evidence.

## Changes

- Narrowed explicit subagent authorization so `PM-led`, `team preset`,
  `workflow`, or `review` alone do not require `SUBAGENT_CALL` evidence.
- Kept true authorization phrases such as `subagent`, `spawn_agent`,
  `multi-agent`, `parallel agent`, `role separation`, `delegate`,
  `delegation`, and `delegated`.
- Made Stop require final `SUBAGENT_CALL used/not_used` evidence when either
  explicit authorization exists or a subagent tool event was observed.
- Strengthened `SUBAGENT_CALL` readiness to require reason, direct evidence or
  substitute check, and residual risk.
- Added detailed L1-L4 escalation criteria to `AGENTS.md` and
  `hooks/lightweight-codex-policy.json`.
- Added debugger-toolchain status rules to `maintenance/AGENT_TOOL_REQUIREMENTS.md`
  and `toolchains/README.md`.
- Added debugger smoke checks to `maintenance/scripts/check-toolchain-sources.ps1`.
- Added hook smoke coverage for PM-led/team-preset false positives and actual
  subagent tool events.
- Recorded a reusable incident pattern for debugger-toolchain ambiguity.

## Debugger Toolchain Status

- `gdb`: active. Evidence: `gdb.cmd --version` returned `GNU gdb (GDB) 17.1`.
- `cdb`: active. Evidence: `cdb.cmd -version` returned
  `cdb version 10.0.26100.7705`.
- `python pdb`: active built-in. Evidence: managed Python shim returned
  `pdb available 3.14.5`.
- `debugpy`: optional and not installed in the managed Python shim. Evidence:
  `debugpy=not_installed`.
- `rust-gdb` and `rust-lldb`: wrapper targets exist, but are conditional and
  not active for the current `stable-x86_64-pc-windows-msvc` Rust toolchain.
  Evidence: Rustup reports each debugger binary is `not applicable` to the
  active MSVC Rust toolchain.

## Verification

- PowerShell parser checks passed for `hooks/lightweight-codex-hook.ps1` and
  `maintenance/scripts/check-toolchain-sources.ps1`.
- JSON parse passed for `hooks/lightweight-codex-policy.json` and
  `evals/hook-policy-smoke.json`.
- Python compile passed for
  `maintenance/scripts/codex_agent_harness_workflows.py`.
- `codex_agent_harness.py eval --eval-id hook-policy-smoke` passed.
- `check-toolchain-sources.ps1 -Json` passed with debugger checks recorded as
  active, active built-in, optional-not-installed, or conditional-not-active.
- Harness workflow file line count is 994, below the current 1000-line limit.

## Remaining Risk

- A Stop hook still cannot reconstruct explicit subagent authorization if both
  prior hook state and observed subagent tool events are unavailable. The
  durable fallback remains the final-evidence rule in `AGENTS.md`.
- `debugpy` was not installed because this pass was a verification and
  documentation correction, not a project-specific Python debugger install.
