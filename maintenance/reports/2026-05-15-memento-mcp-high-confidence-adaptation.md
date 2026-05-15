# Memento MCP High-Confidence Adaptation

Date: 2026-05-15

## Scope

This pass adapts only the high-confidence patterns from the reviewed
oh-my-codex meta-design and Memento PM reinforcement packs into the existing
Codex PM workflow. It does not install oh-my-codex, replace the PM workflow,
add a runtime layer above Codex, weaken hooks, weaken AGENTS.md, or create broad
fallback behavior.

## Adopted Items

1. UserPromptSubmit meta-analysis
   - Strengthens: `lightweight-codex-hook.ps1` prompt reminders.
   - Objective improvement: every non-trivial prompt gets a compact workflow,
     toolchain, evidence, and memory-use frame before action.
   - Prevents: intent drift, skipped evidence sequencing, and hidden
     fallback-to-default behavior.
   - Maintenance cost: a few deterministic hook strings and classifier hints.
   - Lives in: hook and policy JSON.
   - Runtime proof: sample hook parse plus `UserPromptSubmit` sample output.

2. Task-type subagent routing
   - Strengthens: existing explicit-authorization subagent policy.
   - Objective improvement: keeps routing advisory and bounded without
     bypassing the runtime rule that subagents require explicit user
     authorization.
   - Prevents: unauthorized delegation and worker evidence being treated as PM
     completion authority.
   - Maintenance cost: no new runtime, no new agent catalog.
   - Lives in: AGENTS.md and hook reminders.
   - Runtime proof: prompt reminder states delegation authorization status.

3. Purpose-based toolchain selection
   - Strengthens: existing toolchain source policy.
   - Objective improvement: tool choice is tied to the task purpose before
     mutation, especially for MCP, workstation, docs, frontend, and Git work.
   - Prevents: bare-command drift, old shim reuse, and unsupported runtime
     claims.
   - Maintenance cost: small hook classifier plus durable status docs.
   - Lives in: hook, `WORKSTATION_MAINTENANCE.md`, `MCP_RUNTIME_STATUS.md`.
   - Runtime proof: toolchain source check and Memento runtime verifier.

4. English normalized internal intent compilation
   - Strengthens: PM pre-action discipline without changing user-facing Korean
     communication.
   - Objective improvement: separates goal, task type, authority boundary,
     toolchain purpose, evidence target, and memory action.
   - Prevents: conflating memory, tools, tests, and final authority.
   - Maintenance cost: prompt-only instruction, no runtime dependency.
   - Lives in: hook reminder and AGENTS.md.
   - Runtime proof: `UserPromptSubmit` hook output includes the intent frame.

5. Evidence sequencing and finalization
   - Strengthens: existing Goal Governance and Stop hook final audit.
   - Objective improvement: Memento evidence is explicitly candidate evidence,
     while final status still requires PM independent verification.
   - Prevents: "tool available", "MCP result", or "memory says so" becoming a
     completion claim.
   - Maintenance cost: documentation and runtime verifier.
   - Lives in: AGENTS.md, hook, runbook, MCP status.
   - Runtime proof: final goal audit plus `memento-mcp-runtime.ps1 verify`.

6. PM memory and Memento handoff loop
   - Strengthens: prior Memory/RAG support with a live MCP memory toolchain.
   - Objective improvement: `context`, `recall`, `remember`, `reflect`, and
     `tool_feedback` are attached to PM phases and write gates.
   - Prevents: stale raw Markdown memory reads, unreviewed imports, duplicate
     memory runtimes, and unsupported recall claims.
   - Maintenance cost: one managed runtime script, one MCP entry, and explicit
     legacy contamination boundaries.
   - Lives in: AGENTS.md, hook, `MCP_RUNTIME_STATUS.md`,
     `WORKSTATION_MAINTENANCE.md`, and this report.
   - Runtime proof: HTTP health, MCP `tools/list`, `get_skill_guide`,
     `context`, `recall`, `tool_feedback`, PostgreSQL readiness, and pgvector
     schema checks.

## Active Runtime

- Source: `%USERPROFILE%\.codex\tools\memento-mcp`.
- State: `%USERPROFILE%\.codex\state\memento-mcp`.
- PostgreSQL: local port `55432`, dedicated `memento_pm` database.
- Memento HTTP: `http://127.0.0.1:57332/mcp`.
- Codex MCP registration: `memento`, bearer token from `MEMENTO_ACCESS_KEY`.
- Manager/verifier: `maintenance\scripts\memento-mcp-runtime.ps1`.

## Legacy Contamination Decisions

- `toolchains\shims\memsearch.*`: retired, not active fallback.
- `maintenance\scripts\check-memory-rag-status.ps1`: retired status shim; points
  operators to Memento verifier.
- `memories\raw_memories.md`: historical data only. Do not import or read as
  authority unless the user explicitly asks for a reviewed migration.
- Historical reports that mention MemSearch remain historical records. They do
  not define active runtime policy after this report.

## Dont-Even-Try Contamination Review

Verdict: CLEAN for active workflow surfaces after remediation.

Checked:

- Active `memsearch`, `MemRAG`, `raw_memories`, and
  `check-memory-rag-status` references outside historical reports and third-party
  Memento source material.
- Hook reminders and AGENTS authority wording for hidden fallback or completion
  authority drift.
- Legacy executable entry points by running `memsearch.cmd --query test` and
  `check-memory-rag-status.ps1`.

Findings:

- No active reference still treats `memsearch` as a supported retrieval path.
- `memsearch.cmd` routes to `memsearch.ps1`, which exits with code 2 and points
  to the Memento verifier.
- `check-memory-rag-status.ps1` reports `status=legacy; active=false` and exits
  with code 2.
- Historical reports still mention MemSearch. They are retained as history and
  are superseded by this report, `MCP_RUNTIME_STATUS.md`, and
  `WORKSTATION_MAINTENANCE.md`.

## Post-Patch Code Review Corrections

The follow-up review found and corrected three issues:

- Korean prompts containing review/commit/push intent were not classified as
  review/ship/git by `UserPromptSubmit`; the hook now handles these localized
  signals through ASCII codepoint construction while keeping policy files ASCII.
- External runtime source trees under `tools/memento-mcp` and
  `tools/pgvector-v0.8.2` were visible to the parent Git repository as
  untracked embedded repositories; `.gitignore` now excludes these exact managed
  external checkouts while keeping the active runtime documented in maintenance
  records.
- The managed Memento HTTP process was loading in-process ONNX Reranker/NLI
  helpers and the local transformers semantic embedding model, leaving
  `node.exe server.js` around 1.1GB after app restart and semantic memory use.
  The Codex-managed start path now injects
  `MEMENTO_INPROCESS_ONNX_ENABLED=false` and
  `MEMENTO_MANAGED_EMBEDDING_PROVIDER=none`, `restart` recycles only the
  Memento HTTP process, and the verifier records and enforces the managed memory
  limit.

Local Memento source notes:

- `scripts/post-migrate-flexible-embedding-dims.js` is patched in the ignored
  local Memento checkout so PostgreSQL `vector(n)` typmods are checked with
  `format_type(...)`, not only `udt_name`.
- `package-lock.json` in the ignored local Memento checkout was updated by
  `npm audit fix` to remove moderate-or-higher vulnerabilities.
- These are local workstation runtime changes, not a vendored copy of
  Memento MCP in the parent repository.

## Verification Command

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.codex\maintenance\scripts\memento-mcp-runtime.ps1 verify
```

Expected result includes `status=pass`, `required_tools=present`,
`skill_guide_lifecycle=pass`, `context=pass`, `recall=pass`, and
`tool_feedback=pass`.

Observed verification on 2026-05-15:

- `memento-mcp-runtime.ps1 verify`: pass; PostgreSQL ready, Memento HTTP
  healthy, pgvector columns are `vector(384)`, Codex MCP registration enabled,
  19 MCP tools exposed by HTTP JSON-RPC, required memory tools present,
  `get_skill_guide`, `context`, `recall`, and `tool_feedback` passed.
- Hook parse and policy JSON parse: pass.
- Hook `SessionStart` and `UserPromptSubmit` samples: pass; reminders include
  Memento support-only authority, internal English intent frame, toolchain
  purpose, and no legacy Memory/RAG fallback.
- `codex_agent_harness.py verify`: pass after refreshing stale benchmark
  results.
- Memento package checks: `node --check` for the patched embedding-dimension
  script passed; `npm audit --audit-level=moderate` passed with 0
  vulnerabilities; `npm run lint:migrations` passed.
- Memento Jest root tests: pass with 11 suites and 115 tests when run with an
  explicit Windows-safe `--testMatch`.
- Memento managed memory check after restart: verifier reports
  `memento_working_set_mb=172.1` below managed limit `512` after required MCP
  tool checks; immediate post-restart status was `88.5`.

## Residual Risks

- Current Codex sessions may need reload before `mcp__memento__...` tools appear
  in the injected tool list. HTTP JSON-RPC smoke checks are acceptable interim
  runtime evidence and must be reported as such.
- The raw historical memory file was not imported into Memento. This is
  intentional to avoid unreviewed legacy contamination.
- The Memento source checkout contains upstream documentation with non-Windows
  examples. Those docs are source material only, not local runtime policy.
- Upstream Memento `npm test` is not Windows-clean as-is: the npm script uses
  POSIX environment-variable assignment, the Jest project glob misses tests
  under this Windows path, and some node:test files assume POSIX paths or
  `grep`. This does not block the active runtime verifier, but it remains an
  upstream test-harness portability risk.
