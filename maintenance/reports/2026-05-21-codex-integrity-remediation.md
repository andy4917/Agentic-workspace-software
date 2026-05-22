# Codex Integrity Remediation - 2026-05-21

## Scope

- User request: fix the failed integrity checks and resolve residual risks from the `.codex` folder tree, app settings, cache, MCP, config, and AGENTS audit.
- Surfaces changed: toolchain shim, harness status logic, toolchain source check, incident manual, active cache/import residue.
- Secrets policy: `auth.json` content was not read.

## Root Causes

1. Vendor/tool discovery residue reappeared under active `.codex` paths:
   - `vendor_imports`
   - `.tmp/bundled-marketplaces`
   - `.tmp/plugins`
   - `.tmp/plugins.sha`
2. `toolchains/shims/codex.cmd` preferred the Scoop Codex CLI before the installed Store app resource, causing `codex-cli 0.132.0` to shadow the official app resource `codex-cli 0.131.0`.
3. `workspace_script_file_size` treated upstream `.system` skill scripts as locally owned workspace scripts. The visible failure was `skills/.system/imagegen/scripts/image_gen.py` at 995 lines, even though the imagegen skill contract says not to edit that fallback CLI directly.
4. `check-toolchain-sources.ps1` reported the `codex.cmd` fallback path as if it were the effective source, which made successful official-wrapper alignment easy to misread.

## Changes

- Quarantined active residue to:
  - `C:\Users\anise\.codex-archives\2026-05-21-integrity-remediation-20260521-212455`
- Updated `toolchains/shims/codex.cmd` to prefer the installed OpenAI.Codex Store app resource before fallback paths.
- Updated `maintenance/scripts/codex_agent_harness_status.py` to classify oversized upstream `.system` skill material as `ignored_upstream_system_skill` instead of failing local workspace script size.
- Added a harness self-test case proving that upstream `.system` oversized scripts are exempt while local oversized skill scripts still fail.
- Updated `maintenance/scripts/check-toolchain-sources.ps1` to report `official-app-wrapper:codex` against the Store app resource and avoid presenting the Scoop fallback as the effective Codex source.
- Added an incident-manual pattern for vendor import residue recreated by tool or skill discovery.

## Verification

- `maintenance/scripts/check-codex-native-alignment.ps1 -Json`: pass.
- `maintenance/scripts/check-naming-conventions.ps1 -Json`: pass, `finding_count=0`.
- `maintenance/scripts/codex-harness-doctor.ps1`: pass, including `workspace_script_file_size`, `removed_blocker_paths`, and `naming_convention`.
- `toolchains/shims/codex.cmd --version`: `codex-cli 0.131.0`.
- `python -m py_compile maintenance/scripts/codex_agent_harness_status.py maintenance/scripts/codex_agent_harness_merge.py`: pass.
- Direct ownership-boundary test for `workspace_script_line_count_status`: pass.
- `python maintenance/scripts/codex_agent_harness.py --root C:\Users\anise\.codex self-test`: pass.
- `maintenance/scripts/check-toolchain-sources.ps1 -Json`: pass; `official-app-wrapper:codex` reports wrapper and Store app output as `codex-cli 0.131.0`.
- `toolchains/shims/codex.cmd mcp list`: pass; Memento and OpenAI developer docs remain enabled, chrome_devtools_observe and shadcn remain disabled.
- `maintenance/scripts/memento-mcp-runtime.ps1 verify`: pass.
- `maintenance/scripts/memento-security-contract-check.ps1`: pass.

## Residual Risks

- The residue was quarantined, not deleted. A future tool discovery run may recreate it; the durable prevention point is the discovery/cache owner, not this cleanup.
- `check-toolchain-sources.ps1` still reports many local-chain wrappers by design. This is inventory, not a problem, as long as official-bundle wrappers remain preferred for Codex-owned tools.
- `skills/.system/imagegen/scripts/image_gen.py` remains 995 lines. The harness now treats it as upstream system skill material rather than local cleanup debt; local oversized skill scripts remain enforced.
