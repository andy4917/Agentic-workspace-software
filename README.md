# Agentic Workspace Software

This repository records the managed `.codex` workstation control surface:
global operating policy, agent workflows, maintenance runbooks, toolchain
wrappers, verification scripts, patched runtime notes, and handoff documents
that help diagnose workstation-level agent behavior.

It is intended to make global Codex changes reviewable from outside the local
machine. It is not the live Codex runtime itself and it is not a secret store.

## Scope

Tracked here:

- `.codex` agent operating guidance and workflow policy.
- Maintenance runbooks and workstation control-plane documentation.
- Toolchain wrapper source and verification scripts.
- MCP, plugin, skill, hook, and runtime troubleshooting records when they are
  safe to publish.
- Public-safe patches, reports, and handoff material needed to identify
  failures, drift, or recurring operational issues.

Not tracked here:

- `config.toml`, auth files, credentials, tokens, private keys, session logs,
  SQLite state, browser state, local caches, and other live private runtime
  files.
- Project repositories outside the `.codex` workstation scope unless a user task
  explicitly targets them.
- Generated or sensitive local state that cannot be reviewed safely in public.

## Operating Contract

This repository exists for inspection and maintenance of the workstation control
plane. Changes should name:

- affected workstation surface;
- source class and active path when a tool or runtime is involved;
- dependency chain;
- verification commands;
- not-run reasons;
- residual risks;
- rollback or recovery notes.

For workstation management, follow
`maintenance/WORKSTATION_CONTROL_RUNBOOK.md` and
`maintenance/WORKSTATION_MAINTENANCE.md` before changing active runtime,
toolchains, logs, trust settings, hooks, or external publishing surfaces.
For cache, log, memory, folder, file, and managed-source/live-runtime sync
behavior, use `maintenance/CODEX_STATE_MANAGEMENT.md`.
For Codex self-management, full-access default permission posture, and managed
automation review, use `maintenance/CODEX_SELF_MANAGEMENT_LOOP.md`.
For product-repository spec/architecture governance adapted from the Vibe
SpecOps pack, use `maintenance/SPECOPS_OPERATING_MODEL.md`.

Use `maintenance/WORKSTATION_LAYERING.md` to choose the smallest verification
layer. In particular, `repo-verify` is the public-safe CI path for tracked
managed source, while full local `verify` remains the runtime-heavy workstation
proof path.

## Review Use

External review should focus on:

- hidden coupling between bundled tools, local wrappers, and MCP packages;
- unsafe or unclear active-runtime changes;
- missing evidence for completion claims;
- hook or workflow behavior that weakens validation;
- stale patched plugin/runtime assumptions;
- accidental inclusion of private local state.

Passing checks are evidence, not completion authority. The PM session remains
responsible for connecting user intent, changed surfaces, direct evidence,
checks not run, and remaining risks.
