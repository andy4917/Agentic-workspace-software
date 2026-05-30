# Codex P0 Integrity Closed Loop

Generated UTC: 2026-05-30T20:08:35.1956192Z

## Root-Cause Gate

- Observed symptom: Prior P0 reports and live manifests can be mistaken for current proof while runtime PID, watcher state, and validation output may have changed.
- Source trace: Current validation emits fresh JSON but the existing scaffold-validation, validation-log, and clean-baseline manifests are not refreshed unless a separate manual step does it.
- Strongest supported root cause: The P0 remediation existed as evidence packets and individual commands, not as one repeatable closure loop that rechecks original failure modes and refreshes manifests only from fresh evidence.
- Exact change location: maintenance/scripts/codex-p0-integrity-loop.ps1 plus generated manifests and report output.
- Fix goal: Run one bounded command that gathers current diff, runtime, toolchain, doctor, Scoop, and original regression evidence, then writes fresh reviewable manifests and a report.
- Minimal change scope: Add an orchestrating script and generated evidence artifacts; do not alter passing cleanup or validator logic.
- Original failure mode to verify: stale manifests, missing watcher, orphan or duplicate managed roots, reserved PID loop regression, stale command route, false pass, and dead app-server cleanup safety.
- Uncertainty: Computer Use may passively inspect Windows app inventory, but Codex Desktop UI input automation is forbidden by the Computer Use safety rules.
- Stop condition: Any failed check leaves overall_status=fail and avoids writing a clean baseline manifest.

## Policy Inputs

| Document | Managed Path | SHA256 | Present |
|---|---|---|---|
| Mandatory Root-Cause-First Modification | C:\Users\anise\Documents\Codex\maintenance\policies\root-cause-first-modification.md | B5D03557AEC56D8F5B04B9917938AFA2A4239E6EC76162F10F1DDB646895CF56 | True |
| Sandcastle Integration Policy | C:\Users\anise\Documents\Codex\maintenance\policies\sandcastle-integration-policy.md | 54BE6CBFED17D1E79BCD249D88BF06E537CE0B5904E378E003E7106E150F336F | True |
| Codex Self-Maintenance Control Plan | C:\Users\anise\Documents\Codex\maintenance\policies\codex-self-maintenance-control-plan.md | 3821B6AA5EFE6C9EAA76BCA2E4602F83ECC8D0656211343836D6C5ED37B4E251 | True |
| Latest feature reflection points | C:\Users\anise\Documents\Codex\maintenance\policies\latest-feature-reflection-points.md | 764E6FD525B4ECAB63CABC521A08E452C0BAE2C482AFEA28AB4FC7F738821A71 | True |

## Evidence Ledger

| Check | Status |
|---|---|
| policy_inputs_present | pass |
| git_diff_closure | pass |
| runtime_cleanup_status | pass |
| reserved_pid_loop_regression | pass |
| dead_app_server_cleanup_regression | pass |
| scaffold_validation_current | pass |
| toolchain_sources_current | pass |
| codex_doctor_current | pass |
| scoop_health_current | pass |
| manifest_staleness_detected_before_refresh | pass |

## Current Runtime

- App-server PID: 32184
- Watcher PIDs: 18216
- Managed orphan count: 0
- Duplicate keys: none

## Closure

- Overall status: pass
- Manifest stale before refresh: True
- Stale reasons before refresh: managed_roots_changed, managed_loop_script_hash_changed, live_loop_script_hash_changed, runtime_signature_changed, validation_summary_changed, policy_inputs_changed
- Report-only mode: False
- Clean tree required for baseline: True
- Computer Use boundary: passive app inventory only; Codex Desktop UI automation is forbidden by the Computer Use safety rules.
- Sandcastle boundary: not used for this active-runtime slice.

## Artifacts

- Loop latest manifest: C:\Users\anise\.codex\maintenance\manifests\p0-integrity-loop.latest.json
- Loop ledger: C:\Users\anise\.codex\maintenance\manifests\p0-integrity-loop-log.jsonl
- Scaffold validation manifest: C:\Users\anise\.codex\maintenance\manifests\scaffold-validation.latest.json
- Clean baseline manifest: C:\Users\anise\.codex\maintenance\manifests\clean-baseline-manifest.json

## Not Run

- Physical Codex Desktop close-button click was not automated because the Computer Use policy forbids automating the Codex desktop app UI or Codex CLI.
- ReportOnly cleanup-all regression skip: False
