# External Evaluation Hardening - 2026-05-17

## Scope

This pass responds to `C:\Users\anise\Downloads\external_evaluation_conclusion_en.md`.
It improves tracked managed source only. It does not read secrets, mutate
`config.toml`, change live MCP registrations, change hooks, inspect raw SQLite
or browser state, or publish external runtime data.

## Accepted Criticisms And Corrections

| External criticism | Correction | Evidence |
| --- | --- | --- |
| The system is strong for one workstation but too dense for ordinary work. | Added explicit verification layers and simple-mode guidance so PMs can choose `repo`, `core`, `extended`, `stress`, or `full` instead of always escalating to runtime-heavy verification. | `maintenance/WORKSTATION_LAYERING.md`, `README.md`, `maintenance/WORKSTATION_MAINTENANCE.md`, `maintenance/AGENT_TOOL_REQUIREMENTS.md` |
| Memento/PostgreSQL was coupled to core workstation health. | Added `doctor --tier core` without `memento_runtime` and `doctor --tier stress` with `memento_runtime`; default `doctor --json` remains full/backward-compatible. | `maintenance/scripts/codex_agent_harness.py`, `codex_agent_harness_base.py`, `codex_agent_harness_lifecycle.py`, `evals/doctor-tier-smoke.json` |
| Repository quality was not independently reproducible from ignored live state. | Added `repo-verify`, a tracked-source verification path that avoids ignored `config.toml`, credentials, SQLite, logs, browser state, Memento state, and MCP injection. | `maintenance/scripts/codex_agent_harness_workflows.py`, `maintenance/scripts/codex-repo-verify.ps1`, `evals/repo-verify.json`, `.github/workflows/repo-verify.yml` |
| CI-capable validation was missing. | Added a Windows GitHub Actions workflow that runs repository-only verification. | `.github/workflows/repo-verify.yml` |
| Policy drift risk existed across README, runbooks, MCP status, tool requirements, hooks, and harness. | Added `WORKSTATION_LAYERING.md` as the layering SSOT and changed nearby docs to point to it rather than duplicate detailed rules. | `maintenance/WORKSTATION_LAYERING.md` plus references in README and maintenance docs |
| Security posture could look stronger than it is because checks are detection-centered, not isolation-centered. | Layering docs explicitly say lower layers do not prove sandbox isolation, live MCP injection, browser state, local secrets, or long-running runtime health. | `maintenance/WORKSTATION_LAYERING.md`, `maintenance/AGENT_TOOL_REQUIREMENTS.md` |

## Intentional Non-Goals

- No hook behavior was weakened. The external critique recommended reducing hook
  responsibilities, but changing live Stop/Pre/Post hook enforcement is a
  higher-risk active-runtime change and was not necessary to create a lower-cost
  verification path.
- No Memento runtime behavior was changed. The improvement separates Memento
  from core doctor, while preserving full/stress verification for runtime work.
- No secret, credential, raw SQLite/log, browser session, or ignored `config.toml`
  content was inspected.
- Existing untracked skills under `skills/roast-feedback-to-goal-hardening/` and
  `skills/technical-system-roast-review/` were present before this pass and were
  not adopted into this change.

## Verification

Required checks:

```powershell
python maintenance/scripts/codex_agent_harness.py repo-verify
python maintenance/scripts/codex_agent_harness.py eval --eval-id repo-verify
python maintenance/scripts/codex_agent_harness.py eval --eval-id doctor-tier-smoke
powershell.exe -NoProfile -ExecutionPolicy Bypass -File maintenance/scripts/memento-mcp-runtime.ps1 verify
python maintenance/scripts/codex_agent_harness.py verify
python maintenance/scripts/codex_agent_harness.py audit --json
```

Pass criteria:

- `repo-verify` passes without calling `doctor --tier core` or requiring ignored
  live runtime state.
- `doctor-tier-smoke` proves `core` excludes `memento_runtime` and `stress` plus
  `full` include it.
- `verify` remains backward-compatible and passes the full local runtime-heavy
  check.
- `audit --json` reports `status=pass` and `score=100.0`.

## Anomaly Calibration

- A mutable `reports/verification.latest.*` run briefly showed `verify=fail`
  because the runtime-heavy Memento check timed out. The same Memento proof was
  rerun directly and returned `status=pass`, then full `verify` and
  `audit --json` were rerun successfully.
- The worktree also contains unrelated `skills/clean-all-slop/` edits and
  untracked skill directories that are not part of this pass. Commit staging
  must use an explicit allowlist, not `git add .`.

## Residual Risks

- `repo-verify` is intentionally narrower than full workstation verification.
  It does not prove live MCP injection, Memento health, browser/native host
  state, local secrets, or long-running runtime behavior.
- Hook simplification remains a separate active-runtime design task if the user
  later asks to reduce Stop/Pre/Post hook responsibilities directly.
- The current Git worktree also contains pre-existing untracked skill folders
  outside this pass.

## Rollback

Revert the files changed by this pass. The change does not mutate runtime state,
so rollback is a normal Git revert of managed source.
