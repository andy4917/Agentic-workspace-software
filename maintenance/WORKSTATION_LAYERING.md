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
| `core` | Local managed-source health: config parse, harness files, generated-output tracking, hook routing, managed files, file size, stale references, and sentinels. | `python maintenance/scripts/codex_agent_harness.py doctor --tier core --json` |
| `extended` | Core plus agent/workflow ergonomics and active app runtime writability. | `python maintenance/scripts/codex_agent_harness.py doctor --tier extended --json` |
| `stress` | Runtime-heavy checks such as Memento/PostgreSQL health, memory ceiling, and recent log risk patterns. | `python maintenance/scripts/codex_agent_harness.py doctor --tier stress --json` |
| `full` | Backward-compatible complete local verification tier. | `python maintenance/scripts/codex_agent_harness.py doctor --json` |

## Simple Mode

For tiny or ordinary project work, prefer the `repo` or `core` layer unless the
task touches MCP, Memento, hooks, toolchains, browser/native host state, Goal
governance, Worker-Watcher, or release handoff.

Simple mode is not a bypass. It still requires direct checks, not-run reasons,
secret-safe handling, and truthful residual-risk reporting. It avoids treating
optional runtime substrates as blockers for unrelated managed-source work.

## Compatibility Contract

- Existing `doctor --json` and `verify` behavior remains `full` and continues
  to check Memento runtime health.
- `repo-verify` is allowed to run in CI or clean checkouts where ignored files
  such as `config.toml`, SQLite state, logs, browser state, Memento state, and
  credentials are absent.
- `doctor --tier core` must not call Memento or PostgreSQL.
- `doctor --tier stress` must include Memento runtime checks when Memento is
  declared locally.
- Passing `repo` or `core` checks is evidence only; it does not prove live MCP
  tool injection, browser state, local secrets, or long-running runtime health.

## External-Evaluation Mapping

- Hook and workflow density: simple mode gives PMs a lower-cost path for work
  that does not touch control-plane surfaces.
- Memento coupling: doctor tiers prevent Memento/PostgreSQL health from being a
  core managed-source blocker.
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
