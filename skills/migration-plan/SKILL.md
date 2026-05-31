---
name: migration-plan
description: Use when planning or executing migrations across code, data, configuration, runtime state, repositories, package managers, APIs, storage, build systems, or workflow policy.
---

# Migration Plan

## Workflow

1. Define old state, target state, invariants, owners, and the smallest reversible slice.
2. Inventory affected files, generated outputs, runtime state, external dependencies, and compatibility contracts.
3. Choose a staged path: prepare, dual-read or compatibility bridge when needed, switch, verify, remove legacy only after proof.
4. Define rollback before mutation. Keep backups, feature flags, or restore steps proportional to the risk.
5. Execute one slice at a time and verify equivalence or intentional change before continuing.

## Risk Checks

- Data and config migrations have parse/validation checks.
- Runtime and workflow migrations preserve user authorization and do not reintroduce retired tools.
- Legacy deletion is delayed until no live reference remains.
- Reports distinguish migrated, quarantined, deferred, and out-of-scope surfaces.

## Exit Evidence

Report migration map, changed surfaces, compatibility checks, rollback path, verification commands, and remaining legacy surfaces.
