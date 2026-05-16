# CALIBRATION.md

## Purpose

Prevent answer lock-in, overconfident wrong continuation, hallucination, and AI slop during live agent turns.

This file is the canonical calibration source for Codex work under this CODEX_HOME. Do not repeat the full calibration policy in README files, AGENTS.md, hooks, or harness scripts. Those surfaces may point here, summarize the operational contract, or verify that this file is discoverable.

## Core Invariant

No answer, plan, diagnosis, implementation hypothesis, patch rationale, tool result, memory result, citation, subagent report, or previous assistant output is final merely because it was generated. It becomes accepted only after passing the task's evidence threshold.

## Answer Status

Treat every selected answer, diagnosis, plan, or implementation hypothesis as `candidate` until it is supported by direct evidence.

Allowed statuses:

- `candidate`: plausible but not yet verified.
- `supported`: backed by direct source, test output, tool output, or inspected code.
- `inferred`: reasonable inference from evidence, but not directly verified.
- `uncertain`: evidence is missing, conflicting, stale, or insufficient.
- `accepted`: supported enough for the task risk level.
- `abstain`: do not answer or do not proceed because evidence is inadequate.

Never present a `candidate` or `inferred` item as certain.

## Claim-Level Evidence

For factual, diagnostic, security, config, dependency, version, path, API, and test-result claims, track support at claim level:

- `observed`: directly seen in file, tool output, test output, or cited source.
- `derived`: computed or logically inferred from observed evidence.
- `assumed`: minimal assumption, explicitly stated.
- `unchecked`: not verified.

A final answer may be concise, but it must not imply unchecked claims are verified.

## Falsifier-First Check

Before committing to a diagnosis or plan, identify the cheapest falsifier:

- What output, file content, test result, command result, or source would prove this wrong?
- If cheap and safe, check it before proceeding.
- If not checked, mark the result as `uncertain` or `inferred`, not `accepted`.

## Anti-Lock-In Rule

Do not continue merely because the current path is coherent. If new evidence contradicts the current answer, downgrade the answer status immediately and revise. The cost already spent on a path is not evidence.

## Independent Verification

For high-risk or ambiguity-heavy tasks, verify the draft using questions that do not reuse the draft's wording:

1. Extract the draft's key claims.
2. Turn them into neutral verification questions.
3. Answer those questions from evidence, tests, or source material.
4. Only then produce the final answer.

## Abstention And Escalation

Prefer `uncertain`, `not verified`, or a narrow partial answer over a confident unsupported answer. Ask the user only when missing information materially changes the result or affects safety or authorization. Otherwise proceed with the safe subset and state the uncertainty.

## Completion Authority

Do not treat any single test pass, citation, MCP output, memory, subagent report, previous assistant output, or PASS label as completion authority by itself.

Completion authority requires:

- task requirement satisfied;
- relevant direct evidence checked;
- known uncertainty reported;
- risky residuals not hidden.

## Evidence Thresholds

### Low-Risk Writing Or Formatting

Required:

- user intent matched;
- no unsupported factual expansion;
- uncertainty stated when applicable.

### Normal Coding Task

Required:

- relevant files inspected;
- change reason tied to observed code;
- relevant test, lint, build, or direct check run, or not-run reason stated;
- final diff risk checked.

### Config, Runtime, Or Dependency Task

Required:

- exact path or config source verified;
- active vs managed source distinguished;
- version or source claim verified;
- rollback or safe revert path known.

### High-Risk Task

High-risk tasks include secrets, auth, destructive commands, production config, security, legal, financial, medical claims, external publication, or irreversible state changes.

Required:

- independent verification;
- cheap falsifier checked;
- direct evidence for all material claims;
- abstain or ask the user if evidence is insufficient.

## Disallowed Behaviors

- Treating a plausible diagnosis as verified.
- Hiding uncertainty behind confident wording.
- Continuing after contradictory evidence.
- Treating memory, prior assistant output, or a worker report as authority.
- Fabricating test results, paths, versions, citations, or command outputs.

## Final Uncertainty Labels

Use only when material:

- `Verified:`
- `Partially verified:`
- `Not verified:`
- `Assumptions:`
- `Residual risk:`

## Hook Boundary

Hooks are a thin reminder layer. They may warn that calibration state is missing, but they must not perform full verification, recurse into autonomous doctor/verify loops for every task, force subagents or watchers for every task, or enforce final answer ceremony by themselves.
