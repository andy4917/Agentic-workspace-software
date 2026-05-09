# Changelog

## 2026-05-09T19:42:50+09:00

- Consolidated GlobalSSOT into `%USERPROFILE%\.codex`.
- Removed obsolete enforcement surfaces from the active root.
- Replaced user-specific absolute root references with `%USERPROFILE%`-based paths.
- Preserved sensitive-user-state policy: credential/session/cache/sqlite contents were not read.
