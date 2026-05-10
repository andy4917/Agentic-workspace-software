# Agent Tool Requirements

This file describes tools the agent should use even when the user does not name
them explicitly. It is operational guidance for `C:\Users\anise\.codex`.

## Default Resolution

Use `C:\Users\anise\.codex\toolchains\shims` as the first command surface.
The shims call installer-owned tools by absolute path; do not move package
manager directories into `.codex`.

## Core Stacks

### Python

- Use `uv` for project environment creation, lock/sync, and fast package tasks
  when a project has `pyproject.toml` or `uv.lock`.
- Use `python`, `pip`, and `pipx` through the `.codex` shims for global checks.
- Use `ruff`, `pytest`, `mypy`, `black`, `poetry`, `pdm`, `pre-commit`, `tox`,
  `nox`, and `semgrep` when the repo config or task calls for them.

### JavaScript / TypeScript

- Use the repo's lockfile/package manager first.
- Use `node`, `npm`, `npx`, `pnpm`, `bun`, and `deno` through `.codex` shims.
- Use `tsc`, `tsx`, `eslint`, `prettier`, `biome`, `pyright`, `yarn`, and `zx`
  when repo scripts or task validation call for them.

### Rust

- Use `cargo`, `rustc`, `rustfmt`, `cargo-clippy`, `cargo-nextest`, `cargo-insta`,
  `just`, and `rust-analyzer` through `.codex` shims.
- Prefer `cargo test` or `cargo nextest run` according to the repo's existing
  pattern.

### C / C++

- Use `cmake` and `zig` through `.codex` shims when present.
- Use MSVC shims `cl`, `nmake`, `link`, `lib`, `dumpbin`, and `rc`; each shim
  loads `vcvars64.bat` before invoking the tool.
- Use `msvc-x64-shell` when an interactive MSVC developer shell is needed.

## MCP Use Policy

MCP servers are only usable in a session after they are enabled in config and the
app has restarted or otherwise reloaded tool definitions. If a server is enabled
but no `mcp__...` tools appear in the active tool list, record that as a runtime
load issue, not as proof the tool is unnecessary.

- Use OpenAI Developer Docs MCP for OpenAI API/model/plugin documentation.
- Use Context7 only when `CONTEXT7_API_KEY` is available and current library
  documentation is needed.
- Use Sequential Thinking for high-ambiguity debugging or planning, not for
  routine edits.
- Use Windows PowerShell MCP only when its narrower tool policy is useful; the
  normal local shell remains the primary Windows diagnostics tool.

## Reasoning Effort Policy

Do not hard-code `xhigh` as the default. Keep the persistent config at a
placeholder default (`medium`) and escalate per task/session only when complexity,
ambiguity, or validation risk justifies it.

## Runtime Contamination Guard

The plugin feature may stay enabled, but active source paths must not point at
`.tmp`, `tmp`, `vendor_imports`, `bundled-marketplaces`, `plugins\cache`, or
`plugins\plugins`. Sentinel blockers may exist at those exact path names until
the app runtime stops regenerating bundled marketplace/cache clones.
