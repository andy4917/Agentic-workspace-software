# Project Workflow Chain Protocol

This file defines the Codex-global project workflow-chain preflight and
scaffolding procedure. It applies to project repositories and durable project
artifacts across frontend, backend, data, automation, CLI, extension,
infrastructure, documentation, and integration work.

Frontend has additional quality rules in `docs/codex_frontend_quality_directive.md`.
Those rules extend this protocol; they do not replace it.

## Trigger

Run this protocol when a user asks Codex to modify, build, test, review, repair,
or extend a project repository or durable project artifact.

Do not run it for a tiny read-only question, a single terminal fact, or a task
where the user explicitly says not to scaffold or mutate the project.

## Chain Status

Classify the project workflow chain before implementation:

- `chain_ready`: the project has enough instructions, context, commands,
  contracts, and verification paths for the requested work.
- `chain_partial`: some pieces exist, but requested work would depend on
  missing, stale, ambiguous, or mismatched chain artifacts.
- `chain_missing`: the project has no usable chain for the requested work.
- `chain_not_applicable`: the task is read-only, outside a project repository,
  or explicitly limited to no scaffolding.

Configuration, package installation, MCP registration, or an installed skill is
not enough to mark a chain ready. The chain must be usable in the project.

## Minimum Chain

The smallest durable chain should answer these questions from project files or
repo scripts:

- `project_instructions`: Which project-local instruction file governs agents?
  Prefer `AGENTS.md`; read lower-priority files such as `agent.md` when present.
- `product_or_goal_context`: What is being built, for whom, and what user value
  or operational outcome matters? Use existing docs or scaffold `PRODUCT.md`,
  `README.md`, or a scoped spec when missing.
- `architecture_or_boundaries`: What are the main modules, boundaries, data
  flows, external systems, and ownership limits?
- `commands`: How do agents install, run, build, lint, test, typecheck, format,
  and verify the project using its actual package manager or scripts?
- `contracts`: What public interfaces, schemas, routes, events, component
  contracts, generated files, migrations, or document formats must stay aligned?
- `compatibility_impact`: Which existing hooks, workflow gates, toolchain/MCP
  routes, skills, plugin cache boundaries, scripts, tests, and rollback paths
  could this change affect, duplicate, weaken, or bypass?
- `verification`: Which direct checks prove the requested change? Include
  fallback checks and precise not-run reasons.
- `handoff`: Where should changed behavior, accepted evidence, not-run checks,
  residual risks, and rollback notes be recorded?

## Quality Gate Evidence

For code-affecting work, connect the chain to the project-local Vibe Quality
Gate before implementation:

- `Boundary`: import direction, layer ownership, public APIs, cycles, and
  re-export changes.
- `Contract / SSOT`: canonical helper, type, schema, validator, mapper, shape,
  and generated-output sources.
- `Failure`: allowed error-handling boundary, fallback or retry behavior, and
  failure-path coverage.
- `Simplicity`: nesting, complexity, function size, file size, helper sprawl,
  and dead-code pressure.
- `Verification`: typecheck, lint, tests, boundary checks, edge cases, side
  effects, and precise not-run reasons.

When a TypeScript or JavaScript project has package tooling, prefer one
project-local `quality` command that wraps the existing typecheck, lint, and
test commands. Add ESLint, TypeScript strictness, dependency-cruiser, or CI
enforcement only when that toolchain exists, the project needs it for the active
request, or the user explicitly asks for expansion.

## Domain Additions

Add only the domain pieces relevant to the requested work:

- Frontend/UI: follow `docs/codex_frontend_quality_directive.md`, including
  the official Product Design workflow when exposed, optional Impeccable
  compatibility only when installed, `PRODUCT.md`, `DESIGN.md`, component
  contract, shadcn/components checks when applicable, Storybook or equivalent
  rendered state coverage, and browser/runtime observation when practical.
- Backend/API: identify API contracts, request/response schemas, validation
  layer, auth/permission boundary, persistence boundary, migration workflow,
  integration tests, and service runbook.
- Data/analytics/ML: identify source datasets, schema contracts, lineage,
  privacy constraints, reproducibility command, evaluation metric, and output
  validation.
- CLI/automation/scripts: identify invocation contract, inputs/outputs, dry-run
  or no-op mode when practical, logging, idempotency, rollback, and Windows path
  behavior.
- Browser extensions/apps: identify manifest, permissions, content/background
  boundaries, UI surface, packaging command, and install/runtime verification.
- Infrastructure/deployment: identify environment boundaries, secrets metadata
  without reading secret values, plan/diff command, rollback, and blast radius.
- Documentation/content: identify audience, source of truth, generated outputs,
  render/export verification, and stale-content checks.

## Scaffolding Rule

If the status is `chain_partial` or `chain_missing`, scaffold the smallest
project-local chain needed for the requested work before changing product code.

Acceptable scaffolding examples:

- add or update `AGENTS.md` with project-specific commands and constraints;
- add `PRODUCT.md`, a scoped spec, or a short architecture note when project
  intent is undocumented;
- add `docs/contracts/*`, OpenAPI/schema notes, component contracts, or
  generated-file instructions when contract drift is likely;
- add missing package scripts or documented commands only when they wrap
  existing project tooling and can be verified;
- add a test, Storybook story, fixture, smoke check, or verification script when
  the requested work has no direct proof path.

Avoid broad scaffolding that is unrelated to the active request. Do not install
major frameworks, rewrite project structure, or create heavy gates unless the
user explicitly asks or the project already requires them.

## Reporting

Final reports for project work must include:

- chain status: `chain_ready`, `chain_partial`, `chain_missing`, or
  `chain_not_applicable`;
- scaffolding performed, or why scaffolding was not performed;
- changed surfaces;
- direct checks run;
- checks not run with reasons;
- PM independent verification;
- residual risks and rollback notes;
- status: `complete`, `blocked`, or `continue`.
