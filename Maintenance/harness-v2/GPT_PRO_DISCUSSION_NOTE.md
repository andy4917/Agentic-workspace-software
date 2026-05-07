# GPT Pro Discussion Note

GPT Pro review confirmed.

I agree with the main recommendation: do not keep layering patches onto the
current production hook as the primary design. The correct next step is an
isolated Harness V2 with acceptance tests first.

What I verified:

- The provided review document was read from
  `C:\Users\anise\Downloads\codex_dev_env_remodel_review.md`.
- Current official Codex docs align with the review's key assumptions:
  - hooks are lifecycle surfaces, and Stop can continue/refuse completion
    without treating every response as failure;
  - skills are progressively loaded, so installed does not mean used;
  - AGENTS.md is scoped guidance, not completion authority;
  - subagents are explicit helpers and should remain candidate evidence.
- The live system still reproduces a scope false positive: the user-mentioned
  review file was initially blocked as `path_outside_active_scope`.

Implemented as isolated V2 prototype:

- `HARNESS_V2_DESIGN.md`
- `harness_v2_policy.yaml`
- `harness_v2_acceptance_tests.yaml`
- `Invoke-HarnessV2Acceptance.ps1`
- `MIGRATION_PLAN.md`
- `harness_v2_integrity_compatibility_actions.md`

Discussion points to confirm before production wiring:

1. Should user-mentioned external reference files always be read-only allowed
   unless private material is detected?
2. Should path-scope mismatch be recorded as `path_scope_observed` instead of a
   hard blocker, while secret/auth, destructive side effect, unauthorized
   control-plane mutation, evaluator manipulation, and fake-success shortcuts
   remain `BLOCKED`?
3. Should image generation be permanently excluded from dynamic reproduction
   and direct-evidence gates unless the prompt explicitly asks for executable
   or procedural behavior?
4. Should `DO_NOT_CLAIM_COMPLETE` be represented as a Stop continuation only
   when the assistant is making a completion claim, and otherwise stay silent?
5. Should the first production migration be shadow observation rather than
   direct replacement?

Proposed answer:

Proceed with shadow-mode V2 first. Acceptance tests should be the contract, and
the current V1 hook should be treated as trace material until V2 proves the
normal path is quiet and the reward-hacking path gets no completion authority.
