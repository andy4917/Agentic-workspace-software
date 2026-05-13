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
- `local-wrapper`: a `.codex\toolchains\shims\*.cmd` or `*.ps1` wrapper that
  selects one of the classes above. Wrappers must not point at broken
  package-manager shims.

Do not put `%USERPROFILE%\.codex\toolchains\shims` in persistent User or Machine
PATH. Use these shims by explicit path or process-local PATH only for a bounded
task.

Already-running apps keep their inherited PATH until they restart. Treat
persistent PATH entries for this directory as contamination to be removed after
backup and verification.

Windows `rg` note:

- `rg.ps1` is the PowerShell-safe wrapper for search patterns or paths that may
  contain cmd metacharacters such as `|`, `&`, `<`, or `>`.
- `rg.cmd` is a cmd.exe compatibility wrapper. Do not call it directly from
  PowerShell with unescaped cmd metacharacters; use bare `rg`, bundled `rg.exe`,
  or `rg.ps1`.

Current shim groups:

- Official Codex bundle wrappers: `node`, `rg`
- JavaScript local-chain: `npm`, `npx`, `pnpm`, `bun`, `deno`, `tsc`, `tsserver`,
  `tsx`, `eslint`, `prettier`, `biome`, `yarn`, `zx`, `next`,
  `create-next-app`, `vite`, `create-vite`, `create-vue`, `ng`,
  `sv`, `astro`, `create-astro`, `nuxt`, `nuxi`, `remix`, `express`,
  `nest`, `electron`, `electron-forge`
- Python: `python`, `py`, `pip`, `pipx`, `uv`, `ruff`, `pytest`, `mypy`,
  `black`, `poetry`, `pdm`, `pre-commit`, `tox`, `nox`, `semgrep`,
  `fastapi`, `django-admin`, `flask`
- Git/search/shell utilities: `git`, `gh`, `rg`, `fd`, `fzf`, `jq`, `es`, `7z`,
  `code`, `pwsh`, `opa`
- Rust/JVM/build: `rustc`, `cargo`, `rustup`, `rustfmt`, `cargo-nextest`,
  `cargo-insta`, `cargo-dylint`, `just`, `rust-analyzer`, `cargo-tauri`,
  `trunk`, `wasm-pack`, `cargo-generate`, `cargo-add`, `cargo-rm`,
  `cargo-upgrade`, `cargo-set-version`, `java`, `javac`, `mvn`, `gradle`,
  `cmake`, `dotnet`
- C/C++: `zig`, `cl`, `nmake`, `link`, `lib`, `dumpbin`, `rc`,
  `msvc-x64-shell`, `clang`, `clang++`, `clang-cl`, `gcc`, `g++`, `lld`,
  `lld-link`, `llvm-config`, `pkg-config`, `make`, `mingw32-make`, `gdb`,
  `ucrt64-shell`
- System/package: `scoop`, `winget`, `choco`

Do not place runtime cache, temporary clones, package stores, or bundled
marketplace payloads here.

Quick check:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.codex\maintenance\scripts\check-toolchain-sources.ps1
```

The check fails for broken wrapper targets and for bundled-tool wrappers that do
not use the official Codex bundle.

Last verification:

- 2026-05-13 20:20 KST: `check-toolchain-sources.ps1` returned
  `status=pass; failures=0; warnings=0`.
- Tool invocations in Codex workstation maintenance used explicit shim paths
  under `%USERPROFILE%\.codex\toolchains\shims` for package-manager and local
  toolchain commands.
