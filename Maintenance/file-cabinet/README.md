# Root File Cabinet

This cabinet keeps root-level `%USERPROFILE%\.codex` files manageable without moving live Codex files away from the paths the app expects.

## Layout

- `root-files/`: one folder per root-level file.
- `root-files/<file>/README.md`: source path, status, size, modified time, and snapshot status.
- `root-files/<file>/snapshot/`: copies only for safe static documents and manifests.
- `root-files.index.json`: machine-readable inventory for all root-level files.

## Safety Policy

- Live runtime, database, session, cache, and credential files remain in place.
- `auth.json` and similar credential/session files are never copied by this script.
- SQLite, WAL, SHM, state, cache, and session index files are indexed only.
- Re-run `Maintenance/Manage-RootFileCabinet.ps1 -Refresh` to refresh folders and safe snapshots.
