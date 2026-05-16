# Runtime Migration

This directory is the controlled Rust/Python split workspace for active
Node/JS surfaces under `%USERPROFILE%\.codex`.

Current scope:

- inventory first;
- Memento MCP excluded unless a later explicit request changes that boundary;
- Python for read-only inventory and migration orchestration;
- Rust reserved for protocol kernels, long-lived services, and hot local
  validation paths after contracts exist.
- Rust candidate triage is recorded in
  `inventory/rust-workflow-candidates.yaml`; absence of current tracked Rust
  source does not mean the deferred surfaces are unsuitable for an isolated Rust
  compile workflow.
- The current Rust correction report is
  `reports/2026-05-17-rust-workflow-candidate-triage.md`; it ranks
  `installed-browsers.js` as the safe first Rust slice, keeps
  `open-chrome-window.js` behind dry-run parity, and treats
  `installManifest.mjs` as a later controlled-change surface.

First verifier:

```powershell
%USERPROFILE%\.codex\toolchains\shims\python.cmd %USERPROFILE%\.codex\runtime-migration\python\runtime_migration\node_js_surface_scanner.py --root %USERPROFILE%\.codex --output %USERPROFILE%\.codex\runtime-migration\inventory\node-js-surfaces.yaml
```

GitHub language-stat rule:

- `plugins/patched/openai-bundled/**` is plugin-owned app-cache, not owned
  migration source, and is marked `linguist-vendored` in `.gitattributes`.
- Any JS kept because a forced Rust/Python rewrite would break plugin or browser
  behavior must be recorded in `inventory/js-language-handoff.yaml` before it is
  counted as deferred rather than migrated.
- Compact helper CLIs may be migrated out of plugin app-cache only when their
  command contract is documented and covered by Python compile plus fixture
  tests that avoid reading real user browser data.
- Rust helper CLIs must also keep app-cache command references unchanged until
  `contracts/cli-contracts.yaml` parity checks pass and rollback is documented.
