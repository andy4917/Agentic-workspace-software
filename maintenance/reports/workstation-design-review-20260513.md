# Workstation Design Review - 2026-05-13

## Scope

Reviewed the public-safe `.codex` workstation control plane, app/plugin support
surfaces, and final operating-flow design after the workstation maintenance
normalization work.

Inspected surfaces:

- `README.md`
- `AGENTS.md`
- `maintenance/WORKSTATION_CONTROL_RUNBOOK.md`
- `maintenance/WORKSTATION_MAINTENANCE.md`
- `maintenance/AGENT_TOOL_REQUIREMENTS.md`
- `maintenance/MCP_RUNTIME_STATUS.md`
- `maintenance/NAMING_CONVENTION.md`
- `maintenance/SUBAGENT_DELEGATION_CHARTER.md`
- `maintenance/MULTI_AGENT_WORKFLOW_STATUS.md`
- `maintenance/CHROME_DEVTOOLS_MCP_OBSERVER.md`
- `maintenance/scripts/*.ps1`
- patched Chrome/browser-use plugin browser client scripts
- tracked file list and GitHub remote state

## Design Finding

No blocking design issue remains in the reviewed scope.

The current design is coherent:

- public-safe managed source is versioned in GitHub;
- live private runtime state remains ignored;
- Workstation PM responsibilities are explicit;
- workstation tasks start with surface classification and risk levels;
- subagents are evidence producers, not completion authority;
- bundled tools are preferred over local duplicates;
- local-chain tools are explicit and wrapper-backed;
- Chrome DevTools MCP is off by default and toggled only for frontend browser
  observation;
- completion requires changed surfaces, direct evidence, not-run reasons, and
  residual risks.

## Correction Applied

Three mutable `latest` report files were still tracked even though `.gitignore`
now classifies mutable latest outputs as local evidence:

- `maintenance/reports/codex-home-maintenance.latest.json`
- `maintenance/reports/dev-environment-inventory.latest.json`
- `maintenance/reports/dev-environment-inventory.latest.md`

They were removed from Git tracking with `git rm --cached`. The local files were
not deleted.

The temporary GitHub clone-check directory
`%USERPROFILE%\Documents\Codex\tmp-agentic-workspace-clone-check` was moved to
the Windows Recycle Bin after path validation.

## Verification

Checks run:

- `git status -sb`
- `git ls-files` review for tracked sensitive/runtime paths
- tracked large-file review
- PowerShell parser check for `maintenance/scripts/*.ps1`
- `node --check` for patched Chrome and browser-use `browser-client.mjs`
- `chrome-devtools-mcp-toggle.ps1 status`
- `codex mcp list`
- `check-toolchain-sources.ps1`
- `codex_agent_harness.py verify`
- `git diff --check`
- ASCII check for operational docs
- GitHub API check for repository description and remote state

Result:

- harness verification passed;
- toolchain source check passed with zero failures and zero warnings;
- Chrome DevTools MCP final state is `state=off`;
- no tracked secret/runtime filename pattern was found;
- the only secret-like content match was the private-key detection regex in
  `tools/codex-log-db.py`, not a secret value.

## Not Checked

- Secret contents were not read.
- SQLite/log contents were not inspected.
- Browser state, sessions, caches, and memories were not published or audited
  beyond path/tracking boundaries.
- A full machine inventory was not rerun; this was a design and tracked-surface
  review, not a byte-level filesystem audit.

## Residual Risks

- The GitHub repository is public, so future changes must continue to enforce
  the public-safe boundary.
- SSH remote usage remains unresolved; GitHub operations currently use `gh`
  HTTPS authentication.
- Patched bundled plugin/runtime assumptions should be rechecked after Codex
  Desktop updates.
- Active sessions may still require reload before newly configured MCP tools are
  exposed.

## Status

`complete` for the reviewed workstation-control design scope.
