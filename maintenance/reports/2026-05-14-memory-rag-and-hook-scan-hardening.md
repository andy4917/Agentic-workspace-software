# Memory RAG And Hook Scan Hardening - 2026-05-14

## Superseded Status

This is a historical report only. It was superseded on 2026-05-15 by the
Windows-native Memento MCP runtime and support-only PM memory loop. Do not use
this document as active runtime guidance: `memsearch`, raw Markdown memories,
and `check-memory-rag-status.ps1` are retired legacy Memory/RAG surfaces, not
active fallback.

## Status

Implemented and verified.

## Problem

Two previous residual risks were not acceptable as recurring manual checks:

- Memory/RAG indexing was left as not-run even though the workstation needs a
  repeatable health check.
- A staged diff sensitive-pattern scan was blocked because the hook classified
  the search pattern as protected content access.

## Design

- Add `maintenance/scripts/check-memory-rag-status.ps1`.
  - Verifies `memories/` metadata and Git usability without printing raw memory
    contents.
  - Verifies the active `memsearch` CLI dependency through
    `toolchains/shims/memsearch.cmd`.
  - `memsearch` is a managed local shim. Default mode wraps
    `codex_agent_harness.py retrieve`; `--memory` mode searches
    `memories/raw_memories.md` with redacted previews.
  - It is no longer optional for Memory/RAG workstation verification.
- Add `maintenance/scripts/check-staged-sensitive-diff.ps1`.
  - Scans staged added lines for sensitive assignments.
  - Reports only file, category, and line digest.
  - Does not print raw matched lines.
- Update the lightweight hook so staged `git diff --cached` validation is not
  confused with direct protected-file reads.
- Add `hook-policy-smoke` synthetic eval coverage.
- Add both checks to the default harness `verify` command so this does not stay
  as a manual residual risk.

## Security Boundary

Direct protected-file reads remain blocked. The staged diff scanner is a
pre-commit validation tool and redacts matched content by design.

## Active Dependency Promotion

- Source class: managed local toolchain shim.
- Exact paths:
  - `toolchains/shims/memsearch.cmd`
  - `toolchains/shims/memsearch.ps1`
- Owning check: `maintenance/scripts/check-memory-rag-status.ps1`.
- Dependency chain:
  - `memsearch.cmd`
  - `memsearch.ps1`
  - `toolchains/shims/python.cmd`
  - default: `maintenance/scripts/codex_agent_harness.py retrieve`
  - memory mode: `memories/raw_memories.md`
- Active boundary: `memsearch` is required for Memory/RAG workstation
  verification. The shim does not make Memory/RAG authoritative; it only proves
  the support-only retrieval and memory search paths are callable.

## Verification

Checks run:

- PowerShell parser check for `hooks/lightweight-codex-hook.ps1`,
  `check-memory-rag-status.ps1`, `check-staged-sensitive-diff.ps1`, and
  `check-worktree-sensitive-diff.ps1`: pass.
- Python compile check for `codex_agent_harness_workflows.py`: pass.
- `check-memory-rag-status.ps1`: pass; memory metadata exists, memory Git
  status is usable, active `memsearch` retrieval and memory search selected
  context.
- `check-staged-sensitive-diff.ps1`: pass; zero findings.
- `codex_agent_harness.py eval --eval-id hook-policy-smoke`: pass.
  - Staged diff validation is allowed.
  - Direct protected-file reads remain blocked.
  - Mixed direct protected-file reads plus staged diff scans remain blocked.
  - The redacted staged scanner is allowed.
- Follow-up realistic-use simulation found that normal unstaged Codex edits can
  leave `check-staged-sensitive-diff.ps1` with `scanned_added_lines=0`; the
  harness now also runs `check-worktree-sensitive-diff.ps1`, which uses a
  temporary Git index to scan dirty worktree changes without mutating staging.
- `codex_agent_harness.py benchmark --eval-id hook-policy-smoke`: pass, used to
  refresh benchmark evidence after harness code changed.
- `codex_agent_harness.py verify`: pass.

The memory status check does not print raw memory contents. Its `memsearch
--memory` proof reads `memories/raw_memories.md` locally and emits only redacted
line references, headings, scores, and digests.

## Rollback

Revert:

- `hooks/lightweight-codex-hook.ps1`
- `hooks/lightweight-codex-policy.json`
- `maintenance/scripts/check-memory-rag-status.ps1`
- `toolchains/shims/memsearch.cmd`
- `toolchains/shims/memsearch.ps1`
- `maintenance/scripts/check-staged-sensitive-diff.ps1`
- `maintenance/scripts/check-worktree-sensitive-diff.ps1`
- `maintenance/scripts/codex_agent_harness_workflows.py`
- `evals/hook-policy-smoke.json`
- `maintenance/WORKSTATION_MAINTENANCE.md`
- `maintenance/PM_WORKSPACE_ALIGNED_DESIGN.md`
- this report
