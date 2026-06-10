# Workstation Layering

This document records the response to the 2026-05-17 external evaluation that
flagged the Codex workstation as valuable for a single operator but too dense
for general development, onboarding, security isolation, and reproducibility.

It is managed source. It does not activate hooks, change runtime config, or
grant completion authority by itself.

## Layers

Use the smallest layer that proves the current task.

| Layer | Purpose | Command |
| --- | --- | --- |
| `repo` | CI-capable tracked managed-source checks that do not require ignored private runtime state such as `config.toml`. | `python maintenance/scripts/codex_agent_harness.py repo-verify` |
| `scaffold` | Live `.codex` scaffold checks: config reconciliation, MCP baseline, hooks, skills, shims, managed/live sync, and retired runtime absence. | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.codex\maintenance\scripts\validate-codex-scaffold.ps1 -Json` |
| `p0` | Control-plane closure: current diff, runtime cleanup state, validator output, toolchain, doctor, Scoop health, and stale-manifest detection. | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.codex\maintenance\scripts\codex-p0-integrity-loop.ps1 -Json -ProcessTimeoutSeconds 120` |
| `compat` | Compatibility wrapper for the current control-plane stack. It runs repo verification plus live scaffold/P0/CLI checks and writes `reports/verification.latest.md`. | `python maintenance/scripts/codex_agent_harness.py verify` |

`no-mistakes` is not a replacement for these local layers. It is the adopted
outer repository validation gate for handoff work that needs non-self-certified
evidence, such as test/TDD changes, safe push, PR, CI, release, or merge
handoff. Run it through
`%USERPROFILE%\.codex\toolchains\shims\no-mistakes.cmd` after the relevant
local layer is coherent, but do not invoke it from inside a
no-mistakes-spawned gate worktree or agent step.

## Simple Mode

For tiny or ordinary project work, prefer the `repo` layer unless the task
touches MCP baseline, hooks, toolchains, browser/native host state, Goal
governance, Worker-Watcher, or release handoff. When release or repository
handoff is in scope, apply the `no-mistakes` outer gate after the smallest
local layer that proves basic correctness.

Simple mode is not a bypass. It still requires direct checks, not-run reasons,
secret-safe handling, and truthful residual-risk reporting. It avoids treating
optional runtime substrates as blockers for unrelated managed-source work.

## Compatibility Contract

- `repo-verify` is allowed to run in CI or clean checkouts where ignored files
  such as `config.toml`, SQLite state, logs, browser state, Memento state, and
  credentials are absent.
- `verify` is a compatibility command for the active stack, not the old
  install-state/full-doctor audit path.
- Context7 is absent from the active MCP baseline, and Memento and Serena are
  retired. No layer should require Context7, Memento/PostgreSQL, or Serena
  runtime health as normal success evidence.
- Passing `repo` checks is evidence only; it does not prove live MCP tool
  injection, browser state, local secrets, or long-running runtime health.

## External-Evaluation Mapping

- Hook and workflow density: simple mode gives PMs a lower-cost path for work
  that does not touch control-plane surfaces.
- Retired-runtime coupling: scaffold/P0 checks prove Context7 is absent and
  Memento and Serena are absent or disabled instead of treating their runtime
  health as a blocker.
- Reproducibility: `repo-verify` and the GitHub Actions workflow provide a
  public-safe CI path for tracked source quality.
- Policy drift: this document is the layer source of truth; references in
  README and maintenance docs should point here instead of duplicating the full
  contract.
- Security posture: repo/core checks do not claim sandbox isolation. Secret
  and destructive boundaries remain governed by existing scanners and hooks.

## Verification

Run these after layer or verification changes:

```powershell
python maintenance/scripts/codex_agent_harness.py repo-verify
python maintenance/scripts/codex_agent_harness.py eval --eval-id doctor-tier-smoke
python maintenance/scripts/codex_agent_harness.py eval --eval-id repo-verify
python maintenance/scripts/codex_agent_harness.py verify
```
