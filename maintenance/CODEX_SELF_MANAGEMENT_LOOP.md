# Codex Self-Management Loop

This document adapts `codex_self_management_loop_proposal.md` to this Windows
workstation. It is managed-source policy for Codex operations, not a new
runtime state store.

## Decision

Do not create a separate `CodexOps` repository for this workstation. The current
split already has the required shape:

- `C:\Users\anise\Documents\Codex` is the reviewable managed-source repository.
- `C:\Users\anise\.codex` is the live runtime root and `CODEX_HOME`.
- Public-safe desired state lives in this repository.
- Private runtime truth, credentials, sessions, SQLite state, caches, and raw
  app state stay under `.codex` and are not committed.

## Permission Posture

The user-requested default is maximum local autonomy:

- `sandbox_mode = "danger-full-access"`
- `approval_policy = "never"`
- `[windows].sandbox = "elevated"`

This is execution permission, not completion authority. Codex may perform the
ordinary implementation, repair, validation, and cleanup work needed for a user
goal without asking the user to operate tools manually. It must still avoid
untargeted secrets, keep destructive actions scoped and reversible when
practical, and report external irreversible actions such as push, publish,
deploy, account changes, or paid operations with direct evidence.

The live runtime policy source is `C:\Users\anise\.codex\config.d\00-policy.toml`.
The managed public-safe mirror is `config.d\00-policy.toml`. Validation must
prove the managed and live copies are synchronized and that `config.toml`
matches the live fragment.

## Managed Surfaces

Primary managed surfaces:

- `AGENTS.md`: global operating contract for this managed source.
- `config.d\00-policy.toml`: public-safe runtime policy fragment.
- `hooks\compact-codex-hook.ps1`: deterministic hook runner.
- `maintenance\scripts\*.ps1`: runtime inspection, cleanup, and validation.
- `maintenance\*.md`: runbooks, policies, and evidence contracts.
- `automations\*\automation.toml`: managed automation definitions or drafts.
- `maintenance\templates\specops\*`: reusable spec/architecture governance
  templates for product repositories.

## Loop

1. Inspect current user goal, live runtime evidence, managed source, and relevant
   prior thread result packets.
2. Classify unexpected files or old-looking state before trusting or removing
   them.
3. Patch the smallest managed-source surface that fixes the confirmed mismatch.
4. Copy only public-safe live-called files into `.codex`.
5. Reconcile live `config.d` into `config.toml` when a config fragment changes.
6. Verify with `validate-codex-scaffold.ps1`, `codex-p0-integrity-loop.ps1`,
   direct runtime process checks, and targeted smoke tests.
7. Report changed surfaces, direct checks, not-run checks, rollback notes, and
   residual risk.

## Automation Model

Automation starts as managed source. A managed automation file is not proof that
the Codex app has scheduled it.

Automation candidates must define:

- goal and scope;
- execution root;
- write surfaces;
- permission posture;
- stop condition;
- expected report;
- not-run and rollback behavior.

Report-only health checks may run on a schedule. Any automation that mutates
`.codex`, broadens permissions, pushes, publishes, deploys, sends messages, or
touches accounts must be explicitly requested as an app automation change and
must use the app automation tooling when available.

## Memory Model

Use file memory for reviewed operating decisions and reports. Memento is retired
from the default control plane, so do not write or verify MCP memory as part of
ordinary self-management. Never store secrets, raw logs, full prompts, or
speculative guesses as verified memory.

## Standard Validation

```powershell
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\anise\.codex\maintenance\scripts\validate-codex-scaffold.ps1 -CodexHome C:\Users\anise\.codex -Json
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoProfile -ExecutionPolicy Bypass -File C:\Users\anise\.codex\maintenance\scripts\codex-p0-integrity-loop.ps1 -Json -ProcessTimeoutSeconds 120
C:\Users\anise\.codex\toolchains\shims\codex.ps1 doctor --json
```

Report-only P0 is acceptable for read-only review passes. Final publication
evidence uses the full P0 loop so cleanup mutation and Scoop health are not
silently skipped.

Do not use `-SkipScoop` for closure. The P0 loop treats skipped Scoop health as
a failed evidence gap.

## Rollback

Rollback is path-specific:

- Config policy: restore the previous `config.d\00-policy.toml`, copy it to
  `.codex\config.d`, regenerate `.codex\config.toml`, then run validator and
  Codex doctor through `toolchains\shims\codex.ps1` or the bundled `codex.exe`.
- Hook behavior: restore `hooks\compact-codex-hook.ps1`, copy it to
  `.codex\hooks`, then run hook smoke plus runtime validation.
- Runtime cleanup: use `codex-runtime-process-cleanup.ps1 -Mode status` before
  any cleanup. Use report-only for uncertain ownership; after explicit cleanup
  authorization, follow `CODEX_STATE_MANAGEMENT.md`: path boundary plus
  reparse-point descendant scan; fail closed on top-level or descendant
  reparse points or scan errors.
