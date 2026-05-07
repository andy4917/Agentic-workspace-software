# Dev_Codex_App_GlobalSSOT

Canonical root for the clean-slate Codex App global SSOT.

This root is the source for managed declarative config, hook config, runtime state schemas, evidence fixtures, and bookkeeping documents. Runtime data is not moved by default.

Primary folders:

- `Settings`: declarative config, runtime state declarations, and hook implementation files.
- `Maintenance`: audit notes and operational verification records for this SSOT.

Required bookkeeping:

- New managed elements are registered in `MANIFEST.json`.
- Behavior, scope, or naming changes are recorded in `CHANGELOG.md`.
- Imported storage folders are mapped in `ROOT_MAP.json`.

