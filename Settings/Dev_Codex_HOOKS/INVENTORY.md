# Inventory

- `pre_turn_active_contract.yaml`: active contract hook config.
- `pre_command_guard.yaml`: command guard hook config.
- `pre_response_checklist.yaml`: pre-response checklist hook config.
- `retry_invalidation.yaml`: retry invalidation hook config.
- `completion_gate.yaml`: completion gate hook config.
- `post_turn_state_register.yaml`: post-turn state register hook config.
- `codex-ssot-hook.ps1`: shared executable hook runner, including runtime capability receipt generation, task classification and need resolution receipts, append-only `tool_usage_event.v2` observation, hook invocation event IDs, parent lineage preservation, Stop-only required-route validation, future timestamp rejection, explicit clock skew, gate-issued completion receipt generation, and current-task repair classification for isolated Harness V2 and PM decision ledger surfaces.
