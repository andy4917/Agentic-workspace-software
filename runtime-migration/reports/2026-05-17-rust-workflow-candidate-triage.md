# Rust Workflow Candidate Triage - 2026-05-17

## Status

Accepted for planning. No Rust code, Cargo project, plugin command reference,
native-host manifest, registry key, or browser launch behavior was changed by
this triage.

## Correction

The earlier boundary should be read narrowly: Rust was not used in the previous
slice because the chosen replacements were compact helper CLIs with Python
fixture parity already available. That is not evidence that Rust is unsuitable.
Several deferred Chrome helper surfaces are good Rust candidates once their CLI
contracts are captured and tested.

## Evidence Inspected

- `plugins/patched/openai-bundled/plugins/chrome/scripts/installed-browsers.js`
- `plugins/patched/openai-bundled/plugins/chrome/scripts/open-chrome-window.js`
- `plugins/patched/openai-bundled/plugins/chrome/scripts/installManifest.mjs`
- `runtime-migration/inventory/js-language-handoff.yaml`
- `runtime-migration/inventory/node-js-surfaces.yaml`
- `runtime-migration/contracts/cli-contracts.yaml`

## Candidate Ranking

1. `installed-browsers.js`: best first Rust slice. It is an observe-only CLI:
   registry queries, command lookup, filesystem probes, plist parsing, and
   JSON/text output. The source shows no file writes and no browser launch. Rust
   can model this behind command/filesystem/platform adapters and compare JSON
   output against JS fixtures.

2. `open-chrome-window.js`: viable only after dry-run parity. Its profile
   selection and executable resolution are testable, and `--dry-run --json`
   exposes a stable launch plan. Real launch remains higher risk because it
   invokes `cmd.exe start`, `open`, or `google-chrome`.

3. `installManifest.mjs`: possible, but not a safe first slice. The script
   validates a bundled extension-host binary, writes native messaging host JSON,
   and on Windows runs `reg add` under `HKCU`. A Rust version should start as
   dry-run manifest generation only, with explicit apply, backup, rollback, and
   native-host smoke checks before replacement.

4. `runtime_migration/node_js_surface_scanner.py`: Rust-friendly later, but the
   current Python scanner is the inventory parity oracle while schemas are still
   moving.

5. `browser-client.mjs`: not a first slice. A Rust role here would be a separate
   native-host or protocol kernel design, not a direct language-stat rewrite.

## Safe First Slice

Create an isolated Cargo project under
`runtime-migration/rust/chrome-installed-browsers` only after the draft contract
in `contracts/cli-contracts.yaml` is accepted. Keep the plugin command pointing
at the existing JS helper until fixture parity, Windows smoke evidence, and
rollback notes exist.

Minimum acceptance:

- `cargo fmt --check`
- `cargo test` using injected command-output and filesystem fixtures
- JS vs Rust `--json` parity on safe fixtures
- JS vs Rust `--check` exit-code parity for empty inventory
- no real browser profile, cookie, secret, native-host, or registry mutation in tests

## Compatibility Impact

- Hooks and workflow gates: unchanged. This is documentation and contract
  scaffolding only.
- MCP/toolchain routes: unchanged. Rust future work must use
  `%USERPROFILE%\.codex\toolchains\shims\cargo.cmd`.
- Plugin cache boundaries: unchanged. Patched Chrome app-cache files were read
  as evidence but not modified.
- Tests: structured YAML parse checks are sufficient for this triage; no runtime
  browser smoke is expected because no runtime behavior changed.
- Rollback: remove this report and revert
  `runtime-migration/README.md`,
  `runtime-migration/contracts/cli-contracts.yaml`, and
  `runtime-migration/inventory/rust-workflow-candidates.yaml`. No external
  state rollback is needed.

## Residual Risk

This triage is based on source inspection and structured contract capture, not a
compiled Rust implementation. Real OS discovery behavior can still diverge
across Windows registry virtualization, localized command output, macOS
LaunchServices data, and Linux desktop settings, so the first Rust slice must
prove parity with fixtures before any plugin replacement.
