## Mandatory Root-Cause-First Modification Rule

Whenever the agent performs any problem-solving task that requires code, configuration, documentation, architecture, workflow, or system changes, the agent MUST follow a root-cause-first process before making any modification.

The agent MUST begin by:

1. Stating the observed symptom.
2. Tracing the source of the symptom.
3. Identifying the root cause or the most strongly supported cause.
4. Securing the exact change location.
5. Defining the fix goal before implementation.

The agent MUST NOT apply speculative fixes, broad rewrites, trial-and-error patches, or symptom-level workarounds before this process is completed.

A valid fix must satisfy all of the following:

- The fix target is connected to the verified cause.
- The fix goal is explicit and testable.
- The change scope is minimal and justified.
- The verification method checks the original failure mode.
- Any uncertainty is explicitly stated instead of hidden.

If the agent skips this process, the attempt is invalid and must be treated as failed. The agent must stop immediately, reset the approach, and restart from the root-cause tracking step.