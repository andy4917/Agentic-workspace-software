# Codex SSOT Naming And Organization Plan

Generated: 2026-05-31

## Scope

This packet covers the user concern that `C:\Users\anise\.codex` is the live
source of truth while `C:\Users\anise\Documents\Codex` still contains old-looking
managed-source files from 2026-05-26. It also records the applicable findings
from `gruhn/awesome-naming` for workstation workflow naming and organization.

## Current SSOT Model

- `C:\Users\anise\.codex` is the live Codex runtime root and `CODEX_HOME`.
- `C:\Users\anise\Documents\Codex` is the reviewable managed-source repository
  for policy, scripts, runbooks, generated reports, and scaffold changes.
- Live runtime state is proven by current config, process state, manifests,
  script output, and tests under `.codex`, not by old managed-source file dates.
- Managed-source files with old modification dates are not automatically wrong,
  but they must be classified before being trusted or removed.

## Direct Evidence

- Managed repo inspection found the SSOT split already stated in `AGENTS.md`.
- Live runtime inspection found current `.codex` config and process manifests
  under the runtime root.
- `gruhn/awesome-naming` was cloned read-only to the temp directory and its
  tracked files were reviewed: `README.md`, `CONTRIBUTING.md`, and `LICENSE`.
- The README link inventory had 98 unique links. 96 returned successful HTTP
  responses. 2 returned HTTP 403 from the remote hosts:
  `Cyber hygiene` and `Optimistic UI`.
- Computer Use was attempted for direct Windows evidence in this turn, but the
  `node_repl` transport closed. No UI automation fallback was used.

## Awesome Naming Findings

Useful names are concrete when they describe observable behavior. For this
workstation, the applicable vocabulary is:

- `root`, `tree`, `leaf` for real hierarchy or process ownership.
- `adapter`, `facade`, `wrapper`, and `shim` for boundary translation.
- `sandbox` for isolated work that cannot mutate the active runtime by accident.
- `canary` and `heartbeat` for active liveness and regression signals.
- `breadcrumb` for intentional audit traces.
- `queue`, `bottleneck`, and `technical-debt` for workflow diagnosis.
- Avoid vague operational names such as `magic`, `god`, `spaghetti`, or joke
  names when a concrete failure class exists.

## Already Applied

- `maintenance/NAMING_CONVENTION.md` already defines source classes such as
  `official-bundle`, `app-bundle-bin`, `local-wrapper`, `local-chain`,
  `runtime-cache`, `quarantine-archive`, and `managed-install-record`.
- `AGENTS.md` already separates the live runtime root from the managed-source
  repository.
- The close-lifecycle cleanup work already records app-server, watcher,
  managed-root, duplicate-root, and orphan-process checks.
- The P0 loop already refreshes manifests from fresh runtime evidence instead
  of treating old reports as completion proof.

## Applied In This Pass

- Added an AGENTS rule that file age in the managed-source repo is not live
  runtime truth until the surface is classified and linked to current evidence.
- Mirrored the same classification rule into the compact live bootstrap at
  `C:\Users\anise\.codex\AGENTS.md`.
- Added behavioral naming rules so public naming patterns are used only when
  they map to observable lifecycle or boundary behavior.
- Narrowed the Computer Use wording in the P0 loop: Windows screen and
  non-Codex app evidence is allowed when the tool works, but Codex Desktop app
  and Codex CLI input automation remain out of bounds.
- Patched runtime cleanup so duplicate managed roots are report-only during
  watch mode unless explicitly opted in. This avoids killing stable roots when
  a short-lived replacement root appears.
- Patched `ensure-watch` reporting so it exposes the effective watcher flags
  from the running watcher instead of echoing only the current invocation's
  requested flags.
- Patched scaffold validation so it enforces singleton/no-orphan behavior for
  observed roots and active watcher state, not always-on presence for every
  registered MCP root.
- Patched live runtime hygiene classification so app state, config state,
  database state, credential state, quarantine state, and forbidden active roots
  are explicit; uncategorized top-level runtime extras now fail validation.
- Recycled `C:\Users\anise\.codex\vendor_imports` after confirming there were
  no active config references or non-self process references. The first recycle
  attempt failed because Git fsmonitor was watching
  `C:\Users\anise\.codex\vendor_imports\skills`; `codex-home-maintenance.ps1`
  now stops fsmonitor daemons under a transient root before archive+Recycle.
- Refreshed Scoop bucket metadata. `scoop status` now reports
  `Scoop is up to date` and `Everything is ok`; `scoop checkup` reports no
  problems. `C:\Users\anise\scoop\apps\codex\current` is absent because `codex`
  is not installed as a Scoop app in the current environment.

## Organization Plan

1. Classify 2026-05-26 managed-source surfaces as active managed source,
   historical evidence, source template, runtime output, quarantine candidate,
   or contamination candidate.
2. Keep `.codex` as live runtime evidence and `Documents\Codex` as tracked
   managed-source evidence; sync only narrow runtime copies that scripts call
   directly.
3. Replace vague active names with concrete source-class or failure-class names.
4. Keep reports as evidence packets, but make scripts and manifests the
   repeatable closure loop.
5. For close-button behavior, use user-performed close actions plus post-close
   process evidence, or non-Codex Windows UI evidence when Computer Use is
   available.
6. Quarantine rather than permanently delete old-looking surfaces until live
   linkage and rollback impact are checked.

## Residual Risks

- Computer Use direct screen evidence was not available in this turn because
  the node-backed transport closed.
- Old managed-source surfaces may still need one-by-one classification before
  a full organization cleanup can safely remove or quarantine them.
- Remote awesome-naming links with HTTP 403 cannot be independently inspected
  without a different access path.
