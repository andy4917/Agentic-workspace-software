# Codex State Management

This document defines how this workstation treats Codex caches, logs, memory,
folders, files, and managed-source to live-runtime synchronization. It is
managed-source policy, not a secret store and not completion authority.

## Roots

- `C:\Users\anise\.codex` is the live runtime root and `CODEX_HOME`.
- `C:\Users\anise\Documents\Codex` is the reviewable managed-source repository.
- Live runtime state is proven from current config, manifests, process state,
  and validation output. Old managed-source file dates are evidence to classify,
  not proof of active runtime behavior.
- Runtime state is not copied wholesale into managed source. Only public-safe
  scripts, docs, reports, and sanitized evidence belong in this repository.

## Cache Management

Current cache classes:

- `runtime-cache`: generated state used by Codex Desktop or plugins, including
  `.codex\cache`, `.codex\plugins\cache`, `.codex\.tmp`, `.codex\tmp`,
  `.codex\node_repl`, browser/plugin runtime folders, and app-created package
  state.
- `external-package-cache`: package-manager caches outside `CODEX_HOME`, such as
  npm, uv, pip, pnpm, Scoop, Cargo, Rustup, and VS Code CLI caches.
- `retired-residue`: deprecated, disabled, archived, or backup surfaces that are
  not active runtime truth.

Handling rules:

- Do not treat runtime cache as a configured source of truth.
- Do not sentinel-block `.tmp`, `tmp`, or `plugins\cache`; Codex and plugins may
  create these while running.
- Audit runtime caches by size, active reference, process linkage, and
  category. Remove only when a live process is not using the path.
- Clean package-manager caches through their owning package manager or an
  explicit maintenance script, not by ad hoc recursive deletion.
- Do not create persistent archive or backup roots for retired residue. When
  removal is explicitly authorized, verify the path boundary and delete the
  residue directly. Recursive cleanup must fail closed for top-level or
  descendant reparse points, junctions, symlinks, or descendant scan failures.
  If ownership is uncertain, stop at classification instead of preserving
  another fallback copy.

## Log Management

Current log classes:

- SQLite operational state: `logs_*.sqlite`, `state_*.sqlite`, `goals_*.sqlite`,
  `memories_*.sqlite`, plus their WAL/SHM files.
- Hook or maintenance ledgers under `.codex\state` and
  `.codex\maintenance\manifests`.
- Human-readable current reports under ignored `reports\*.latest.*` outputs.
- Raw app logs, when present, remain local runtime state.

Handling rules:

- Logs are evidence candidates, not completion authority.
- Keep hook and workflow logs small, local, structured, and non-authoritative.
- Do not store raw secrets, full prompts, or full tool payloads by default.
- Never delete SQLite WAL/SHM files directly. Use app shutdown, checkpoint, or
  owning maintenance commands.
- Before removing old raw logs, create a manifest or structured summary when
  needed for audit, then delete only after path-boundary verification. Do not
  create new retained archives as cleanup output.

## Memory Management

Current memory classes:

- Retired Memento state, if present, is historical runtime state and not an
  active PM memory substrate.
- SQLite memory state such as `memories_*.sqlite`.
- Runtime memory folders such as `.codex\memories`, when created by the app.
- Legacy raw Memory/RAG files are not an active fallback.

Handling rules:

- Use `maintenance\MEMORY_BOUNDARY_POLICY.md` as the canonical classification
  rule when memory-like information appears in a task.
- Classify memory-like information as `global-settings` or `project-scope`
  before relying on it. Do not store, interpret, or report one item as both.
- If scope is unclear, keep the information as temporary turn context only and
  do not persist it as memory.
- Memory artifacts are support-only historical evidence unless a current user
  instruction explicitly reopens a memory system. User instructions, scoped
  `AGENTS.md`, current files, tests, runtime output, and PM verification outrank
  recalled memory.
- Do not write memory as part of the default workstation workflow.
- Never write secrets, raw credentials, raw logs, full prompts, or speculative
  guesses as verified memory.
- Do not restore old raw memory folders as active state. Use direct files/tests
  instead.

## Folder And File Management

Active file classes:

- `config.toml`: live runtime configuration truth.
- `config.d`: managed source material that must be reconciled into
  `config.toml`; it is not active by itself.
- `maintenance\scripts`: public-safe maintenance scripts.
- `maintenance\manifests`: generated live evidence under `CODEX_HOME`.
- `reports\*.latest.*`: current local evidence packets; rerun the responsible
  command before treating them as validation.
- `skills`, `toolchains\shims`, `hooks`: active control-plane surfaces governed
  by config and validation.
- `skills-disabled`, `archive`, `archived_*`, compressed backups, and retired
  snapshots: contamination candidates unless a current config, process, or
  user instruction proves active use.

Handling rules:

- Classify every old-looking or unexpected root before trusting or removing it.
- Active files must be visible to audit unless they are secrets, sessions, logs,
  SQLite state, browser state, or live app cache.
- Do not hot-restore old sessions, logs, SQLite state, WAL/SHM files, browser
  profiles, stale hook output, generated shims, or volatile caches.

## Sync Model

The sync direction is intentional:

1. Edit and review public-safe policy/scripts in
   `C:\Users\anise\Documents\Codex`.
2. Copy only live-called public-safe files into `C:\Users\anise\.codex`.
3. Validate that live copies and managed-source copies match by SHA-256.
4. Run live runtime checks from `CODEX_HOME`.
5. Commit only managed-source files and sanitized reports.

Currently byte-synced live-copy files are the public-safe paths named by the
`managed_source_live_sync` check in
`maintenance\scripts\validate-codex-scaffold.ps1`. The set includes:

- `config.d\*.toml` fragments;
- `hooks\compact-codex-hook.ps1`;
- core maintenance docs and manifests such as
  `maintenance\AGENT_TOOL_REQUIREMENTS.md`,
  `maintenance\CODEX_STATE_MANAGEMENT.md`, and
  `maintenance\manifests\keep-set.json`;
- public-safe maintenance scripts used by the scaffold, harness, P0 loop,
  browser/MCP toggles, and runtime cleanup;
- `toolchains\README.md` and PowerShell-native shim entry points such as
  `toolchains\shims\codex.ps1`, `toolchains\shims\git.ps1`,
  `toolchains\shims\no-mistakes.ps1`, and `toolchains\shims\pwsh.ps1`;
- active live-called skills such as `skills\frontend-visual-debug\SKILL.md`,
  `skills\git-easy-korean\SKILL.md`, and
  `skills\test-integrity-gate\SKILL.md`.

`C:\Users\anise\.codex\AGENTS.md` is a compact live bootstrap. It is not byte
identical to the managed-source `AGENTS.md` by design.

## Codex Self-Inspection Loop

Codex checks its own environment through these layers:

1. `validate-codex-scaffold.ps1`
   - verifies config fragments, MCP set, command sources, retired MCP runtime absence,
     hooks, skills, shims, no-mistakes gate readiness, PATH hygiene, secret
     scan, runtime process state, live-runtime state classification, and
     managed-source/live-copy sync.
2. `codex-runtime-process-cleanup.ps1`
   - reports app-server, watcher, managed roots, orphan processes, duplicate
     roots, and close-lifecycle cleanup readiness.
3. `codex-home-maintenance.ps1`
   - inventories active references, native hosts, sentinel blockers,
     toolchain/cache roots, transient roots, approved report roots, and
     direct-delete cleanup outcomes including reparse-point refusal results.
4. `check-toolchain-sources.ps1`
   - verifies official-bundle and local-chain command resolution.
5. Codex CLI doctor through `toolchains\shims\codex.ps1` or the bundled
   `codex.exe`
   - checks Codex app/runtime, auth mode metadata, config, network, state DBs,
     thread inventory, and installation consistency.
6. `codex-p0-integrity-loop.ps1`
   - combines current diff, runtime cleanup status, validator output,
     toolchain checks, doctor output, Scoop health, manifest staleness, and
     ledger integrity into a repeatable closure loop.

The self-inspection loop must report missing evidence, stale manifests,
uncategorized runtime roots, forbidden active roots, sync mismatches, tool
failures, and not-run checks as evidence gaps rather than success.

## Standard Commands

```powershell
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\anise\.codex\maintenance\scripts\validate-codex-scaffold.ps1 -CodexHome C:\Users\anise\.codex -Json
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\anise\.codex\maintenance\scripts\codex-runtime-process-cleanup.ps1 -Mode status -CodexHome C:\Users\anise\.codex
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\anise\.codex\maintenance\scripts\codex-home-maintenance.ps1 -Mode Report -CodexHome C:\Users\anise\.codex -ReportRoot C:\Users\anise\Documents\Codex\reports
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\anise\.codex\maintenance\scripts\codex-p0-integrity-loop.ps1 -Json -ProcessTimeoutSeconds 120
```

Use `-ReportOnly` only for read-only inspection or intentionally dirty review
passes. Do not pair P0 closure with `-SkipScoop`; the loop treats skipped Scoop
health as a failed evidence gap because Scoop health is part of current
control-plane closure.
