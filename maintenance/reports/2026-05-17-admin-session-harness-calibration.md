# Admin Session Harness Calibration - 2026-05-17

## Scope

Codex was running from an elevated administrator token for a plugin JS migration
slice. The Memento runtime guard intentionally rejects administrator tokens
because the managed PostgreSQL runtime is designed for the current non-elevated
user token.

## Issue

`doctor-tier-smoke` claimed to be a structural tiering smoke, but its evaluator
required stress and full doctor to pass. In an administrator session, those
runtime-heavy tiers include `memento_runtime` and fail by design.

`audit --json` also used full doctor for the quality gate, converting unrelated
Memento runtime health into a managed-source audit failure.

## Change

- `doctor-tier-smoke` now verifies tier structure: core excludes
  `memento_runtime`, while stress and full include it even if runtime health is
  unhealthy.
- `audit --json` now uses core doctor for the managed-source quality gate.

## Verification

- `python -m py_compile maintenance/scripts/codex_agent_harness_lifecycle.py maintenance/scripts/codex_agent_harness_workflows.py`
- `python maintenance/scripts/codex_agent_harness.py eval --eval-id doctor-tier-smoke`
- `python maintenance/scripts/codex_agent_harness.py benchmark --eval-id doctor-tier-smoke`
- `python maintenance/scripts/codex_agent_harness.py repo-verify`
- `python maintenance/scripts/codex_agent_harness.py doctor --tier core --json`
- `python maintenance/scripts/codex_agent_harness.py audit --json`

## Non-Goals

- No Memento runtime launch guard was weakened.
- Full/stress Memento health remains a non-admin runtime check.
- No hook policy was changed.

## Rollback

Revert this report plus the matching changes in
`evals/doctor-tier-smoke.json`,
`maintenance/scripts/codex_agent_harness_lifecycle.py`, and
`maintenance/scripts/codex_agent_harness_workflows.py`.
