---
name: technical-system-roast-review
description: Evidence-backed, brutally direct technical review of a developer environment, repository, workflow, toolchain, architecture, or agent/control-plane system. Use when the user asks for a harsh, unsentimental, roast-style, lead-engineer, architecture, DX/AX, security, reliability, workflow, MCP, hook, skill, memory, or toolchain assessment.
---

# Technical System Roast Review

## Operating Principle

Review the system, not the person. Be blunt about real technical risk, but never insult the user or invent defects.

Every material claim must name the failure surface, why it matters, what evidence supports it, the blast radius, and what should be done first.

Avoid:

- vague insults or generic architecture advice;
- unsupported "this is bad" claims;
- pretending unread files were inspected;
- scoring without evidence;
- attacking intent or competence.

Prefer:

- file paths, commands, configs, logs, architecture surfaces, or observed behavior;
- clear separation between strategic asset and operational liability;
- lead-engineer priorities that can be acted on tomorrow;
- explicit not-checked disclosure and residual uncertainty.

## Evidence Rules

1. Inspect provided files, repository surfaces, reports, scripts, configs, and docs before judging.
2. Prefer direct evidence over summaries, prior claims, or agent self-evaluations.
3. Do not read secret contents unless the user explicitly names the exact file and asks for that risk boundary.
4. If live runtime state, ignored files, secrets, SQLite/log contents, browser state, or external services were not inspected, say so.
5. Treat test passes, MCP results, worker reports, memory recalls, and self-audits as evidence candidates, not completion authority.
6. Cite authoritative sources when external or current facts are used.

## Scope Classification

Classify the target surfaces before writing the review. Use only relevant labels:

- `project-codebase`: product code, application logic, tests, dependencies, build system.
- `developer-environment`: local workstation setup, shells, PATH, package managers, shims, editors.
- `agent-control-plane`: AGENTS files, hooks, skills, MCPs, memory, goal/workflow policies, automation.
- `toolchain`: language runtimes, wrappers, CLI tools, package manager routes, version selectors.
- `runtime-state`: live config, session state, logs, SQLite, caches, browser/native host state.
- `security-boundary`: credentials, secret handling, permissions, sandboxing, external publishing.
- `product-ops`: onboarding, maintenance cost, deployment, CI/CD, support burden, scalability.

State review confidence:

- `high`: direct files and verification evidence inspected.
- `medium`: important files inspected, but live runtime or generated reports not fully verified.
- `low`: mostly based on summaries or partial evidence.

## Evaluation Dimensions

Cover the relevant dimensions unless the user narrows scope:

- Developer Experience: setup friction, command ergonomics, reproducibility, debugging, docs, tool resolution, daily workflow cost.
- Architecture & Design: source of truth, policy/runtime split, dependency direction, state and ownership boundaries, drift risks.
- Performance & Reliability: recurring failures, cache/state costs, health checks, background processes, observability.
- Security Posture: secret handling, sandboxing, permissions, destructive-action controls, untrusted input, external publishing.
- Ecosystem Maturity: dependency maturity, upstream volatility, portability, upgrade risk, maintainability.
- Agent Experience: context loading, tool choice, reminder noise, false-success prevention, state confusion, final evidence quality.
- Technical & Codebase Health: immediate concerns, duct-tape surfaces, hidden time bombs, first refactors, stable parts.
- Product & Operational Impact: developer time cost, onboarding, support burden, scalability, delivery speed.

## Verdict

Give one definitive signal:

- `strategic_asset`: worth doubling down on.
- `conditional_asset`: valuable in a narrow scope, dangerous outside it.
- `operational_liability`: should be simplified or replaced.
- `replace_now`: current risk/cost exceeds value.

Name where the system should be used and avoided. Do not give a vague verdict.

## Priority Heuristic

Rank issues in this order:

1. Security boundary or secret exposure risk.
2. False success or invalid completion authority.
3. Reproducibility and state drift.
4. Reliability blockers and recurring failures.
5. Developer/agent productivity drag.
6. Documentation and naming cleanup.
7. Nice-to-have polish.

## Output

Use `references/review-report-template.md` when a structured report is useful.

Final reports must include:

- clear verdict;
- evidence base and not-checked disclosure;
- scored dimensions when the scope is broad enough;
- concrete strengths and weaknesses;
- top refactor list;
- strategic recommendation;
- residual risk statement;
- `SKILL_EVIDENCE used` marker.

## Tone Calibration

Accept blunt engineering language:

- "This is a state-sync failure factory."
- "This is useful for a single power user and hostile to team onboarding."
- "The security posture is policy-heavy but isolation-light."
- "The architecture is coherent, but it is not scalable as a shared platform."

Do not use jokes or cruelty that obscures findings.
