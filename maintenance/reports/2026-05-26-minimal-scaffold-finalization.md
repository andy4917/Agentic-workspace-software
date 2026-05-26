# Minimal Scaffold Finalization Evidence

Date: 2026-05-26.

Scope: post-reinstall Codex minimal scaffold under `%USERPROFILE%\.codex` and
tracked control-plane source in this repository. This report records evidence
that can be gathered while Codex Desktop is still running. It does not close the
live-runtime cleanup gate.

## Current Blocking Gate

- `hot_runtime_top_level_minimal`: still blocked while Codex Desktop is running.
  Live state currently includes session, SQLite/WAL/SHM, logs, cache, browser,
  plugin, tool, sandbox, auth, and app state roots under `%USERPROFILE%\.codex`.
- Required safe close path: fully close Codex Desktop, capture a live-runtime
  tree manifest, archive SQLite/WAL/SHM, old sessions, logs, and caches, exclude
  auth/credential files from the baseline, rerun
  `maintenance\scripts\validate-codex-scaffold.ps1`, then freeze the final
  clean baseline manifest and archive SHA256.

## Config Reconcile Drift

- Observed failure: Codex Desktop rewrote runtime-managed TOML into
  `config.toml` after startup/tool discovery, causing
  `config_fragment_reconcile_match` to report mismatches for `00-policy.toml`,
  `20-hooks.toml`, and `30-skills.toml`.
- Runtime-managed additions observed: `browser@openai-bundled`, `hooks.state`
  trusted hashes, and `marketplaces.openai-bundled` pointing at
  `.codex\.tmp\bundled-marketplaces\openai-bundled`.
- Remediation run: `%USERPROFILE%\.codex\maintenance\scripts\compile-config.ps1
  -CodexHome %USERPROFILE%\.codex`.
- Result: rebuilt `%USERPROFILE%\.codex\config.toml` with SHA256
  `B2D0E703087D9F8C3C1AD15E084DE00E4AC292B498BB46DDD3A85D8E23255148`; fresh
  validation reports `config_fragment_reconcile_match: pass`.

## Serena Next-Spawn Evidence

- Trigger: current session exposed Serena tools through tool discovery and
  `initial_instructions` was called.
- Process evidence after spawn: one `serena.exe start-mcp-server` root was
  present, with command-line args including `--project-from-cwd`,
  `--context=codex`, and `--open-web-dashboard False`.
- Validator evidence: `serena_single_server_process: pass`, root count `1`.
- Residual risk: this proves the next spawn in this Codex session did not create
  duplicate server roots. It does not prove cross-client single-instance
  behavior if multiple Codex clients concurrently start stdio Serena servers.

## Memento Baseline Policy

- Baseline policy: `registered + read-only live verify`.
- Active registration: `memento` remains in `config.toml` and targets
  `http://127.0.0.1:57332/mcp` with token from `MEMENTO_ACCESS_KEY`.
- Runtime source: local-chain checkout
  `%USERPROFILE%\.codex\tools\memento-mcp`, with managed patches vendored under
  `maintenance\patches`.
- Verification: `memento-mcp-runtime.ps1 verify` is read-only by default and
  reports `tool_feedback=skipped-readonly`; write/feedback probes require
  `verify -WriteProbe`.
- Baseline exclusion: PostgreSQL data, Memento state, logs, credentials, and
  runtime caches are not part of the final clean scaffold archive.

## Reinstall Evidence

- `codex --version`: `codex-cli 0.133.0-alpha.1`.
- Codex bundle root: `%LOCALAPPDATA%\OpenAI\Codex`.
- Bundle root creation time: `2026-05-25T20:12:07Z`.
- Bundled command paths observed:
  - `%LOCALAPPDATA%\OpenAI\Codex\bin\3f4fb8cdd344abc7\codex.exe`
  - `%LOCALAPPDATA%\OpenAI\Codex\bin\5b9024f90663758b\node.exe`
  - `%LOCALAPPDATA%\OpenAI\Codex\bin\ada252862d154cdd\rg.exe`
  - `%LOCALAPPDATA%\OpenAI\Codex\bin\3c238e29bbc930ff\node_repl.exe`
- Strict config proof after recompile: `codex --strict-config exec --help`
  completed successfully.

## Credential Lifecycle Evidence

- Git remote uses SSH:
  `git@github.com:andy4917/Agentic-workspace-software.git`.
- Global Git identity is set to the requested name and email.
- Private key material was not read.
- Public key file observed: `%USERPROFILE%\.ssh\id_ed25519.pub`.
- Current public key fingerprint: `SHA256:gAOgmfBkYE1Oxy2s72apLOUgehQLtk+fC/1bx9Ob3nI`.
- User-supplied public key fingerprint in the handoff prompt:
  `SHA256:PQaqXI7sTN08D+9L2BPJJ6J8QVFjLGvjBJflrTPf65c`.
- Residual risk: the current local public key differs from the user-supplied
  public key in the prompt. Push succeeded earlier, so the active key is usable,
  but the final credential ledger should record which fingerprint is registered
  in GitHub, the GitHub key title, the local public/private key paths, and the
  revocation note. Do not store private key contents or raw tokens in this repo.

## Cloud Archive Target

- Checked local filesystem drives and top-level user directories for a mounted
  Google Drive or equivalent cloud target.
- Result: no Google Drive/Drive mount was present in the local filesystem view.
- Residual risk: final compressed/deduplicated archive SHA256 cannot be proven
  against the 2 TB cloud target from this session. Close by uploading the final
  baseline/archive to the chosen cloud target, then record remote path, archive
  name, size, and SHA256 in the local final manifest.

## Final Freeze Requirements

Before marking `clean-baseline-manifest.json` as `final`:

1. Close Codex Desktop completely.
2. Capture a live-runtime tree manifest.
3. Archive/quarantine old sessions, logs, SQLite/WAL/SHM, caches, and non-keep
   runtime residue without reading credential contents.
4. Recompile `config.toml` from `config.d` after any app-managed runtime edits.
5. Run `validate-codex-scaffold.ps1` and require every check to pass.
6. Create the final baseline zip and record SHA256.
7. Supersede any provisional Desktop snapshot.
8. Record P0/P1 findings as `none`, or keep the manifest blocked.
