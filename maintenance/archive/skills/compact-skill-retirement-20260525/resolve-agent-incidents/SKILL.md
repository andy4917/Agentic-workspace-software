---
name: resolve-agent-incidents
description: "Use when Codex needs to diagnose, resolve, review, or document recurring agent incidents: subagent reward-hacking patterns, unsupported success claims, skipped validation, stale or hidden failures, Codex app/tool errors, MCP/runtime loading problems, hook/workflow issues, Windows path or shell failures, and maintenance troubleshooting records that should be normalized into a reusable incident manual."
---

# Resolve Agent Incidents

Use this skill to turn agent or Codex app failures into fast, evidence-backed fixes and reusable incident records.

## Workflow

1. Define the incident in one sentence: expected behavior, actual behavior, affected surface, and whether the user is blocked.
2. Preserve evidence before changing anything: exact error text, command/tool call, file path, timestamp when useful, and any not-run checks.
3. Read `references/incident-manual.md` when the incident involves reward-hacking behavior, repeated tool/app failures, unclear validation claims, workflow hooks, or a pattern that should be recorded for future use. If the normal file-reading route fails, try another available read surface before treating the manual as unavailable, and preserve the original read failure as evidence.
4. Classify the incident using the manual's taxonomy. Prefer one primary type and optional secondary tags.
5. Match against known patterns. If a pattern matches, apply the documented fix only after checking that the local context really has the same fingerprint.
6. If no pattern matches, form a narrow hypothesis, run the smallest direct check, and patch the first confirmed mismatch.
7. Verify with direct evidence: rerun the failing command, inspect the changed artifact, or state the precise reason direct verification cannot run.
8. Review the outcome for false completion claims: passing output, subagent reports, hook reminders, or MCP availability do not prove completion by themselves.
9. Update the incident manual when the issue is new, repeated, or easy to misdiagnose. Add the symptom fingerprint, root cause, fix, verification, and residual risk.

## Recording Rules

- Record facts, not reassurance.
- Treat subagent output as candidate evidence until independently checked.
- Mark skipped checks as `not_run`; do not convert them into success language.
- Do not read secrets or credential contents to diagnose an incident unless the user explicitly asks for that exact file.
- Keep incident entries compact enough to scan during a live failure.
- Prefer stable fingerprints over long logs: exact error fragments, tool names, paths, status codes, command names, and reproduction steps.

## Reference

Use `references/incident-manual.md` for:

- normalized incident types and tags;
- reward-hacking anti-patterns and review questions;
- known Codex app/tool failure patterns;
- incident record and pattern entry templates;
- update rules for maintaining the manual over time.
