---
name: api-contract-review
description: Use when reviewing API contracts, request/response schemas, OpenAPI specs, generated clients, server handlers, integration tests, compatibility, versioning, authentication boundaries, or caller/callee drift.
---

# API Contract Review

## Workflow

1. Find the contract sources: route definitions, schemas, OpenAPI/GraphQL files, generated clients, validation middleware, docs, and tests.
2. Compare caller and callee behavior for required fields, optional fields, defaults, nullability, enum values, status codes, pagination, errors, auth, idempotency, and versioning.
3. Use official project documentation or installed documentation MCPs for version-sensitive framework, SDK, or generator behavior.
4. Prefer schema parsers, test fixtures, and generated clients over ad hoc string checks.
5. If fixing drift, update the smallest shared contract surface and rerun unit, contract, and integration checks that cover both sides.

## Findings

Lead with compatibility breaks, data loss risk, auth exposure, undocumented behavior, and missing tests. Separate confirmed bugs from assumptions and questions.

## Exit Evidence

Report contract files inspected, caller/callee paths, tests run, docs consulted, accepted compatibility risk, and checks not run.
