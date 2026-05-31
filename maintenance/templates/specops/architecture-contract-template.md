# Architecture Contract

Last Updated: <YYYY-MM-DD>

## System Boundary

Define what this system owns and does not own.

## Domain Boundaries

| Domain | Responsibility | Owns Data | Must Not Know About |
|---|---|---|---|
|  |  |  |  |

## Dependency Direction

Core rule:

- Domain/application policy must not depend on UI, database, framework,
  transport, or vendor SDK details.
- Infrastructure adapters may depend inward.

```text
UI / API / Framework
        |
        v
Application Use Cases
        |
        v
Domain Model / Business Rules
        ^
Infrastructure Adapters depend inward through interfaces
```

## Data Ownership

| Entity/Table/Collection | Owner Domain | Write Path | Read Path | Migration Risk |
|---|---|---|---|---|
|  |  |  |  |  |

## Scalability Contract

| Area | Current Assumption | Limit | Required Upgrade Trigger |
|---|---|---|---|
| DB queries |  |  |  |
| Background jobs |  |  |  |
| Cache |  |  |  |
| File storage |  |  |  |
| External APIs |  |  |  |

## Reliability Contract

- Idempotency:
- Retry:
- Timeout:
- Fallback:
- Rollback:

## Observability Contract

- Required logs:
- Required metrics:
- Required traces:
- Required alerts:

## Prohibited Shortcuts

| Shortcut | Why Prohibited | Safer Alternative |
|---|---|---|
|  |  |  |

