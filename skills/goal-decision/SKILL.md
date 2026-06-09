---
name: goal-decision
version: 1.0.0
description: Decide whether a user task should become a Codex /goal, stay as a one-off prompt, or be refined first. Use for goal drafting, long-running task triage, benchmark/debug/research/refactor/migration tasks, and requests like “should this be a goal?” or “turn this into a /goal”.
---

# Goal Decision Skill

Use this skill before creating or recommending a Codex `/goal`. Your job is to classify the task, explain the decision briefly, and produce either a strong `/goal` or a better normal prompt.

## Core rule

Use `/goal` only when the task is a durable, evidence-checkable objective whose next step may depend on what Codex learns while working.

Do not use `/goal` merely because the task is large. Use it when there is:

1. a single coherent objective,
2. a verifiable completion condition,
3. an iteration loop or uncertain path,
4. enough repo, data, test, benchmark, log, issue, or source context to check progress,
5. clear constraints and boundaries,
6. a safe stopping condition for success, blockage, user approval, or budget exhaustion.

## Decision classes

Return exactly one of these classes:

- `USE_GOAL`: The task should be converted into a `/goal`.
- `USE_PROMPT`: A normal one-off prompt is better.
- `REFINE_FIRST`: The task may become a Goal, but required completion or verification details are missing.
- `PLAN_FIRST`: The task is broad or architectural enough that Codex should draft a plan first, then convert the approved plan into a Goal.
- `REQUIRE_HUMAN_APPROVAL`: The work includes high-risk operations and should not run autonomously without explicit checkpoints.

## Use `/goal` when

Prefer `USE_GOAL` when most of these are true:

- The task may take many steps or multiple turns.
- The finish line is clear enough to verify.
- The path is uncertain: Codex may need to inspect, run, patch, benchmark, retry, compare, or research.
- The task has a validation loop, such as tests, benchmarks, CI logs, screenshots, evals, generated artifacts, or a final audit report.
- The user would otherwise keep saying “continue,” “try the next fix,” “rerun tests,” or “keep going until done.”
- Failure modes can be handled with a blocked stop condition.

Good examples:

- Reproduce and fix a flaky test.
- Reduce latency below a threshold while keeping tests green.
- Migrate a package or framework while preserving public behavior.
- Investigate a CI failure until fixed or clearly blocked.
- Reproduce a paper, benchmark, or claim set and produce an evidence ledger.
- Optimize prompts against an eval suite until a target score or blocker.
- Implement a PLAN.md with milestone validation.

## Do not use `/goal` when

Prefer `USE_PROMPT` when any of these are true:

- The task is a one-line edit, one-off explanation, simple code review, small refactor, or direct answer.
- There is no meaningful continuation loop.
- Success can be judged immediately from one response.
- The request is a loose backlog or unrelated task bundle.
- The user only wants options, advice, or a draft, not persistent execution.
- The task has no accessible evidence surface.

Examples:

- “Explain this error.”
- “Rename this variable.”
- “Review this function for obvious bugs.”
- “Write a README paragraph.”
- “What does this command do?”

## Refine before Goal

Return `REFINE_FIRST` when the task is Goal-shaped but missing one or more essentials:

- target outcome,
- verification command or artifact,
- acceptable boundaries,
- constraints that must not regress,
- allowed approximation/proxy evidence,
- stop condition for blockers,
- human approval points.

Do not ask more than three clarification questions. If the missing details can be inferred safely, make conservative assumptions and label them.

## Plan before Goal

Return `PLAN_FIRST` when the objective is coherent but too broad to safely execute directly. This is common for:

- new product builds,
- major architecture changes,
- multi-module migrations,
- ambiguous UX implementation,
- large research projects without a claim inventory,
- any task where milestones must be approved before execution.

Output a `/plan` prompt or a plan-producing normal prompt. Do not output a final `/goal` unless the user supplied enough detail to make completion auditable.

## Human approval required

Return `REQUIRE_HUMAN_APPROVAL` when the task includes actions that should not proceed autonomously, including:

- production deploys,
- destructive data migrations,
- deletion or irreversible writes,
- credential, secret, billing, access-control, or permission changes,
- legal, medical, financial, security, or compliance-sensitive changes,
- changes affecting customer data,
- broad dependency upgrades with unknown blast radius,
- any command likely to mutate external systems.

In this case, propose a Goal only if it includes explicit approval gates before high-risk actions. Otherwise propose a safer investigation-only prompt.

## Scoring rubric

Score each dimension from 0 to 2:

- `objective_clarity`: Is there one coherent end state?
- `verification_surface`: Are tests, benchmarks, logs, artifacts, or source evidence available?
- `iteration_need`: Does progress require inspect-run-change-check loops?
- `scope_boundaries`: Are files, systems, tools, and constraints bounded?
- `autonomy_safety`: Can Codex continue safely without risky irreversible actions?

Decision guide:

- 8-10 and no high-risk blocker: `USE_GOAL`
- 5-7 with missing verification or constraints: `REFINE_FIRST`
- 5-7 with broad scope needing milestones: `PLAN_FIRST`
- 0-4 with immediate or simple task: `USE_PROMPT`
- Any high-risk autonomous action: `REQUIRE_HUMAN_APPROVAL`

The score is a guide, not a substitute for judgment.

## Required output format

When asked to decide, respond in this structure:

```text
Decision: <USE_GOAL | USE_PROMPT | REFINE_FIRST | PLAN_FIRST | REQUIRE_HUMAN_APPROVAL>
Confidence: <High | Medium | Low>
Why: <1-3 concise sentences>
Evidence surface: <tests/benchmarks/logs/artifacts/source docs/none>
Missing pieces: <none or concise list>
Recommended next input:
<copyable command or prompt>
```

If the answer is `USE_GOAL`, the recommended next input must be a complete `/goal` command.

If the answer is `USE_PROMPT`, the recommended next input must be a normal prompt, not `/goal`.

If the answer is `REFINE_FIRST`, ask for only the missing details that materially affect the Goal. Also provide a best-effort draft marked `Draft only` when safe.

If the answer is `PLAN_FIRST`, provide a `/plan` command or a plan request that can later become a Goal.

If the answer is `REQUIRE_HUMAN_APPROVAL`, provide a safer Goal or prompt with explicit approval gates.

## Strong `/goal` template

Use this template for `USE_GOAL`:

```text
/goal <desired end state>, verified by <specific commands, tests, benchmarks, artifacts, or evidence>, while preserving <constraints and non-regressions>. Use only <allowed files/tools/data/systems>. Work in checkpoints: after each iteration, record <change made>, <evidence observed>, and <next best action>. Stop when <success condition> is met, or if <blocked condition/budget/risk gate> occurs; then report <attempted paths>, <evidence>, <remaining uncertainty>, and <next input needed>.
```

Keep `/goal` text compact. If the objective would exceed CLI limits or become unreadable, instruct the user to put detailed criteria in a file such as `GOAL.md`, `PLAN.md`, or `REPRODUCTION.md`, then set a shorter Goal that points to that file.

## Goal quality checklist

Before outputting a `/goal`, verify that it includes:

- outcome,
- verification surface,
- constraints,
- boundaries,
- iteration policy,
- success stop condition,
- blocked stop condition,
- approval gates for risky steps,
- honest handling of uncertainty.

If any item is missing and cannot be safely inferred, do not return `USE_GOAL`; return `REFINE_FIRST` or `PLAN_FIRST`.

## Examples

### Performance optimization

Input:
“Checkout p95가 180ms인데 120ms 아래로 낮추고 싶어.”

Output:
```text
Decision: USE_GOAL
Confidence: High
Why: 목표가 정량적이고, 벤치마크와 correctness suite로 반복 검증할 수 있습니다.
Evidence surface: checkout benchmark, correctness test suite
Missing pieces: benchmark command name if not discoverable from repo
Recommended next input:
/goal Reduce checkout p95 latency below 120 ms, verified by the checkout benchmark, while keeping the correctness suite green. Use only checkout-service code, benchmark fixtures, and related tests. Work in checkpoints: after each iteration, record the change, benchmark result, test result, and next experiment. Stop when p95 is below 120 ms and correctness passes, or if the benchmark cannot run or no valid optimization path remains; then report attempted paths, evidence, blockers, and next input needed.
```

### One-off explanation

Input:
“이 TypeScript 에러가 무슨 뜻이야?”

Output:
```text
Decision: USE_PROMPT
Confidence: High
Why: 한 번의 설명으로 해결되는 질의이며 지속 목표나 반복 검증 루프가 필요하지 않습니다.
Evidence surface: compiler error text
Missing pieces: error text if not provided
Recommended next input:
Explain this TypeScript error, identify the likely root cause, and suggest the smallest safe fix. Use the provided error text and relevant code only.
```

### Broad migration

Input:
“앱을 Next.js 최신 구조로 전부 마이그레이션해줘.”

Output:
```text
Decision: PLAN_FIRST
Confidence: Medium
Why: 목표는 Goal 후보이지만 범위와 검증 기준이 넓어 바로 실행하면 드리프트 위험이 큽니다. 먼저 영향 범위, 마일스톤, 검증 명령, 롤백 기준을 계획해야 합니다.
Evidence surface: build, tests, route-level smoke checks, visual checks
Missing pieces: target Next.js version, protected behavior, test commands, rollout boundary
Recommended next input:
/plan Inspect the current app structure and propose a scoped Next.js migration plan with milestones, files affected, validation commands, rollback strategy, and risks. Do not modify files yet.
```

### Risky production work

Input:
“프로덕션 DB 스키마 바꾸고 배포까지 계속 진행해.”

Output:
```text
Decision: REQUIRE_HUMAN_APPROVAL
Confidence: High
Why: 프로덕션 데이터와 배포는 irreversible risk가 있으므로 무인 반복 실행에 맡기면 안 됩니다. Goal을 쓰더라도 조사, dry-run, migration diff 작성, 승인 대기까지만 허용해야 합니다.
Evidence surface: migration diff, dry-run output, staging validation, rollback plan
Missing pieces: approval policy, staging command, rollback command
Recommended next input:
/goal Prepare a production database migration proposal, verified by local and staging dry-run outputs, while making no production changes. Use only schema files, migration tooling, staging validation, and docs. Work in checkpoints: inspect current schema, draft migration, run non-production validation, and produce rollback instructions. Stop before any production write, deploy, or credential change and request explicit human approval with the evidence gathered.
```

## Final behavior rules

- Prefer a normal prompt when a Goal would create unnecessary autonomy.
- Prefer a Goal when the user would otherwise need to repeatedly ask Codex to continue a validation loop.
- Never mark a Goal as suitable without a verification surface.
- Never hide uncertainty; encode uncertainty and blockers into the stop condition.
- Never allow high-risk external mutations without explicit approval gates.
- Keep the recommended command copyable.
