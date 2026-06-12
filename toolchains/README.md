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
- `git.ps1`, `gh.ps1`, `pwsh.ps1`, `codex.ps1`, and `no-mistakes.ps1` are the
  PowerShell-native entry points for Codex-managed runs. The corresponding
  `.cmd` files remain compatibility wrappers for cmd.exe callers only, except
  retired GitHub CLI `.cmd` wrappers, which should not be restored.

Current shim groups:

- Official Codex bundle wrappers: `codex`, `node`, `rg`
- JavaScript local-chain: `npm`, `npx`, `pnpm`, `bun`, `deno`, `tsc`, `tsserver`,
  `tsx`, `eslint`, `prettier`, `biome`, `yarn`, `zx`, `next`,
  `create-next-app`, `vite`, `create-vite`, `create-vue`, `ng`,
  `sv`, `svelte-kit`, `webpack`, `webpack-cli`, `astro`, `create-astro`, `nuxt`, `nuxi`, `remix`, `express`,
  `nest`, `electron`, `electron-forge`
- Python: `python`, `py`, `pip`, `pipx`, `uv`, `ruff`, `pytest`, `mypy`,
  `black`, `poetry`, `pdm`, `pre-commit`, `tox`, `nox`, `semgrep`,
  `fastapi`, `django-admin`, `flask`
- Git/search/shell utilities: `git`, `gh`, `rg`, `fd`, `fzf`, `jq`, `es`, `7z`,
  `code`, `pwsh`, `opa`, `no-mistakes`
- Rust/JVM/build: `rustc`, `cargo`, `rustup`, `rustfmt`, `cargo-nextest`,
  `cargo-insta`, `cargo-dylint`, `just`, `rust-analyzer`, `cargo-tauri`,
  `trunk`, `wasm-pack`, `cargo-generate`, `cargo-add`, `cargo-rm`,
  `cargo-upgrade`, `cargo-set-version`, `java`, `javac`, `mvn`, `gradle`,
  `cmake`, `dotnet`
- C/C++: `zig`, `cl`, `nmake`, `link`, `lib`, `dumpbin`, `rc`,
  `msvc-x64-shell`, `clang`, `clang++`, `clang-cl`, `gcc`, `g++`, `lld`,
  `lld-link`, `llvm-config`, `pkg-config`, `make`, `mingw32-make`, `gdb`,
  `ucrt64-shell`
- Windows debugging: `cdb`, `dumpchk`, `symchk`
- System/package: `scoop`, `winget`, `choco`

Debugger status:

- Active and verified: `gdb.cmd --version` for GNU/UCRT debugging and
  `cdb.cmd -version` for Windows/MSVC dump or native debugging.
- Python built-in debugger: `pdb` is available through the managed Python 3.14.5
  shim. `debugpy` is not currently installed or exposed as a command.
- Installed wrapper targets: `dumpchk.cmd` and `symchk.cmd` under Windows
  Debugging Tools.
- Conditional Rustup wrappers: `rust-gdb.cmd`, `rust-gdbgui.cmd`, and
  `rust-lldb.cmd` exist, but the active Rust toolchain is
  `stable-x86_64-pc-windows-msvc`; `rust-gdb.cmd --version` and
  `rust-lldb.cmd --version` currently report `not applicable`. Treat them as
  present-but-not-active until a compatible Rust toolchain/debugger path is
  deliberately selected and verified.

Do not claim a debugger was used unless a debugger command was invoked and the
command evidence is reported. Otherwise report it as available but not used, or
conditional/unavailable with the reason.

Do not place runtime cache, temporary clones, package stores, or bundled
marketplace payloads here.

Quick check:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File %USERPROFILE%\.codex\maintenance\scripts\check-toolchain-sources.ps1
```

The check fails for broken wrapper targets and for bundled-tool wrappers that do
not use the official Codex bundle.

Last verification:

- 2026-05-16 KST: `check-toolchain-sources.ps1 -Json` returned
  `status=pass; failures=0; warnings=0`; `gdb` and `cdb` version probes passed,
  while Rustup `rust-gdb` and `rust-lldb` probes were recorded as conditional
  under the active MSVC Rust toolchain. Python `pdb` was available through the
  Python 3.14.5 shim, and `debugpy` was not installed.
- 2026-05-13 21:36 KST: `check-toolchain-sources.ps1` returned
  `status=pass; failures=0; warnings=0` after adding Windows Debugging Tools
  wrappers.
- 2026-05-13 21:35 KST: Windows Debugging Tools installed from
  `Microsoft.WindowsSDK.10.0.26100` with debugger feature only; wrappers point
  at `C:\Program Files (x86)\Windows Kits\10\Debuggers\x64`.
- 2026-05-13 20:20 KST: `check-toolchain-sources.ps1` returned
  `status=pass; failures=0; warnings=0`.
- Tool invocations in Codex workstation maintenance used explicit shim paths
  under `%USERPROFILE%\.codex\toolchains\shims` for package-manager and local
  toolchain commands.
- 2026-06-11 KST: PowerShell-native `git.ps1`, `gh.ps1`, `pwsh.ps1`,
  `codex.ps1`, and `no-mistakes.ps1` were added so
  Git/GitHub/no-mistakes/Codex-maintenance commands do not repeatedly open
  foreground `cmd.exe` windows from Codex-managed PowerShell runs. The `.cmd`
  wrappers remain compatibility entry points for cmd.exe callers, not the
  preferred PM workflow route.
- 2026-06-10 KST: `no-mistakes` adopted as the outer repository validation
  gate. The active wrapper is
  `%USERPROFILE%\.codex\toolchains\shims\no-mistakes.ps1`, which invokes the
  official `kunchenguid/no-mistakes` release binary under
  `%LOCALAPPDATA%\no-mistakes` with telemetry and background update checks
  disabled for deterministic Codex-managed runs. The wrapper intentionally
  removes the Codex shim directory from its child `PATH` so
  no-mistakes-spawned shell commands resolve real `pwsh.exe` instead of `.cmd`
  wrappers. It must normalize PATH entries only for the shim-directory
  comparison and append retained entries unchanged. The no-mistakes Codex agent
  path is overridden to
  `%USERPROFILE%\.codex\toolchains\no-mistakes\codex-agent-hidden.exe`, a
  managed hidden launcher that delegates to bundled `codex.exe` without opening
  a foreground console window. It streams stdout/stderr, closes stdin by
  default to prevent `codex exec` from waiting for additional prompt input, and
  only forwards stdin when `CODEX_AGENT_HIDDEN_FORWARD_STDIN=1` is set. The
  no-mistakes `agent_args_override.codex` block must also pass
  `-c model_reasoning_effort="medium"` so gate agents do not inherit the
  interactive-session `xhigh` reasoning setting.
