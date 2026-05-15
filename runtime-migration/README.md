# Runtime Migration

This directory is the controlled Rust/Python split workspace for active
Node/JS surfaces under `%USERPROFILE%\.codex`.

Current scope:

- inventory first;
- Memento MCP excluded unless a later explicit request changes that boundary;
- Python for read-only inventory and migration orchestration;
- Rust reserved for protocol kernels, long-lived services, and hot local
  validation paths after contracts exist.

First verifier:

```powershell
%USERPROFILE%\.codex\toolchains\shims\python.cmd %USERPROFILE%\.codex\runtime-migration\python\runtime_migration\node_js_surface_scanner.py --root %USERPROFILE%\.codex --output %USERPROFILE%\.codex\runtime-migration\inventory\node-js-surfaces.yaml
```
