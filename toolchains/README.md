# Codex Managed Toolchain Entry Points

This directory makes the active local toolchain visible and preferred from
`C:\Users\anise\.codex` without relocating installer-owned directories.

`shims\*.cmd` files call the canonical installed tools by absolute path.
Put `C:\Users\anise\.codex\toolchains\shims` at the front of User PATH so
Codex and new terminals resolve these managed entry points first.

Already-running apps keep their inherited PATH until they restart. After changing
User PATH, restart Codex Desktop before treating these shims as the app runtime's
active toolchain entry points.

Current shim groups:

- JavaScript: `node`, `npm`, `npx`, `pnpm`, `bun`, `deno`, `tsc`, `tsserver`,
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
- System/package/container: `scoop`, `winget`, `choco`, `docker`

Do not place runtime cache, temporary clones, package stores, or bundled
marketplace payloads here.
