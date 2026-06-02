# Codex Memory Boundary Policy

This policy defines how Codex classifies memory-like information for this
workstation. It is a boundary rule, not a request to create memory storage,
scripts, automation, or generated code.

## Purpose

Codex must prevent contamination between two memory scopes:

- `global-settings`: stable preferences and operating standards that apply
  across repositories.
- `project-scope`: facts and rules that apply only to the current repository or
  current working directory.

No item may be stored, interpreted, or reported as belonging to both scopes at
the same time. If the scope is unclear, keep the information as temporary turn
context only and do not persist it as memory.

## Global-Settings Scope

Use this scope only for stable cross-project preferences:

- preferred engineering workflow and response style;
- code review, architecture, security, and quality standards;
- recurring verification expectations;
- skill-use principles that are not tied to one repository, framework, or
  domain.

Do not put these in global-settings memory:

- repository folder structure;
- project-specific tech stack, APIs, databases, environment variables, build
  commands, deployment routes, naming conventions, or domain rules;
- one-off debugging observations;
- temporary judgments from a single task.

Global skill guidance must stay framework-neutral and repository-neutral unless
the user explicitly opens a broader workstation policy change.

## Project-Scope Boundary

Use this scope only for current-repository evidence:

- project purpose and directory roles;
- build, test, lint, typecheck, and deployment commands;
- project-specific architecture, naming, forbidden patterns, review criteria,
  and skill-use rules.

Do not put these in project-scope memory:

- user preferences that should apply across all repositories;
- rules copied from another repository without current evidence;
- unverified guesses;
- transient failures generalized into durable project rules.

Project-scoped skill guidance must not be promoted to global policy without a
separate workstation-policy task and direct evidence.

## Conflict Handling

When the two scopes conflict:

1. Prefer project-scope evidence for project structure, commands, and runnable
   behavior.
2. Prefer global-settings evidence for response style, review strictness,
   safety posture, and quality bar.
3. If scope remains unclear, do not persist it and do not use it as completion
   authority.
4. If the conflict affects code or config edits, report the boundary conflict
   before editing.

## Active Workstation Rule

Memento and Serena remain retired as active memory MCPs for this baseline.
Current files, scoped `AGENTS.md`, tests, command output, runtime state,
source-backed documentation, installed skills, and reviewed subagent evidence
outrank recalled memory.

Memory writes are not part of the default workflow. A future memory system may
be used only after current user instructions explicitly reopen that boundary,
and each item must be classified as `global-settings` or `project-scope` before
being persisted.

## Verification

A memory-boundary-sensitive task is complete only when the final report states:

- which scope was used, if any;
- what was intentionally not persisted;
- whether any skill choice depended on global or project-scoped evidence;
- what remains temporary turn context.
