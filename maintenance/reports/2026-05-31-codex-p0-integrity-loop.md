# Codex P0 Integrity Closed Loop

Generated UTC: 2026-05-31T10:47:07.7316285Z

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
| loop_ledger_integrity | pass |

## Checks Run Detail

| Check | Command | CWD | Timestamp UTC | Exit code | Result | Evidence |
|---|---|---|---|---|---|---|
| policy_inputs_present | Test-Path/Get-FileHash maintenance\policies\*.md | C:\Users\anise\Documents\Codex | 2026-05-31T10:47:07.7316285Z | 0 | pass | missing=0; inputs=4 |
| git_diff_closure | git status --short --branch; git status --porcelain; git diff --check | C:\Users\anise\Documents\Codex | 2026-05-31T10:47:07.8806325Z | 0 | pass | dirty_paths=0; diff_check_exit_code=0 |
| runtime_cleanup_status | C:\Users\anise\.codex\toolchains\shims\pwsh.cmd -NoProfile -ExecutionPolicy Bypass -File C:\Users\anise\.codex\maintenance\scripts\codex-runtime-process-cleanup.ps1 -Mode status -CodexHome C:\Users\anise\.codex | C:\Users\anise\Documents\Codex | 2026-05-31T10:47:08.0852074Z | 0 | pass | app_server_pid=14456; watchers=1; managed_orphans=0; duplicate_keys=0 |
| reserved_pid_loop_regression | Select-String -LiteralPath C:\Users\anise\.codex\maintenance\scripts\codex-runtime-process-cleanup.ps1 -Pattern 'foreach\s*\(\s*\$pid\b' | C:\Users\anise\Documents\Codex | 2026-05-31T10:47:09.5320137Z | 0 | pass | forbidden_hits=0 |
| dead_app_server_cleanup_regression | C:\Users\anise\.codex\toolchains\shims\pwsh.cmd -NoProfile -ExecutionPolicy Bypass -File C:\Users\anise\.codex\maintenance\scripts\codex-runtime-process-cleanup.ps1 -Mode cleanup-all -ParentPid 65000 -CodexHome C:\Users\anise\.codex; C:\Users\anise\.codex\tool... | C:\Users\anise\Documents\Codex | 2026-05-31T10:47:09.7124092Z | 0 | pass | dead_pid=65000; before_app_server_pid=14456; after_app_server_pid=14456; before_roots=3572,3856,25644,35028; after_roots=3572,3856,25644,35028 |
| scaffold_validation_current | C:\Users\anise\.codex\toolchains\shims\pwsh.cmd -NoProfile -ExecutionPolicy Bypass -File C:\Users\anise\.codex\maintenance\scripts\validate-codex-scaffold.ps1 -CodexHome C:\Users\anise\.codex -Json | C:\Users\anise\Documents\Codex | 2026-05-31T10:47:11.4894292Z | 0 | pass | overall_status=pass; fail_count=0; generated_utc=05/31/2026 10:47:15 |
| toolchain_sources_current | C:\Users\anise\.codex\toolchains\shims\pwsh.cmd -NoProfile -ExecutionPolicy Bypass -File C:\Users\anise\.codex\maintenance\scripts\check-toolchain-sources.ps1 -Json | C:\Users\anise\Documents\Codex | 2026-05-31T10:47:15.4356704Z | 0 | pass | status=pass; failures=0; warnings=0 |
| codex_doctor_current | cmd.exe /c C:\Users\anise\.codex\toolchains\shims\codex.cmd doctor --json | C:\Users\anise\Documents\Codex | 2026-05-31T10:47:18.4179618Z | 0 | pass | overallStatus=ok; codexVersion=0.135.0-alpha.1 |
| scoop_health_current | cmd.exe /c scoop status; cmd.exe /c scoop checkup | C:\Users\anise\Documents\Codex | 2026-05-31T10:47:23.1070874Z | 0 | pass | status_exit_code=0; checkup_exit_code=0; status=WARN  Scoop bucket(s) out of date. Run 'scoop update' to get the latest changes.; checkup=No problems identified! |
| manifest_staleness_detected_before_refresh | Compare clean-baseline-manifest.json against current runtime, script, validation, toolchain, doctor, policy, and git signatures | C:\Users\anise\Documents\Codex | 2026-05-31T10:47:28.7873345Z | 0 | pass | stale_before_refresh=True; stale_reasons=app_server_pid_changed,managed_root_signature_changed,runtime_signature_changed |
| loop_ledger_integrity | Parse C:\Users\anise\.codex\maintenance\manifests\p0-integrity-loop-log.jsonl and require generated_utc/status/codex_home/repo_root for each JSONL row | C:\Users\anise\Documents\Codex | 2026-05-31T10:47:28.8147206Z | 0 | pass | exists=True; valid=5; invalid=0; repair_allowed=True |

## Current Runtime

- App-server PID: 14456
- Watcher PIDs: 14024
- Managed orphan count: 0
- Duplicate keys: none

## Closure

- Overall status: pass
- Manifest stale before refresh: True
- Stale reasons before refresh: app_server_pid_changed, managed_root_signature_changed, runtime_signature_changed
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
