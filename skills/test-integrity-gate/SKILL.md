---
name: test-integrity-gate
description: Mandatory workflow for tasks that create, edit, fix, weaken, skip, review, or rely on tests, fixtures, mocks, snapshots, test utilities, e2e specs, CI test commands, TDD, or validation evidence. Use before test changes and before claiming tests prove correctness.
---

# Test Integrity Gate

Treat Codex-generated or Codex-modified tests as untrusted until they prove
behavioral validity. A passing test is evidence that current code and current
test agree; it is not proof that the test is a valid specification.

## Trigger

Use this skill whenever the task involves tests, TDD, bug reproduction,
regression coverage, fixtures, mocks, snapshots, test utilities, e2e tests,
CI test commands, or when test output is a core completion claim.

## Scope Check

1. Inspect `git status --short` and changed file paths when inside a git
   repository.
2. Classify the test work: feature TDD, bug regression, refactor safety,
   characterization, test maintenance, fixture, snapshot, e2e, or CI command.
3. Preserve unrelated user changes and do not mix unrelated test edits into the
   same implementation slice.

## Required Sequence

For new or materially changed behavior tests:

1. Lock intent in user terms before writing or editing tests.
2. Define the test oracle before product implementation changes.
3. Draft tests only; do not modify production behavior yet.
4. Run the narrow command expected to fail and capture red proof.
5. Confirm the failure matches the intended behavior gap.
6. Implement the smallest production change.
7. Run targeted tests first, then the relevant broader suite and lint/typecheck
   where available.
8. Complete a pollution scan that tries to invalidate the test.
9. Run the adopted `no-mistakes` outer gate for repository validation handoff
   when the work has a suitable Git remote and needs non-self-certified
   verification. Also use repository CI marker checks, PR template
   requirements, or local verifier scripts when they exist.
10. Report tests as evidence only after red proof, green proof, and pollution
    scan are current and coherent.

For pure refactor-safety or characterization tests, state that the oracle is
the existing behavior being preserved and why that behavior is legitimate.

## Test Integrity Record

Create or update `.test-integrity/<branch-or-slice>.md` when the repository
allows durable test-integrity evidence. If the repository forbids new evidence
files, include the same fields in the final report.

Minimum record:

```md
# Test Integrity Record

## Intent

## Behavioral Contract
- Requirement / invariant / bug reproduction:
- Source of truth:
- Out of scope:

## Test Oracle
- Expected observable behavior:
- Why this behavior is correct:
- How the test would fail on the old behavior:
- What would make this test invalid:
- Boundaries intentionally not mocked:
- Mocks/stubs used and justification:

## Red Proof
- Command:
- Expected failure:
- Actual failure excerpt:
- Failure reason matches intent:
- If no, corrective action:

## Green Proof
- Targeted command:
- Targeted result:
- Full relevant suite command:
- Full relevant suite result:
- Lint/typecheck command:
- Lint/typecheck result:

## Pollution Scan
- Could the test pass if the product behavior were still wrong?
- Does the test assert implementation detail instead of behavior?
- Are mocks hiding the real boundary?
- Were snapshots updated?
- Were fixtures changed?
- Were assertions weakened or removed?
- Were tests skipped, marked flaky, or narrowed?
- Was production code changed only for tests?
- Independent invalidation attempted:
- Result:

## Outer Gate
- Command:
- Outcome:
- Not-run reason:
- ask-user findings:

## Waivers
- Waiver:
- Approved by:
- Reason:
- Expiration / follow-up:
```

## Hard Prohibitions

- Do not call a generated or modified test valid because it passes.
- Do not change expectations after implementation just to make tests pass.
- Do not weaken, delete, skip, narrow, or mark flaky tests without explicit user
  approval recorded as a waiver.
- Do not update snapshots as the only assertion.
- Do not mock the behavior being tested.
- Do not add test-only production APIs, flags, environment switches, or
  backdoors without explicit user approval and recorded rationale.
- Do not replace a failed red proof with an easier passing command.
- Do not use unattended approval flags such as `--yes`, `--skip test`, or
  `--skip review` for test-validity gates unless the user grants a run-specific
  written waiver.

## Validity Checks

A new or materially changed test is valid only if all are true:

- It maps to explicit intent, requirement, invariant, bug reproduction, public
  contract, or documented behavior.
- It fails before implementation for the intended reason.
- It passes after implementation without weakening the oracle.
- It would fail if the intended behavior regressed.
- It avoids implementation-detail assertions unless the task is explicitly
  characterization or internal contract testing.
- Mocks, fixtures, snapshots, and test utilities do not define behavior without
  independent justification.
- Current evidence records commands, outcomes, and not-run reasons.

## Escalation

Stop or create an ask-user item when:

- intent is ambiguous;
- a test passes before implementation;
- the red failure is not about the intended behavior;
- satisfying the test requires changing the product contract;
- a snapshot or fixture change defines the new expected behavior;
- no reliable oracle can be established;
- an outer gate returns an ask-user finding.

## no-mistakes Gate Use

Use `%USERPROFILE%\.codex\toolchains\shims\no-mistakes.ps1` for the outer gate from PowerShell/Codex-managed runs.
Treat missing CLI, daemon, repository initialization, remote, credentials, or
gate findings as blockers to report or repair, not as reasons to silently rely
only on local tests.

When already running inside a no-mistakes-spawned gate worktree or agent step,
do not invoke `no-mistakes`, including `--version`, `doctor`, `axi`, `daemon`,
or the managed wrapper. Recursive calls can interfere with the active pipeline;
use project-native checks, scaffold validator output, and fake-binary wrapper
probes instead.

Do not run broad skip flags, unattended approval, or direct `origin` push to
bypass `no-mistakes` for test-related handoff unless the user gives an explicit
run-specific waiver and the waiver is recorded in the Test Integrity Record.
