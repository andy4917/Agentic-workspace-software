# Codex Self-Management And SpecOps Redesign

Date: 2026-05-31

## Inputs

- `C:\Users\anise\Downloads\codex_self_management_loop_proposal.md`
- `C:\Users\anise\Downloads\codex_vibe_spec_ops_pack.zip`
- Current managed-source repository: `C:\Users\anise\Documents\Codex`
- Current live runtime root: `C:\Users\anise\.codex`

## Decisions

- Reuse `C:\Users\anise\Documents\Codex` as the CodexOps managed-source
  repository instead of creating a separate repo.
- Keep `C:\Users\anise\.codex\config.toml` as active runtime truth, with
  public-safe policy source mirrored in `config.d\00-policy.toml`.
- Set the local default permission posture to full access:
  `sandbox_mode = "danger-full-access"`, `approval_policy = "never"`, and
  `[windows].sandbox = "elevated"`.
- Treat the zip's SpecOps pack as a capability pack and template set, not a
  wholesale install into active `.agents`, `.codex`, or `.github` directories.

## Implemented Surfaces

- `maintenance\CODEX_SELF_MANAGEMENT_LOOP.md`
- `maintenance\SPECOPS_OPERATING_MODEL.md`
- `maintenance\AGENT_TOOL_REQUIREMENTS.md`
- `maintenance\templates\specops\*.md`
- `automations\codex-self-management-review\automation.toml`
- `config.d\00-policy.toml`

## Risk Notes

- Full-access default increases local execution blast radius. The compensating
  controls are direct validation, scoped destructive actions, secret avoidance,
  managed/live sync checks, and final evidence reporting.
- The SpecOps GitHub Action from the zip was not enabled. It references a
  moving external action interface and must be verified against official current
  documentation before use.
- The new self-management automation file is managed-source draft only; it is
  not evidence that the Codex app has scheduled a live automation.

## Verification Plan

- Parse live `config.toml` through `codex doctor --json`.
- Run `validate-codex-scaffold.ps1 -Json`.
- For read-only midpoint review, run `codex-p0-integrity-loop.ps1 -ReportOnly -Json`.
- For final publication evidence, run `codex-p0-integrity-loop.ps1 -Json`
  without `-SkipScoop` so Scoop health and cleanup mutation evidence are current.
- Confirm managed/live SHA sync for live-called scripts, hook, and policy
  fragment.
