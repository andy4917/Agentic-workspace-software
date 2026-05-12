# Codex Managed Toolchain Entry Points

This directory makes the active Codex toolchain visible without relocating
installer-owned directories.

Source classes:

- `official-bundle`: executables shipped by Codex Desktop under
  `%LOCALAPPDATA%\OpenAI\Codex\bin`, the WindowsApps Codex package, or the
  primary workspace runtime returned by `load_workspace_dependencies`. Prefer
  this class for tools that Codex bundles, currently `node`, `node_repl`, `rg`,
  `codex`, and app-provided workspace dependency runtimes.
- `local-chain`: local package manager or language toolchain used only when the
  tool is not bundled, for example `npm`, `npx`, Python tools, Rust, JVM, Git,
  and package-manager CLIs.
- `local-wrapper`: a `.codex\toolchains\shims\*.cmd` wrapper that selects one of
  the classes above. Wrappers must not point at broken package-manager shims.

Do not put `%USERPROFILE%\.codex\toolchains\shims` in persistent User or Machine
PATH. Use these shims by explicit path or process-local PATH only for a bounded
task.

Already-running apps keep their inherited PATH until they restart. Treat
persistent PATH entries for this directory as contamination to be removed after
backup and verification.

Current shim groups:

- Official Codex bundle wrappers: `node`, `rg`
- JavaScript local-chain: `npm`, `npx`, `pnpm`, `bun`, `deno`, `tsc`, `tsserver`,
  `tsx`, `eslint`, `prettier`, `biome`, `yarn`, `zx`
- Python: `python`, `py`, `pip`, `pipx`, `uv`, `ruff`, `pytest`, `mypy`,
  `black`, `poetry`, `pdm`, `pre-commit`, `tox`, `nox`, `semgrep`
- Git/search/shell utilities: `git`, `gh`, `rg`, `fd`, `fzf`, `jq`, `es`, `7z`,
  `code`, `pwsh`
- Rust/JVM/build: `rustc`, `cargo`, `rustup`, `rustfmt`, `cargo-nextest`,
  `cargo-insta`, `cargo-dylint`, `just`, `rust-analyzer`, `java`, `javac`,
  `mvn`, `gradle`, `cmake`
- C/C++: `zig`, `cl`, `nmake`, `link`, `lib`, `dumpbin`, `rc`,
  `msvc-x64-shell`
- System/package: `scoop`, `winget`, `choco`

Do not place runtime cache, temporary clones, package stores, or bundled
marketplace payloads here.

Quick check:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.codex\maintenance\scripts\check-toolchain-sources.ps1
```

The check fails for broken wrapper targets and for bundled-tool wrappers that do
not use the official Codex bundle.
