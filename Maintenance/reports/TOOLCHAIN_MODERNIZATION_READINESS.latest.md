# Toolchain Modernization Readiness

## Summary
PARTIAL

The repository is ready for a modernization plan, but not ready for a production switch. The current command surface is PowerShell-heavy, scattered, and lacks a root `justfile`, Python package boundary, `pyproject.toml`, and `uv.lock`. This is exactly the kind of repo where `just + uv + library-style harness modules` would reduce missed checks, but the migration must run in shadow/parallel mode until the PM evidence chain is fixed.

## just Readiness
- Root `justfile` / `Justfile`: not present.
- Current executable entrypoints:
  - `Maintenance/harness-v2/Invoke-HarnessV2Acceptance.ps1`
  - `Maintenance/Test-PmOrchestrationRuntimeEvidence.ps1`
  - `Maintenance/Test-CodexConfigAuthority.ps1`
  - `Maintenance/Test-EventLedgerIntegrity.ps1`
  - `Maintenance/Test-SubagentInspectionRouting.ps1`
  - `Maintenance/Test-RepoGateAdoption.ps1`
  - `Maintenance/Test-CodexHookUiSurface.ps1`
  - `Maintenance/Test-HeuristicFalsePositiveReview.ps1`
  - `Maintenance/patch-bench/scripts/*.ps1`
- Readiness: PARTIAL. The commands are identifiable, but not consolidated.
- External basis: the just manual describes `just` as a command runner that saves project-specific commands in a `justfile`, making it a good fit for this repo's standard audit recipes.

## uv / pyproject / uv.lock Readiness
```yaml
python_toolchain_status:
  pyproject_exists: false
  uv_lock_exists: false
  requirements_txt_exists: false
  ad_hoc_pip_usage_found: true
  package_import_structure_ready: false
  recommended_next_step: create Tools/harness_py/pyproject.toml and uv.lock in shadow mode
```

Findings:
- No repo-local `pyproject.toml` or `uv.lock` exists for harness tooling.
- No first-party Python package structure exists under `Tools/harness_py`.
- `pip install` strings exist inside hook policy detection code and upstream/sample material. They are not active first-party dependency management, but the vocabulary should be separated from production toolchain instructions.
- Official uv docs define `uv.lock` as the project lockfile next to `pyproject.toml`, and `uv run` / `uv sync` keep the environment aligned with the lockfile.
- Python Packaging docs define `pyproject.toml` as the configuration file for packaging-related tools and project metadata.

## Python Library Boundary
Recommended first package boundary:
```text
Tools/harness_py/
  pyproject.toml
  uv.lock
  src/harness_py/
    audit/current_state.py
    audit/subagents.py
    audit/config_vocabulary.py
    audit/ledgers.py
    reports/current_state.py
    schema/runtime_state.py
    routes/required_routes.py
    receipts/gate.py
```

Move to Python first:
- JSON/YAML/TOML parsing and schema comparison
- Runtime ledger aggregation
- Markdown report generation
- Config vocabulary diff
- Acceptance result normalization
- Stale candidate receipt detection

Keep in PowerShell for now:
- Codex hook entrypoint
- Hook stdin/stdout protocol
- Immediate PreToolUse / Stop enforcement
- Minimal compatibility runner

## PowerShell Bottleneck / Rust Candidate Boundary
`Settings/Dev_Codex_HOOKS/codex-ssot-hook.ps1` is 8,047 lines and 361,664 bytes. That is beyond a comfortable single hook script boundary.

Rust helper candidates:
- path normalization and prefix containment
- canonical event envelope validation
- JSONL append/read canonicalization
- dedupe key generation
- Stop predicate calculation
- receipt freshness/hash validation
- large ledger scans

Do not rewrite the whole hook in Rust. Use a thin PowerShell wrapper plus `Tools/harness-core` only after Python report/audit extraction proves stable.

## Proposed justfile Recipes
```just
default:
    just --list

audit-current:
    powershell -NoProfile -ExecutionPolicy Bypass -File Maintenance/Test-CurrentStateAudit.ps1

harness-acceptance:
    powershell -NoProfile -ExecutionPolicy Bypass -File Maintenance/harness-v2/Invoke-HarnessV2Acceptance.ps1

pm-orchestration-audit:
    powershell -NoProfile -ExecutionPolicy Bypass -File Maintenance/Test-PmOrchestrationRuntimeEvidence.ps1

config-audit:
    powershell -NoProfile -ExecutionPolicy Bypass -File Maintenance/Test-CodexConfigAuthority.ps1

ledger-audit:
    powershell -NoProfile -ExecutionPolicy Bypass -File Maintenance/Test-EventLedgerIntegrity.ps1

subagent-audit:
    uv run python -m harness_py.audit.subagents

report-current:
    uv run python -m harness_py.reports.current_state

py-sync:
    uv sync --locked

rust-bench:
    cargo bench --manifest-path Tools/harness-core/Cargo.toml
```

## Existing Runner Mapping
| Current runner | Proposed recipe | Modernization phase |
|---|---|---|
| `Maintenance/harness-v2/Invoke-HarnessV2Acceptance.ps1` | `just harness-acceptance` | P1 |
| `Maintenance/Test-PmOrchestrationRuntimeEvidence.ps1` | `just pm-orchestration-audit` | P1 |
| `Maintenance/Test-CodexConfigAuthority.ps1` | `just config-audit` | P1 |
| `Maintenance/Test-EventLedgerIntegrity.ps1` | `just ledger-audit` | P1 |
| ad-hoc ledger parsing | `just subagent-audit` | P1/P2 |
| ad-hoc report writing | `just report-current` | P1/P2 |

## Risks
- Moving enforcement logic before fixing runtime evidence would hide the actual failure behind a new toolchain.
- `final_acceptance_result.json` can become stale relative to command output.
- Alias fields such as `model_primary = latest-main` remain for compatibility; consumers must read `resolved_model` for actual model policy.
- Public docs and local app/package vocabulary still contain `features.codex_hooks`, while local authority uses `features.hooks`.

## Recommendation
Proceed with a shadow-only modernization plan:
1. Add `justfile` as a command facade without changing hook behavior.
2. Add `Tools/harness_py` with `uv` as read-only audit/report library.
3. Generate reports from Python and compare against current PowerShell outputs.
4. Only after evidence parity, consider extracting hot ledger validation to Rust.

References: [just manual](https://just.systems/man/en/), [uv project structure](https://docs.astral.sh/uv/concepts/projects/layout/), [uv locking and syncing](https://docs.astral.sh/uv/concepts/projects/sync/), [Python pyproject guide](https://packaging.python.org/guides/writing-pyproject-toml/).
