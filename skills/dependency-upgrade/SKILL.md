---
name: dependency-upgrade
description: Use when upgrading, replacing, pinning, auditing, or troubleshooting dependencies, packages, runtimes, SDKs, CLIs, lockfiles, peer dependencies, security fixes, or compatibility migrations.
---

# Dependency Upgrade

## Workflow

1. Inspect package manifests, lockfiles, runtime version files, toolchain shims, and existing upgrade scripts.
2. Use Context7 or official project documentation for current APIs, migration notes, and version-specific behavior.
3. Upgrade the narrowest dependency set that satisfies the goal. Avoid broad lockfile churn unless required.
4. Check peer dependency, engine, bundler, test, type, and build compatibility.
5. Run the project verification path and inspect generated lockfile changes before claiming success.

## Guardrails

- Do not rely on memory for current package behavior.
- Do not hide audit or install failures with force flags unless the user explicitly accepts the risk.
- Preserve rollback: old version, lockfile diff, and command path.

## Exit Evidence

Report old/new versions, source docs consulted, commands run, lockfile impact, compatibility issues, checks not run, and rollback path.
