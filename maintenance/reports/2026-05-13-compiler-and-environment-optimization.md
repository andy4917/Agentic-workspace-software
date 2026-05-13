# Compiler And Environment Optimization Report

Date: 2026-05-13

## Goal

Close the remaining compiler/toolchain gaps and reduce obvious workstation
development-environment drift after the framework CLI install.

## Surfaces

- toolchain: LLVM, MSYS2 UCRT64, npm global packages, Python user packages,
  Scoop packages, package-manager caches
- managed-source: Codex toolchain shims, toolchain README, tool policy
- cache-generated-state: generated `vite-project` test scaffold and package
  caches

## Risk Level

high-risk-change. The user explicitly requested global compiler installation,
temporary scaffold removal, environment optimization, and Git push.

## Installed Or Updated

- Installed LLVM 22.1.5 from `LLVM.LLVM`.
- Installed MSYS2 20260322 from `MSYS2.MSYS2`.
- Installed MSYS2 UCRT64 packages:
  - `mingw-w64-ucrt-x86_64-gcc 16.1.0-3`
  - `mingw-w64-ucrt-x86_64-clang 22.1.4-4`
  - `mingw-w64-ucrt-x86_64-lld 22.1.4-4`
  - `mingw-w64-ucrt-x86_64-llvm 22.1.4-4`
  - `mingw-w64-ucrt-x86_64-llvm-tools 22.1.4-4`
  - `mingw-w64-ucrt-x86_64-pkgconf 2.5.1`
  - `mingw-w64-ucrt-x86_64-make 4.4.1`
  - `mingw-w64-ucrt-x86_64-gdb 17.1`
  - `mingw-w64-ucrt-x86_64-cmake 4.3.2`
  - `mingw-w64-ucrt-x86_64-ninja 1.13.2`
- Updated npm globals:
  - `@angular/cli 21.2.11`
  - `impeccable 2.1.9`
  - `pnpm 11.1.1`
- Removed legacy global `@vue/cli` because it pulled Vue 2 and Apollo Server
  v3 deprecated dependencies. Modern Vue scaffolding remains available through
  `create-vue`.
- Updated Python user packages including `openai 2.36.0`,
  `openai-agents 0.17.2`, `mcp 1.27.1`, `langchain 1.3.0`,
  `langgraph 1.2.0`, `cryptography 48.0.0`, `pydantic 2.13.4`,
  `requests 2.34.0`, and related dependencies.
- Updated Scoop tools:
  - `deno 2.7.14`
  - `gradle 9.5.1`
  - `temurin21-jdk 21.0.11-10.0`
  - `autohotkey 2.0.26`
  - `sysinternals 20260507`
  - `bun 1.3.14`
  - `opa 1.16.2`
  - `vcredist2022 14.51.36231.0`

## Added Codex Shims

Added wrappers under `%USERPROFILE%\.codex\toolchains\shims`:

- `clang`, `clang++`, `clang-cl`
- `gcc`, `g++`
- `lld`, `lld-link`, `llvm-config`
- `pkg-config`
- `make`, `mingw32-make`
- `gdb`
- `ucrt64-shell`
- `opa`

## Cleanup

- Moved generated
  `C:\Users\anise\Documents\Codex\2026-05-13\openai-sdk-typescript-python\vite-project`
  to the Windows Recycle Bin.
- Ran `npm cache verify`, which garbage-collected 63 cache entries
  (268,349,887 bytes).
- Ran `pnpm store prune`.
- Ran `uv cache prune`; no uv cache was present.
- Ran `python -m pip cache purge`, removing 404 files (32.7 MB).
- Ran `keep_codex_fast.py` in report mode only; no Codex sessions/logs/worktrees
  were archived or mutated.

## Verification

- Compiler shims:
  - `clang 22.1.4`, target `x86_64-w64-windows-gnu`
  - `clang++ 22.1.4`
  - `clang-cl 22.1.5`, target `x86_64-pc-windows-msvc`
  - `gcc 16.1.0`
  - `g++ 16.1.0`
  - `lld-link 22.1.4`
  - `llvm-config 22.1.4`
  - `pkg-config 2.5.1`
  - `make 4.4.1`
  - `gdb 17.1`
- C/C++ syntax smoke checks passed through `gcc`, `clang`, and `g++`.
- `npm ls -g vue@2 apollo-server-core apollo-server-express
  subscriptions-transport-ws --depth=8` returned empty after removing
  `@vue/cli`.
- `python -m pip check` returned `No broken requirements found.`
- `scoop status` returned `Scoop is up to date` and `Everything is ok`.
- The accidental `vite-project` folder no longer exists at the workspace path.

## Not Checked

- No full GUI or desktop app build was run for Tauri/Electron.
- No full CMake/native dependency project was generated and built.
- No Codex session cleanup was applied because Codex is active; report-only was
  used for safety.
- `npm audit -g` was not run because npm returns `EAUDITGLOBAL`: global audit is
  unsupported.

## Residual Risks

- `uipro-cli 2.5.0` remains newer than the npm `latest` tag `2.2.3`; it appears
  as outdated only because the registry dist-tag points backward. It was not
  downgraded.
- Electron Forge still has deprecated transitive dependencies through current
  upstream packages. The top-level package is already current, so this remains
  an upstream dependency-tree issue.
- `vcredist2022` reported that a Windows restart is required to complete that
  runtime update.
- MSYS2 pacman emitted mirror 404 warnings while fetching some packages, but
  package-query and binary smoke checks confirmed the requested packages are
  installed.

## Rollback

- LLVM: uninstall `LLVM.LLVM` via winget or Windows Apps.
- MSYS2: uninstall `MSYS2.MSYS2`; remove related Codex shims if the toolchain is
  not wanted.
- npm globals: `npm uninstall -g <package>` or reinstall previous versions.
- Python user packages: reinstall previous versions with `python -m pip install
  package==version`.
- Scoop packages: `scoop reset <app>@<version>` when prior versions remain in
  Scoop cache, or reinstall via Scoop.
- Shims: remove matching files under `.codex\toolchains\shims`.

