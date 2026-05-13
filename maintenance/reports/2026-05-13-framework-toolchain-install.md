# Framework Toolchain Install Report

Date: 2026-05-13

## Goal

Install workstation-global framework and app-construction tooling that was
missing from the local development surface.

## Surfaces

- toolchain: npm global packages, Python user packages, Cargo binaries, .NET SDK
- managed-source: Codex shim wrappers and toolchain README
- cache-generated-state: npm/Cargo/Python package caches and one accidental Vite
  scaffold directory

## Risk Level

high-risk-change. The user explicitly requested global installation as the
direction for workstation framework coverage.

## Installed

JavaScript and TypeScript global packages under `%APPDATA%\npm`:

- `next`, `create-next-app`
- `vite`, `create-vite`
- `react`, `react-dom`
- `vue`, `create-vue`, `@vue/cli`
- `nuxt`, `nuxi`
- `svelte`, `sv`
- `astro`, `create-astro`
- `@angular/cli`
- `@remix-run/dev`
- `express`, `express-generator`
- `@nestjs/cli`
- `electron`, `@electron-forge/cli`

Python user packages for Python 3.14:

- `fastapi[standard]`
- `django`
- `flask`

Rust/Cargo app construction tools:

- `tauri-cli`
- `trunk`
- `cargo-generate`
- `wasm-pack`
- `cargo-edit`

.NET:

- Microsoft .NET SDK 10.0

## Added Codex Shims

Added wrappers under `%USERPROFILE%\.codex\toolchains\shims` for the new
framework tools, including `next`, `create-next-app`, `vite`, `create-vite`,
`create-vue`, `ng`, `sv`, `astro`, `create-astro`, `nuxt`, `nuxi`,
`remix`, `express`, `nest`, `electron`, `electron-forge`, `fastapi`,
`django-admin`, `flask`, `dotnet`, `cargo-tauri`, `trunk`, `wasm-pack`,
`cargo-generate`, `cargo-add`, `cargo-rm`, `cargo-upgrade`, and
`cargo-set-version`.

## Verification

- `npm list -g --depth=0` showed the installed JS/TS packages.
- `python -m pip list` showed `fastapi 0.136.1`, `Django 6.0.5`,
  `Flask 3.1.3`, `uvicorn 0.46.0`, and `starlette 1.0.0`.
- `cargo install --list` showed `tauri-cli 2.11.1`, `trunk 0.21.14`,
  `cargo-generate 0.23.8`, `wasm-pack 0.14.0`, and `cargo-edit 0.13.10`.
- `dotnet --list-sdks` showed `10.0.204 [C:\Program Files\dotnet\sdk]`.
- Direct shim smoke checks succeeded for Next.js, Vite, Vue CLI, Svelte CLI,
  Astro, Nuxt/Nuxi, Remix, Express generator, Nest CLI, Electron,
  Electron Forge, FastAPI CLI, Django admin, Flask, .NET, Tauri CLI, Trunk,
  wasm-pack, and cargo-generate.
- `maintenance\scripts\check-toolchain-sources.ps1` returned
  `status=pass; failures=0; warnings=0`.

## Not Checked

- No full project scaffolds were built and run end-to-end, except for an
  accidental `create-vite` scaffold during version probing.
- LLVM/Clang/GCC were inspected but not installed in this pass.
- Rust framework crates such as Axum, Actix Web, Rocket, Bevy, and Dioxus were
  not globally installed because they are project dependencies rather than
  global executables.

## Residual Risks

- npm emitted deprecation warnings from transitive dependencies, especially
  legacy packages pulled by framework CLI dependency trees. This is common for
  global scaffold tooling but should be considered when selecting project-local
  dependencies.
- `create-vite --version` unexpectedly scaffolded
  `C:\Users\anise\Documents\Codex\2026-05-13\openai-sdk-typescript-python\vite-project`.
  Removal was blocked by the lightweight destructive-action hook pending user
  approval.
- The active shell PATH may not resolve every newly installed command until new
  shells are opened. Codex can use the explicit `.codex\toolchains\shims`
  paths immediately.

## Rollback

- JS/TS: `npm uninstall -g <package>`
- Python: `python -m pip uninstall <package>`
- Rust: `cargo uninstall <crate>`
- .NET SDK: uninstall `Microsoft.DotNet.SDK.10` via winget or Windows Apps
- Shims: remove the matching files under `.codex\toolchains\shims`
