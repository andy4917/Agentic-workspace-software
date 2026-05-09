# WSHOBSON Agents Docs Full Tree Scan

## Checkout Evidence

- Repository URL: `https://github.com/wshobson/agents.git`
- Branch: `main`
- Commit: `9f9ba3237022cd88d8660060fc58e0492002f978`
- Checkout path: `C:\Users\anise\.codex\.tmp\wshobson-agents-scan\agents`
- Checkout timestamp: `2026-05-09T17:01:45.932602+00:00`
- `git status --short`: `<clean>`
- Total tracked files: 714
- Target folders: `docs/`, `plugins/`, `tools/`
- Target file count: 696
- Read count: 696
- Skipped count: 0

This document is generated from a local checkout and the machine manifest `WSHOBSON_AGENTS_FULL_TREE_MANIFEST.json`.


## Complete File List Under `docs/`

- `docs/agent-skills.md`
- `docs/agents.md`
- `docs/architecture.md`
- `docs/plugin-eval.md`
- `docs/plugins.md`
- `docs/usage.md`

## Required Analysis Dimensions

- Plugin architecture: capability packs contain manifests, agents, commands, skills, references, templates, source, and tests; Codex should distill this into compact capability packs rather than installing everything.
- Agent catalog: source agents are role profiles; Codex should map only useful role patterns into custom agents or subagent prompts.
- Skill catalog: skills are task-triggered procedures with references; Codex should preserve progressive disclosure and short triggers.
- Usage and workflow model: source workflows emphasize explicit invocation, team presets, and task-specific routing.
- Quality evaluation framework: plugin/skill/agent quality checks are useful as review workflows, not runtime completion authority.
- Installation and marketplace assumptions: reject Claude marketplace copy/install assumptions; keep only the capability-pack model.
- Model assignment strategy: use as a routing idea, but keep Codex model choice runtime-native and user/config controlled.
- Codex adaptation implications: PM-led workflow should choose small presets, activate matching skills, verify evidence, and avoid heavy gates.

## Per-File Evidence And Distillation

### `docs/agent-skills.md`

- Read status: `read`
- Semantic class: `documentation`
- Purpose: Agent Skills: Agent Skills are modular packages that extend Claude's capabilities with specialized domain knowledge, following Anthropic's [Agent Skills Specification](https://github.com/anthropics/skills/blob/main/agent_skills_spec.md). This plugin ecosystem includes **153 specialized skills** across 40 plugins, enabling progressive disclosure and efficient token usage.
- Headings observed: # Agent Skills, ## Overview, ## Skills by Plugin, ### Kubernetes Operations (4 skills), ### LLM Application Development (8 skills), ### Backend Development (9 skills), ### Developer Essentials (11 skills), ### Blockchain & Web3 (4 skills)
- Concepts worth carrying into Codex App: Progressive disclosure / load only what is needed; Role-based agent behavior; Reusable skill workflow; Command or task recipe; Quality evaluation; Hook or lifecycle automation; Claude-specific runtime assumption; Model assignment or capability routing
- Concepts to reject: Claude-specific marketplace, slash command, runtime, or installation assumptions when present.
- Related plugin/tool references: conductor, plugins, tools

### `docs/agents.md`

- Read status: `read`
- Semantic class: `documentation`
- Purpose: Agent Reference: Complete reference for all **185 specialized AI agents** organized by category with model assignments. | Agent                                                                                         | Model  | Description                                                            |
- Headings observed: # Agent Reference, ## Agent Categories, ### Architecture & System Design, #### Core Architecture, #### UI/UX & Mobile, ### Programming Languages, #### Systems & Low-Level, #### Web & Application
- Concepts worth carrying into Codex App: Role-based agent behavior; Command or task recipe; Quality evaluation; Claude-specific runtime assumption; Model assignment or capability routing; Marketplace / installation model
- Concepts to reject: Claude-specific marketplace, slash command, runtime, or installation assumptions when present.
- Related plugin/tool references: conductor, plugins

### `docs/architecture.md`

- Read status: `read`
- Semantic class: `documentation`
- Purpose: Architecture & Design Principles: This marketplace follows industry best practices with a focus on granularity, composability, and minimal token usage. - Each plugin does **one thing well** (Unix philosophy) - Clear, focused purposes (describable in 5-10 words) - Average plugin size: **5.5 components** (follows Anthropic's 2-8 pattern)
- Headings observed: # Architecture & Design Principles, ## Core Philosophy, ### Single Responsibility Principle, ### Composability Over Bundling, ### Context Efficiency, ### Maintainability, ## Granular Plugin Architecture, ### Plugin Distribution
- Concepts worth carrying into Codex App: Progressive disclosure / load only what is needed; Role-based agent behavior; Reusable skill workflow; Command or task recipe; Quality evaluation; Claude-specific runtime assumption; Model assignment or capability routing; Marketplace / installation model
- Concepts to reject: Claude-specific marketplace, slash command, runtime, or installation assumptions when present.
- Related plugin/tool references: plugins, tools

### `docs/plugin-eval.md`

- Read status: `read`
- Semantic class: `documentation`
- Purpose: PluginEval: Quality Evaluation Framework: PluginEval is a three-layer quality evaluation framework for Claude Code plugins and skills. It combines deterministic static analysis, LLM-based semantic judging, and Monte Carlo simulation to produce calibrated quality scores with confidence intervals.
- Headings observed: # PluginEval: Quality Evaluation Framework, ## Overview, ### Architecture, ## Installation & Setup, # Install core dependencies (static analysis only), # Install with LLM support (Layers 2 & 3), # Install with direct API support, # Install dev dependencies (tests, linting)
- Concepts worth carrying into Codex App: Progressive disclosure / load only what is needed; Role-based agent behavior; Reusable skill workflow; Command or task recipe; Quality evaluation; Claude-specific runtime assumption; Model assignment or capability routing
- Concepts to reject: Claude-specific marketplace, slash command, runtime, or installation assumptions when present.
- Related plugin/tool references: plugin-eval, plugins, tools

### `docs/plugins.md`

- Read status: `read`
- Semantic class: `documentation`
- Purpose: Complete Plugin Reference: Browse all **80 focused, single-purpose plugins** organized by category, plus 1 externally-hosted plugin (`qa-orchestra`) distributed via a `git-subdir` marketplace entry — 81 plugins total. > 💡 **Also recommended:** [Pensyve](https://github.com/major7apps/pensyve) — universal memory runtime for Claude Code. Distributed from its own marketplace (`major7apps/
- Headings observed: # Complete Plugin Reference, ## Quick Start - Essential Plugins, ### Development Essentials, ### Full-Stack Development, ### Testing & Quality, ### Infrastructure & Operations, ### Language Support, ## Complete Plugin Catalog
- Concepts worth carrying into Codex App: Progressive disclosure / load only what is needed; Role-based agent behavior; Reusable skill workflow; Command or task recipe; Quality evaluation; Hook or lifecycle automation; Claude-specific runtime assumption; Marketplace / installation model
- Concepts to reject: Claude-specific marketplace, slash command, runtime, or installation assumptions when present.
- Related plugin/tool references: conductor, plugins, tools

### `docs/usage.md`

- Read status: `read`
- Semantic class: `documentation`
- Purpose: Usage Guide: Complete guide to using agents, slash commands, and multi-agent workflows. The plugin ecosystem provides two primary interfaces: 1. **Slash Commands** - Direct invocation of tools and workflows 2. **Natural Language** - Claude reasons about which agents to use
- Headings observed: # Usage Guide, ## Overview, ## Slash Commands, ### Command Format, ### Discovering Commands, ### Benefits of Slash Commands, ## Natural Language, ## Command Reference by Category
- Concepts worth carrying into Codex App: Role-based agent behavior; Reusable skill workflow; Command or task recipe; Quality evaluation; Hook or lifecycle automation; Claude-specific runtime assumption; Model assignment or capability routing
- Concepts to reject: Claude-specific marketplace, slash command, runtime, or installation assumptions when present.
- Related plugin/tool references: plugins, tools

## Explicit Read/Classify Evidence

- Docs manifest count: 6
- Docs read count: 6
- Docs skipped count: 0

## Shared Conclusion

### Keep

- small single-purpose capability packs;
- progressive disclosure;
- PM-led team presets;
- Context -> Spec -> Plan -> Implement workflow;
- static quality checks for skills/agents;
- explicit invocation over hidden automatic behavior;
- file ownership and graceful shutdown patterns.

### Reject

- copying the entire Claude marketplace;
- mass installation of every agent;
- Claude-only slash command assumptions;
- tmux or Claude teammate mode as a Codex requirement;
- heavy enforcement hooks;
- completion authority gates from the old failed harness.

### Codex App Mapping

- plugin -> capability pack;
- agent file -> Codex custom agent definition;
- command -> prompt template or task-runner recipe;
- skill -> Codex skill;
- plugin-eval -> skill/agent quality audit;
- conductor track -> lightweight work track;
- agent-teams preset -> PM-selected team workflow.
