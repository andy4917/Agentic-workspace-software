# Worker-Watcher Normalized Handoff

This is managed source for delegated worker integrity. It is not active runtime
configuration, not a hook, and not completion authority.

## Operating Rule

Non-trivial worker dispatch requires at least one independent watcher by default.
Raw worker output is not PM-ready until normalized. Worker complete is not PM complete.
Watcher CLEAN is not PM complete.

```text
PM Goal
  -> Progress Ledger
  -> Worker Dispatch
      -> Worker Result
      -> Watcher Dispatch
          -> clean-all-slop read-only review of the immediately previous worker or PM turn
          -> WATCHER_REPORT
      -> Result Normalizer
          -> NORMALIZED_WORKER_PACKET
  -> PM_MERGE_DECISION
  -> PM Independent Verification
  -> Goal Integrity Gate
```

## Required Artifacts

- `NORMALIZED_WORKER_PACKET`: evidence-first packet extracted from worker output.
- `WATCHER_REPORT`: read-only integrity review using `clean-all-slop`.
- `WATCHER_NOT_USED`: required when a watcher is omitted.
- `PM_MERGE_DECISION`: PM decision to accept, rework, reject, quarantine, or continue.

## Watcher Default

The default watcher role is `OBS-Watcher`. It uses `clean-all-slop` to attack
claims, validation, instruction compliance, hidden fallback, contamination,
reward hacking, and unsupported success language. It does not repair.

## Merge Rules

- Raw worker output is noise until normalized.
- Normalized output is candidate evidence only.
- Watcher findings are candidate evidence only.
- PM merge requires accepted claims, rejected claims, changed surfaces, checks
  run, checks not run, residual risks, and a PM recheck plan.
- PM final completion still requires the final goal audit.

## Watcher Omission

When a watcher cannot be dispatched, record `WATCHER_NOT_USED` before merge.
Impact on confidence must be `normal`, `degraded`, or `blocked`. High-risk
surfaces without a watcher should default to degraded or blocked assurance.

## Adoption Status

Accepted as managed source for the Codex workstation control plane. Hook support
may enforce parts of this later, but this document alone does not mutate hooks.
