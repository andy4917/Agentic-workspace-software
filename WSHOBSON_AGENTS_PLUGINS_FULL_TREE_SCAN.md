# WSHOBSON Agents Plugins Full Tree Scan

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


## Plugin Directory Inventory

- Plugin directories scanned: 80
- `accessibility-compliance`: 5 files
- `agent-orchestration`: 4 files
- `agent-teams`: 28 files
- `api-scaffolding`: 6 files
- `api-testing-observability`: 3 files
- `application-performance`: 5 files
- `arm-cortex-microcontrollers`: 2 files
- `backend-api-security`: 3 files
- `backend-development`: 29 files
- `block-no-verify`: 3 files
- `blockchain-web3`: 6 files
- `brand-landingpage`: 6 files
- `business-analytics`: 4 files
- `c4-architecture`: 6 files
- `cicd-automation`: 12 files
- `cloud-infrastructure`: 22 files
- `code-documentation`: 6 files
- `code-refactoring`: 6 files
- `codebase-cleanup`: 6 files
- `comprehensive-review`: 6 files
- `conductor`: 30 files
- `content-marketing`: 3 files
- `context-management`: 4 files
- `customer-sales-automation`: 3 files
- `data-engineering`: 9 files
- `data-validation-suite`: 2 files
- `database-cloud-optimization`: 6 files
- `database-design`: 4 files
- `database-migrations`: 5 files
- `debugging-toolkit`: 4 files
- `dependency-management`: 3 files
- `deployment-strategies`: 3 files
- `deployment-validation`: 3 files
- `developer-essentials`: 13 files
- `distributed-debugging`: 4 files
- `documentation-generation`: 11 files
- `documentation-standards`: 2 files
- `dotnet-contribution`: 8 files
- `error-debugging`: 6 files
- `error-diagnostics`: 6 files
- `framework-migration`: 10 files
- `frontend-mobile-development`: 9 files
- `frontend-mobile-security`: 5 files
- `full-stack-orchestration`: 6 files
- `functional-programming`: 3 files
- `game-development`: 6 files
- `git-pr-workflows`: 5 files
- `hr-legal-compliance`: 5 files
- `incident-response`: 12 files
- `javascript-typescript`: 11 files
- `julia-development`: 2 files
- `jvm-languages`: 4 files
- `kubernetes-operations`: 19 files
- `llm-application-dev`: 24 files
- `machine-learning-ops`: 6 files
- `meigen-ai-design`: 7 files
- `multi-platform-apps`: 8 files
- `observability-monitoring`: 11 files
- `payment-processing`: 6 files
- `performance-testing-review`: 5 files
- `plugin-eval`: 40 files
- `protect-mcp`: 18 files
- `python-development`: 25 files
- `quantitative-trading`: 5 files
- `reverse-engineering`: 9 files
- `review-agent-governance`: 8 files
- `security-compliance`: 3 files
- `security-scanning`: 11 files
- `seo-analysis-monitoring`: 4 files
- `seo-content-creation`: 4 files
- `seo-technical-optimization`: 5 files
- `shell-scripting`: 6 files
- `signed-audit-trails`: 3 files
- `startup-business-analyst`: 13 files
- `systems-programming`: 9 files
- `tdd-workflows`: 7 files
- `team-collaboration`: 4 files
- `ui-design`: 45 files
- `unit-testing`: 4 files
- `web-scripting`: 3 files

## Per-Plugin Component Counts And Summaries

### `accessibility-compliance`

- Purpose: WCAG accessibility auditing, compliance validation, UI testing for screen readers, keyboard navigation, and inclusive design
- File count: 5
- Component counts: agents 1; commands 1; skills 2; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `ui-visual-validator` (Rigorous visual validation expert specializing in UI testing, design system compliance, and accessibility verificatio...)
- Commands and workflow shape: `accessibility-audit` (Accessibility Audit and Testing: You are an accessibility expert specializing in WCAG compliance, inclusive design, a...)
- Skills and activation patterns: `SKILL` (Test web applications with screen readers including VoiceOver, NVDA, and JAWS. Use when validating screen reader comp...); `SKILL` (Conduct WCAG 2.2 accessibility audits with automated testing, manual verification, and remediation guidance. Use when...)
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/accessibility-compliance/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/accessibility-compliance/agents/ui-visual-validator.md` [agent definition, read]
  - `plugins/accessibility-compliance/commands/accessibility-audit.md` [command workflow, read]
  - `plugins/accessibility-compliance/skills/screen-reader-testing/SKILL.md` [skill instruction, read]
  - `plugins/accessibility-compliance/skills/wcag-audit-patterns/SKILL.md` [skill instruction, read]

### `agent-orchestration`

- Purpose: Multi-agent system optimization, agent improvement workflows, and context management
- File count: 4
- Component counts: agents 1; commands 2; skills 0; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `context-manager` (Elite AI context engineering specialist mastering dynamic context management, vector databases, knowledge graphs, and...)
- Commands and workflow shape: `improve-agent` (Agent Performance Optimization Workflow: Systematic improvement of existing agents through performance analysis, prom...); `multi-agent-optimize` (Multi-Agent Optimization Toolkit: The Multi-Agent Optimization Tool is an advanced AI-driven framework designed to ho...)
- Skills and activation patterns: none found
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/agent-orchestration/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/agent-orchestration/agents/context-manager.md` [agent definition, read]
  - `plugins/agent-orchestration/commands/improve-agent.md` [command workflow, read]
  - `plugins/agent-orchestration/commands/multi-agent-optimize.md` [command workflow, read]

### `agent-teams`

- Purpose: Orchestrate multi-agent teams for parallel code review, hypothesis-driven debugging, and coordinated feature development using Claude Code's Agent Teams
- File count: 28
- Component counts: agents 4; commands 7; skills 6; references 9; manifests 1; templates 0; source code 0; tests 0; other 1
- Useful for PM-main workflow: high priority
- Too domain-specific or heavy: review before adoption; distill only patterns
- Agents and roles: `team-debugger` (Hypothesis-driven debugging investigator that investigates one assigned hypothesis, gathering evidence to confirm or ...); `team-implementer` (Parallel feature builder that implements components within strict file ownership boundaries, coordinating at integrat...); `team-lead` (Team orchestrator that decomposes work into parallel tasks with file ownership boundaries, manages team lifecycle, an...); `team-reviewer` (Multi-dimensional code reviewer that operates on one assigned review dimension (security, performance, architecture, ...)
- Commands and workflow shape: `team-debug` (Debug issues using competing hypotheses with parallel investigation by multiple agents); `team-delegate` (Task delegation dashboard for managing team workload, assignments, and rebalancing); `team-feature` (Develop features in parallel with multiple agents using file ownership boundaries and dependency management); `team-review` (Launch a multi-reviewer parallel code review with specialized review dimensions); `team-shutdown` (Gracefully shut down an agent team, collect final results, and clean up resources); `team-spawn` (Spawn an agent team using presets (review, debug, feature, fullstack, research, security, migration) or custom compos...); `team-status` (Display team members, task status, and progress for an active agent team)
- Skills and activation patterns: `SKILL` (Coordinate parallel code reviews across multiple quality dimensions with finding deduplication, severity calibration,...); `SKILL` (Debug complex issues using competing hypotheses with parallel investigation, evidence collection, and root cause arbi...); `SKILL` (Coordinate parallel feature development with file ownership strategies, conflict avoidance rules, and integration pat...); `SKILL` (Decompose complex tasks, design dependency graphs, and coordinate multi-agent work with proper task descriptions and ...); `SKILL` (Structured messaging protocols for agent team communication including message type selection, plan approval, shutdown...); `SKILL` (Design optimal agent team compositions with sizing heuristics, preset configurations, and agent type selection. Use t...)
- High-priority distillation:
  - Adopt bounded roles, explicit ownership, progressive references, and review/checklist shapes.
  - Do not adopt Claude-only slash command syntax, marketplace install flow, tmux teammate assumptions, or hidden authority gates.
  - Codex mapping: capability pack plus optional custom agents, prompt recipes, and skills selected by the PM.
- Files: 28 total; complete paths are in the JSON manifest.
- Reference/template examples: `plugins/agent-teams/skills/multi-reviewer-patterns/references/review-dimensions.md`, `plugins/agent-teams/skills/parallel-debugging/references/hypothesis-testing.md`, `plugins/agent-teams/skills/parallel-feature-development/references/file-ownership.md`, `plugins/agent-teams/skills/parallel-feature-development/references/merge-strategies.md`, `plugins/agent-teams/skills/task-coordination-strategies/references/dependency-graphs.md`, `plugins/agent-teams/skills/task-coordination-strategies/references/task-decomposition.md`

### `api-scaffolding`

- Purpose: REST and GraphQL API scaffolding, framework selection, backend architecture, and API generation
- File count: 6
- Component counts: agents 4; commands 0; skills 1; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `backend-architect` (Expert backend architect specializing in scalable API design, microservices architecture, and distributed systems. Ma...); `django-pro` (Master Django 5.x with async views, DRF, Celery, and Django Channels. Build scalable web applications with proper arc...); `fastapi-pro` (Build high-performance async APIs with FastAPI, SQLAlchemy 2.0, and Pydantic V2. Master microservices, WebSockets, an...); `graphql-architect` (Master modern GraphQL with federation, performance optimization, and enterprise security. Build scalable schemas, imp...)
- Commands and workflow shape: none found
- Skills and activation patterns: `SKILL` (Create production-ready FastAPI projects with async patterns, dependency injection, and comprehensive error handling....)
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/api-scaffolding/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/api-scaffolding/agents/backend-architect.md` [agent definition, read]
  - `plugins/api-scaffolding/agents/django-pro.md` [agent definition, read]
  - `plugins/api-scaffolding/agents/fastapi-pro.md` [agent definition, read]
  - `plugins/api-scaffolding/agents/graphql-architect.md` [agent definition, read]
  - `plugins/api-scaffolding/skills/fastapi-templates/SKILL.md` [skill instruction, read]

### `api-testing-observability`

- Purpose: API testing automation, request mocking, OpenAPI documentation generation, observability setup, and monitoring
- File count: 3
- Component counts: agents 1; commands 1; skills 0; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `api-documenter` (Master API documentation with OpenAPI 3.1, AI-powered tools, and modern developer experience practices. Create intera...)
- Commands and workflow shape: `api-mock` (API Mocking Framework: You are an API mocking expert specializing in creating realistic mock services for development...)
- Skills and activation patterns: none found
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/api-testing-observability/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/api-testing-observability/agents/api-documenter.md` [agent definition, read]
  - `plugins/api-testing-observability/commands/api-mock.md` [command workflow, read]

### `application-performance`

- Purpose: Application profiling, performance optimization, and observability for frontend and backend systems
- File count: 5
- Component counts: agents 3; commands 1; skills 0; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `frontend-developer` (Build React components, implement responsive layouts, and handle client-side state management. Masters React 19, Next...); `observability-engineer` (Build production-ready monitoring, logging, and tracing systems. Implements comprehensive observability strategies, S...); `performance-engineer` (Expert performance engineer specializing in modern observability, application optimization, and scalable system perfo...)
- Commands and workflow shape: `performance-optimization` (Orchestrate end-to-end application performance optimization from profiling to monitoring)
- Skills and activation patterns: none found
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/application-performance/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/application-performance/agents/frontend-developer.md` [agent definition, read]
  - `plugins/application-performance/agents/observability-engineer.md` [agent definition, read]
  - `plugins/application-performance/agents/performance-engineer.md` [agent definition, read]
  - `plugins/application-performance/commands/performance-optimization.md` [command workflow, read]

### `arm-cortex-microcontrollers`

- Purpose: ARM Cortex-M firmware development for Teensy, STM32, nRF52, and SAMD with peripheral drivers and memory safety patterns
- File count: 2
- Component counts: agents 1; commands 0; skills 0; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `arm-cortex-expert` (>)
- Commands and workflow shape: none found
- Skills and activation patterns: none found
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/arm-cortex-microcontrollers/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/arm-cortex-microcontrollers/agents/arm-cortex-expert.md` [agent definition, read]

### `backend-api-security`

- Purpose: API security hardening, authentication implementation, authorization patterns, rate limiting, and input validation
- File count: 3
- Component counts: agents 2; commands 0; skills 0; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: high priority
- Too domain-specific or heavy: review before adoption; distill only patterns
- Agents and roles: `backend-architect` (Expert backend architect specializing in scalable API design, microservices architecture, and distributed systems. Ma...); `backend-security-coder` (Expert in secure backend coding practices specializing in input validation, authentication, and API security. Use PRO...)
- Commands and workflow shape: none found
- Skills and activation patterns: none found
- High-priority distillation:
  - Adopt bounded roles, explicit ownership, progressive references, and review/checklist shapes.
  - Do not adopt Claude-only slash command syntax, marketplace install flow, tmux teammate assumptions, or hidden authority gates.
  - Codex mapping: capability pack plus optional custom agents, prompt recipes, and skills selected by the PM.
- Files:
  - `plugins/backend-api-security/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/backend-api-security/agents/backend-architect.md` [agent definition, read]
  - `plugins/backend-api-security/agents/backend-security-coder.md` [agent definition, read]

### `backend-development`

- Purpose: Backend API design, GraphQL architecture, workflow orchestration with Temporal, and test-driven backend development
- File count: 29
- Component counts: agents 8; commands 1; skills 13; references 4; manifests 1; templates 2; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `backend-architect` (Expert backend architect specializing in scalable API design, microservices architecture, and distributed systems. Ma...); `event-sourcing-architect` (Expert in event sourcing, CQRS, and event-driven architecture patterns. Masters event store design, projection buildi...); `graphql-architect` (Master modern GraphQL with federation, performance optimization, and enterprise security. Build scalable schemas, imp...); `performance-engineer` (Profile and optimize application performance including response times, memory usage, query efficiency, and scalabilit...); `security-auditor` (Review code and architecture for security vulnerabilities, OWASP Top 10, auth flaws, and compliance issues. Use for s...); `tdd-orchestrator` (Master TDD orchestrator specializing in red-green-refactor discipline, multi-agent workflow coordination, and compreh...); `temporal-python-pro` (Master Temporal workflow orchestration with Python SDK. Implements durable workflows, saga patterns, and distributed ...); `test-automator` (Create comprehensive test suites including unit, integration, and E2E tests. Supports TDD/BDD workflows. Use for test...)
- Commands and workflow shape: `feature-development` (Orchestrate end-to-end feature development from requirements to deployment)
- Skills and activation patterns: `SKILL` (Master REST and GraphQL API design principles to build intuitive, scalable, and maintainable APIs that delight develo...); `SKILL` (Implement proven backend architecture patterns including Clean Architecture, Hexagonal Architecture, and Domain-Drive...); `SKILL` (Implement Command Query Responsibility Segregation for scalable architectures. Use when separating read and write mod...); `SKILL` (Design and implement event stores for event-sourced systems. Use when building event sourcing infrastructure, choosin...); `SKILL` (Design microservices architectures with service boundaries, event-driven communication, and resilience patterns. Use ...); `SKILL` (Build read models and projections from event streams. Use when implementing CQRS read sides, building materialized vi...); `SKILL` (Implement saga patterns for distributed transactions and cross-aggregate workflows. Use this skill when implementing ...); `SKILL` (Test Temporal workflows with pytest, time-skipping, and mocking strategies. Covers unit testing, integration testing,...); +5 more
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files: 29 total; complete paths are in the JSON manifest.
- Reference/template examples: `plugins/backend-development/skills/api-design-principles/references/graphql-schema-design.md`, `plugins/backend-development/skills/api-design-principles/references/rest-best-practices.md`, `plugins/backend-development/skills/architecture-patterns/references/advanced-patterns.md`, `plugins/backend-development/skills/saga-orchestration/references/advanced-patterns.md`, `plugins/backend-development/skills/api-design-principles/assets/api-design-checklist.md`, `plugins/backend-development/skills/api-design-principles/assets/rest-api-template.py`

### `block-no-verify`

- Purpose: PreToolUse hook that prevents AI agents from using --no-verify, --no-gpg-sign, and other bypass flags that skip git hooks
- File count: 3
- Component counts: agents 0; commands 1; skills 1; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: none found
- Commands and workflow shape: `block-no-verify` (Set up PreToolUse hook to block --no-verify and other git bypass flags in Claude Code projects)
- Skills and activation patterns: `SKILL` (Configure a PreToolUse hook to prevent AI agents from skipping git pre-commit hooks with --no-verify and other bypass...)
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/block-no-verify/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/block-no-verify/commands/block-no-verify.md` [command workflow, read]
  - `plugins/block-no-verify/skills/block-no-verify-hook/SKILL.md` [skill instruction, read]

### `blockchain-web3`

- Purpose: Smart contract development with Solidity, DeFi protocol implementation, NFT platforms, and Web3 application architecture
- File count: 6
- Component counts: agents 1; commands 0; skills 4; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `blockchain-developer` (Build production-ready Web3 applications, smart contracts, and decentralized systems. Implements DeFi protocols, NFT ...)
- Commands and workflow shape: none found
- Skills and activation patterns: `SKILL` (Implement DeFi protocols with production-ready templates for staking, AMMs, governance, and lending systems. Use when...); `SKILL` (Implement NFT standards (ERC-721, ERC-1155) with proper metadata handling, minting strategies, and marketplace integr...); `SKILL` (Master smart contract security best practices to prevent common vulnerabilities and implement secure Solidity pattern...); `SKILL` (Test smart contracts comprehensively using Hardhat and Foundry with unit tests, integration tests, and mainnet forkin...)
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/blockchain-web3/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/blockchain-web3/agents/blockchain-developer.md` [agent definition, read]
  - `plugins/blockchain-web3/skills/defi-protocol-templates/SKILL.md` [skill instruction, read]
  - `plugins/blockchain-web3/skills/nft-standards/SKILL.md` [skill instruction, read]
  - `plugins/blockchain-web3/skills/solidity-security/SKILL.md` [skill instruction, read]
  - `plugins/blockchain-web3/skills/web3-testing/SKILL.md` [skill instruction, read]

### `brand-landingpage`

- Purpose: Guides developers from brand discovery through iterative design to deployment-ready HTML via Stitch.
- File count: 6
- Component counts: agents 0; commands 0; skills 1; references 3; manifests 1; templates 0; source code 0; tests 0; other 1
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: none found
- Commands and workflow shape: none found
- Skills and activation patterns: `SKILL` (>)
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/brand-landingpage/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/brand-landingpage/README.md` [documentation, read]
  - `plugins/brand-landingpage/skills/brand-landingpage/SKILL.md` [skill instruction, read]
  - `plugins/brand-landingpage/skills/brand-landingpage/references/interview-framework.md` [skill reference, read]
  - `plugins/brand-landingpage/skills/brand-landingpage/references/state-and-pitfalls.md` [skill reference, read]
  - `plugins/brand-landingpage/skills/brand-landingpage/references/stitch-architecture.md` [skill reference, read]

### `business-analytics`

- Purpose: Business metrics analysis, KPI tracking, financial reporting, and data-driven decision making
- File count: 4
- Component counts: agents 1; commands 0; skills 2; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `business-analyst` (Master modern business analysis with AI-powered analytics, real-time dashboards, and data-driven insights. Build comp...)
- Commands and workflow shape: none found
- Skills and activation patterns: `SKILL` (Transform data into compelling narratives using visualization, context, and persuasive structure. Use when presenting...); `SKILL` (Design effective KPI dashboards with metrics selection, visualization best practices, and real-time monitoring patter...)
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/business-analytics/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/business-analytics/agents/business-analyst.md` [agent definition, read]
  - `plugins/business-analytics/skills/data-storytelling/SKILL.md` [skill instruction, read]
  - `plugins/business-analytics/skills/kpi-dashboard-design/SKILL.md` [skill instruction, read]

### `c4-architecture`

- Purpose: Comprehensive C4 architecture documentation workflow with bottom-up code analysis, component synthesis, container mapping, and context diagram generation
- File count: 6
- Component counts: agents 4; commands 1; skills 0; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `c4-code` (Expert C4 Code-level documentation specialist. Analyzes code directories to create comprehensive C4 code-level docume...); `c4-component` (Expert C4 Component-level documentation specialist. Synthesizes C4 Code-level documentation into Component-level arch...); `c4-container` (Expert C4 Container-level documentation specialist. Synthesizes Component-level documentation into Container-level ar...); `c4-context` (Expert C4 Context-level documentation specialist. Creates high-level system context diagrams, documents personas, use...)
- Commands and workflow shape: `c4-architecture` (Generate comprehensive C4 architecture documentation (Context, Container, Component, Code) for a codebase using botto...)
- Skills and activation patterns: none found
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/c4-architecture/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/c4-architecture/agents/c4-code.md` [agent definition, read]
  - `plugins/c4-architecture/agents/c4-component.md` [agent definition, read]
  - `plugins/c4-architecture/agents/c4-container.md` [agent definition, read]
  - `plugins/c4-architecture/agents/c4-context.md` [agent definition, read]
  - `plugins/c4-architecture/commands/c4-architecture.md` [command workflow, read]

### `cicd-automation`

- Purpose: CI/CD pipeline configuration, GitHub Actions/GitLab CI workflow setup, and automated deployment pipeline orchestration
- File count: 12
- Component counts: agents 5; commands 1; skills 4; references 1; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `cloud-architect` (Expert cloud architect specializing in AWS/Azure/GCP/OCI multi-cloud infrastructure design, advanced IaC (Terraform/O...); `deployment-engineer` (Expert deployment engineer specializing in modern CI/CD pipelines, GitOps workflows, and advanced deployment automati...); `devops-troubleshooter` (Expert DevOps troubleshooter specializing in rapid incident response, advanced debugging, and modern observability. M...); `kubernetes-architect` (Expert Kubernetes architect specializing in cloud-native infrastructure, advanced GitOps workflows (ArgoCD/Flux), and...); `terraform-specialist` (Expert Terraform/OpenTofu specialist mastering advanced IaC automation, state management, and enterprise infrastructu...)
- Commands and workflow shape: `workflow-automate` (Workflow Automation: You are a workflow automation expert specializing in creating efficient CI/CD pipelines, GitHub ...)
- Skills and activation patterns: `SKILL` (Design multi-stage CI/CD pipelines with approval gates, security checks, and deployment orchestration. Use this skill...); `SKILL` (Create production-ready GitHub Actions workflows for automated testing, building, and deploying applications. Use whe...); `SKILL` (Build GitLab CI/CD pipelines with multi-stage workflows, caching, and distributed runners for scalable automation. Us...); `SKILL` (Implement secure secrets management for CI/CD pipelines using Vault, AWS Secrets Manager, or native platform solution...)
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/cicd-automation/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/cicd-automation/agents/cloud-architect.md` [agent definition, read]
  - `plugins/cicd-automation/agents/deployment-engineer.md` [agent definition, read]
  - `plugins/cicd-automation/agents/devops-troubleshooter.md` [agent definition, read]
  - `plugins/cicd-automation/agents/kubernetes-architect.md` [agent definition, read]
  - `plugins/cicd-automation/agents/terraform-specialist.md` [agent definition, read]
  - `plugins/cicd-automation/commands/workflow-automate.md` [command workflow, read]
  - `plugins/cicd-automation/skills/deployment-pipeline-design/SKILL.md` [skill instruction, read]
  - `plugins/cicd-automation/skills/deployment-pipeline-design/references/advanced-strategies.md` [skill reference, read]
  - `plugins/cicd-automation/skills/github-actions-templates/SKILL.md` [skill instruction, read]
  - `plugins/cicd-automation/skills/gitlab-ci-patterns/SKILL.md` [skill instruction, read]
  - `plugins/cicd-automation/skills/secrets-management/SKILL.md` [skill instruction, read]

### `cloud-infrastructure`

- Purpose: Cloud architecture design for AWS/Azure/GCP/OCI, Kubernetes cluster configuration, Terraform infrastructure-as-code, hybrid cloud networking, and multi-cloud cost optimization
- File count: 22
- Component counts: agents 7; commands 0; skills 8; references 6; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `cloud-architect` (Expert cloud architect specializing in AWS/Azure/GCP/OCI multi-cloud infrastructure design, advanced IaC (Terraform/O...); `deployment-engineer` (Expert deployment engineer specializing in modern CI/CD pipelines, GitOps workflows, and advanced deployment automati...); `hybrid-cloud-architect` (Expert hybrid cloud architect specializing in complex multi-cloud solutions across AWS/Azure/GCP/OCI and private clou...); `kubernetes-architect` (Expert Kubernetes architect specializing in cloud-native infrastructure, advanced GitOps workflows (ArgoCD/Flux), and...); `network-engineer` (Expert network engineer specializing in modern cloud networking, security architectures, and performance optimization...); `service-mesh-expert` (Expert service mesh architect specializing in Istio, Linkerd, and cloud-native networking patterns. Masters traffic m...); `terraform-specialist` (Expert Terraform/OpenTofu specialist mastering advanced IaC automation, state management, and enterprise infrastructu...)
- Commands and workflow shape: none found
- Skills and activation patterns: `SKILL` (Optimize cloud costs across AWS, Azure, GCP, and OCI through resource rightsizing, tagging strategies, reserved insta...); `SKILL` (Configure secure, high-performance connectivity between on-premises infrastructure and cloud platforms using VPN and ...); `SKILL` (Configure Istio traffic management including routing, load balancing, circuit breakers, and canary deployments. Use w...); `SKILL` (Implement Linkerd service mesh patterns for lightweight, security-focused service mesh deployments. Use when setting ...); `SKILL` (Configure mutual TLS (mTLS) for zero-trust service-to-service communication. Use when implementing zero-trust network...); `SKILL` (Design multi-cloud architectures using a decision framework to select and integrate services across AWS, Azure, GCP, ...); `SKILL` (Implement comprehensive observability for service meshes including distributed tracing, metrics, and visualization. U...); `SKILL` (Build reusable Terraform modules for AWS, Azure, GCP, and OCI infrastructure following infrastructure-as-code best pr...)
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files: 22 total; complete paths are in the JSON manifest.
- Reference/template examples: `plugins/cloud-infrastructure/skills/cost-optimization/references/tagging-standards.md`, `plugins/cloud-infrastructure/skills/hybrid-cloud-networking/references/direct-connect.md`, `plugins/cloud-infrastructure/skills/multi-cloud-architecture/references/multi-cloud-patterns.md`, `plugins/cloud-infrastructure/skills/multi-cloud-architecture/references/service-comparison.md`, `plugins/cloud-infrastructure/skills/terraform-module-library/references/aws-modules.md`, `plugins/cloud-infrastructure/skills/terraform-module-library/references/oci-modules.md`

### `code-documentation`

- Purpose: Documentation generation, code explanation, and technical writing with automated doc generation and tutorial creation
- File count: 6
- Component counts: agents 3; commands 2; skills 0; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `code-reviewer` (Elite code review expert specializing in modern AI-powered code analysis, security vulnerabilities, performance optim...); `docs-architect` (Creates comprehensive technical documentation from existing codebases. Analyzes architecture, design patterns, and im...); `tutorial-engineer` (Creates step-by-step tutorials and educational content from code. Transforms complex concepts into progressive learni...)
- Commands and workflow shape: `code-explain` (Code Explanation and Analysis: You are a code education expert specializing in explaining complex code through clear ...); `doc-generate` (Automated Documentation Generation: You are a documentation expert specializing in creating comprehensive, maintainab...)
- Skills and activation patterns: none found
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/code-documentation/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/code-documentation/agents/code-reviewer.md` [agent definition, read]
  - `plugins/code-documentation/agents/docs-architect.md` [agent definition, read]
  - `plugins/code-documentation/agents/tutorial-engineer.md` [agent definition, read]
  - `plugins/code-documentation/commands/code-explain.md` [command workflow, read]
  - `plugins/code-documentation/commands/doc-generate.md` [command workflow, read]

### `code-refactoring`

- Purpose: Code cleanup, refactoring automation, and technical debt management with context restoration
- File count: 6
- Component counts: agents 2; commands 3; skills 0; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: high priority
- Too domain-specific or heavy: review before adoption; distill only patterns
- Agents and roles: `code-reviewer` (Elite code review expert specializing in modern AI-powered code analysis, security vulnerabilities, performance optim...); `legacy-modernizer` (Refactor legacy codebases, migrate outdated frameworks, and implement gradual modernization. Handles technical debt, ...)
- Commands and workflow shape: `context-restore` (Context Restoration: Advanced Semantic Memory Rehydration: Expert Context Restoration Specialist focused on intellige...); `refactor-clean` (Refactor and Clean Code: You are a code refactoring expert specializing in clean code principles, SOLID design patter...); `tech-debt` (Technical Debt Analysis and Remediation: You are a technical debt expert specializing in identifying, quantifying, an...)
- Skills and activation patterns: none found
- High-priority distillation:
  - Adopt bounded roles, explicit ownership, progressive references, and review/checklist shapes.
  - Do not adopt Claude-only slash command syntax, marketplace install flow, tmux teammate assumptions, or hidden authority gates.
  - Codex mapping: capability pack plus optional custom agents, prompt recipes, and skills selected by the PM.
- Files:
  - `plugins/code-refactoring/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/code-refactoring/agents/code-reviewer.md` [agent definition, read]
  - `plugins/code-refactoring/agents/legacy-modernizer.md` [agent definition, read]
  - `plugins/code-refactoring/commands/context-restore.md` [command workflow, read]
  - `plugins/code-refactoring/commands/refactor-clean.md` [command workflow, read]
  - `plugins/code-refactoring/commands/tech-debt.md` [command workflow, read]

### `codebase-cleanup`

- Purpose: Technical debt reduction, dependency updates, and code refactoring automation
- File count: 6
- Component counts: agents 2; commands 3; skills 0; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: high priority
- Too domain-specific or heavy: review before adoption; distill only patterns
- Agents and roles: `code-reviewer` (Elite code review expert specializing in modern AI-powered code analysis, security vulnerabilities, performance optim...); `test-automator` (Master AI-powered test automation with modern frameworks, self-healing tests, and comprehensive quality engineering. ...)
- Commands and workflow shape: `deps-audit` (Audit project dependencies for vulnerabilities, outdated packages, license conflicts, and supply chain risks — then p...); `refactor-clean` (Refactor provided code for cleanliness, maintainability, and alignment with SOLID principles and modern best practice...); `tech-debt` (Analyze and remediate technical debt — inventory debt items, score by impact, and produce a prioritized remediation p...)
- Skills and activation patterns: none found
- High-priority distillation:
  - Adopt bounded roles, explicit ownership, progressive references, and review/checklist shapes.
  - Do not adopt Claude-only slash command syntax, marketplace install flow, tmux teammate assumptions, or hidden authority gates.
  - Codex mapping: capability pack plus optional custom agents, prompt recipes, and skills selected by the PM.
- Files:
  - `plugins/codebase-cleanup/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/codebase-cleanup/agents/code-reviewer.md` [agent definition, read]
  - `plugins/codebase-cleanup/agents/test-automator.md` [agent definition, read]
  - `plugins/codebase-cleanup/commands/deps-audit.md` [command workflow, read]
  - `plugins/codebase-cleanup/commands/refactor-clean.md` [command workflow, read]
  - `plugins/codebase-cleanup/commands/tech-debt.md` [command workflow, read]

### `comprehensive-review`

- Purpose: Multi-perspective code analysis covering architecture, security, and best practices
- File count: 6
- Component counts: agents 3; commands 2; skills 0; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: high priority
- Too domain-specific or heavy: review before adoption; distill only patterns
- Agents and roles: `architect-review` (Master software architect specializing in modern architecture patterns, clean architecture, microservices, event-driv...); `code-reviewer` (Elite code review expert specializing in modern AI-powered code analysis, security vulnerabilities, performance optim...); `security-auditor` (Expert security auditor specializing in DevSecOps, comprehensive cybersecurity, and compliance frameworks. Masters vu...)
- Commands and workflow shape: `full-review` (Orchestrate comprehensive multi-dimensional code review using specialized review agents across architecture, security...); `pr-enhance` (Pull Request Enhancement: You are a PR optimization expert specializing in creating high-quality pull requests that f...)
- Skills and activation patterns: none found
- High-priority distillation:
  - Adopt bounded roles, explicit ownership, progressive references, and review/checklist shapes.
  - Do not adopt Claude-only slash command syntax, marketplace install flow, tmux teammate assumptions, or hidden authority gates.
  - Codex mapping: capability pack plus optional custom agents, prompt recipes, and skills selected by the PM.
- Files:
  - `plugins/comprehensive-review/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/comprehensive-review/agents/architect-review.md` [agent definition, read]
  - `plugins/comprehensive-review/agents/code-reviewer.md` [agent definition, read]
  - `plugins/comprehensive-review/agents/security-auditor.md` [agent definition, read]
  - `plugins/comprehensive-review/commands/full-review.md` [command workflow, read]
  - `plugins/comprehensive-review/commands/pr-enhance.md` [command workflow, read]

### `conductor`

- Purpose: Context-Driven Development plugin that transforms Claude Code into a project management tool with structured workflow: Context → Spec & Plan → Implement
- File count: 30
- Component counts: agents 1; commands 6; skills 3; references 1; manifests 1; templates 0; source code 0; tests 0; other 18
- Useful for PM-main workflow: high priority
- Too domain-specific or heavy: review before adoption; distill only patterns
- Agents and roles: `conductor-validator` (Validates Conductor project artifacts for completeness, consistency, and correctness. Use after setup, when diagnosin...)
- Commands and workflow shape: `implement` (Execute tasks from a track's implementation plan following TDD workflow); `manage` (Manage track lifecycle: archive, restore, delete, rename, and cleanup); `new-track` (Create a new track with specification and phased implementation plan); `revert` (Git-aware undo by logical work unit (track, phase, or task)); `setup` (Initialize project with Conductor artifacts (product definition, tech stack, workflow, style guides)); `status` (Display project status, active tracks, and next actions)
- Skills and activation patterns: `SKILL` (>-); `SKILL` (Use this skill when creating, managing, or working with Conductor tracks - the logical work units for features, bugs,...); `SKILL` (Use this skill when implementing tasks according to Conductor's TDD workflow, handling phase checkpoints, managing gi...)
- High-priority distillation:
  - Adopt bounded roles, explicit ownership, progressive references, and review/checklist shapes.
  - Do not adopt Claude-only slash command syntax, marketplace install flow, tmux teammate assumptions, or hidden authority gates.
  - Codex mapping: capability pack plus optional custom agents, prompt recipes, and skills selected by the PM.
- Files: 30 total; complete paths are in the JSON manifest.
- Reference/template examples: `plugins/conductor/skills/context-driven-development/references/artifact-templates.md`

### `content-marketing`

- Purpose: Content marketing strategy, web research, and information synthesis for marketing operations
- File count: 3
- Component counts: agents 2; commands 0; skills 0; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `content-marketer` (Elite content marketing strategist specializing in AI-powered content creation, omnichannel distribution, SEO optimiz...); `search-specialist` (Expert web researcher using advanced search techniques and synthesis. Masters search operators, result filtering, and...)
- Commands and workflow shape: none found
- Skills and activation patterns: none found
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/content-marketing/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/content-marketing/agents/content-marketer.md` [agent definition, read]
  - `plugins/content-marketing/agents/search-specialist.md` [agent definition, read]

### `context-management`

- Purpose: Context persistence, restoration, and long-running conversation management
- File count: 4
- Component counts: agents 1; commands 2; skills 0; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `context-manager` (Elite AI context engineering specialist mastering dynamic context management, vector databases, knowledge graphs, and...)
- Commands and workflow shape: `context-restore` (Context Restoration: Advanced Semantic Memory Rehydration: Expert Context Restoration Specialist focused on intellige...); `context-save` (Context Save Tool: Intelligent Context Management Specialist: An elite context engineering specialist focused on comp...)
- Skills and activation patterns: none found
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/context-management/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/context-management/agents/context-manager.md` [agent definition, read]
  - `plugins/context-management/commands/context-restore.md` [command workflow, read]
  - `plugins/context-management/commands/context-save.md` [command workflow, read]

### `customer-sales-automation`

- Purpose: Customer support workflow automation, sales pipeline management, email campaigns, and CRM integration
- File count: 3
- Component counts: agents 2; commands 0; skills 0; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `customer-support` (Elite AI-powered customer support specialist mastering conversational AI, automated ticketing, sentiment analysis, an...); `sales-automator` (Draft cold emails, follow-ups, and proposal templates. Creates pricing pages, case studies, and sales scripts. Use PR...)
- Commands and workflow shape: none found
- Skills and activation patterns: none found
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/customer-sales-automation/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/customer-sales-automation/agents/customer-support.md` [agent definition, read]
  - `plugins/customer-sales-automation/agents/sales-automator.md` [agent definition, read]

### `data-engineering`

- Purpose: ETL pipeline construction, data warehouse design, batch processing workflows, and data-driven feature development
- File count: 9
- Component counts: agents 2; commands 2; skills 4; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `backend-architect` (Expert backend architect specializing in scalable API design, microservices architecture, and distributed systems. Ma...); `data-engineer` (Build scalable data pipelines, modern data warehouses, and real-time streaming architectures. Implements Apache Spark...)
- Commands and workflow shape: `data-driven-feature` (Build features guided by data insights, A/B testing, and continuous measurement); `data-pipeline` (Data Pipeline Architecture: You are a data pipeline architecture expert specializing in scalable, reliable, and cost-...)
- Skills and activation patterns: `SKILL` (Build production Apache Airflow DAGs with best practices for operators, sensors, testing, and deployment. Use when cr...); `SKILL` (Implement data quality validation with Great Expectations, dbt tests, and data contracts. Use when building data qual...); `SKILL` (Master dbt (data build tool) for analytics engineering with model organization, testing, documentation, and increment...); `SKILL` (Optimize Apache Spark jobs with partitioning, caching, shuffle optimization, and memory tuning. Use when improving Sp...)
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/data-engineering/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/data-engineering/agents/backend-architect.md` [agent definition, read]
  - `plugins/data-engineering/agents/data-engineer.md` [agent definition, read]
  - `plugins/data-engineering/commands/data-driven-feature.md` [command workflow, read]
  - `plugins/data-engineering/commands/data-pipeline.md` [command workflow, read]
  - `plugins/data-engineering/skills/airflow-dag-patterns/SKILL.md` [skill instruction, read]
  - `plugins/data-engineering/skills/data-quality-frameworks/SKILL.md` [skill instruction, read]
  - `plugins/data-engineering/skills/dbt-transformation-patterns/SKILL.md` [skill instruction, read]
  - `plugins/data-engineering/skills/spark-optimization/SKILL.md` [skill instruction, read]

### `data-validation-suite`

- Purpose: Schema validation, data quality monitoring, streaming validation pipelines, and input validation for backend APIs
- File count: 2
- Component counts: agents 1; commands 0; skills 0; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `backend-security-coder` (Expert in secure backend coding practices specializing in input validation, authentication, and API security. Use PRO...)
- Commands and workflow shape: none found
- Skills and activation patterns: none found
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/data-validation-suite/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/data-validation-suite/agents/backend-security-coder.md` [agent definition, read]

### `database-cloud-optimization`

- Purpose: Database query optimization, cloud cost optimization, and scalability improvements
- File count: 6
- Component counts: agents 4; commands 1; skills 0; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `backend-architect` (Expert backend architect specializing in scalable API design, microservices architecture, and distributed systems. Ma...); `cloud-architect` (Expert cloud architect specializing in AWS/Azure/GCP/OCI multi-cloud infrastructure design, advanced IaC (Terraform/O...); `database-architect` (Expert database architect specializing in data layer design from scratch, technology selection, schema modeling, and ...); `database-optimizer` (Expert database optimizer specializing in modern performance tuning, query optimization, and scalable architectures. ...)
- Commands and workflow shape: `cost-optimize` (Cloud Cost Optimization: You are a cloud cost optimization expert specializing in reducing infrastructure expenses wh...)
- Skills and activation patterns: none found
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/database-cloud-optimization/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/database-cloud-optimization/agents/backend-architect.md` [agent definition, read]
  - `plugins/database-cloud-optimization/agents/cloud-architect.md` [agent definition, read]
  - `plugins/database-cloud-optimization/agents/database-architect.md` [agent definition, read]
  - `plugins/database-cloud-optimization/agents/database-optimizer.md` [agent definition, read]
  - `plugins/database-cloud-optimization/commands/cost-optimize.md` [command workflow, read]

### `database-design`

- Purpose: Database architecture, schema design, and SQL optimization for production systems
- File count: 4
- Component counts: agents 2; commands 0; skills 1; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `database-architect` (Expert database architect specializing in data layer design from scratch, technology selection, schema modeling, and ...); `sql-pro` (Master modern SQL with cloud-native databases, OLTP/OLAP optimization, and advanced query techniques. Expert in perfo...)
- Commands and workflow shape: none found
- Skills and activation patterns: `SKILL` (Use this skill when designing or reviewing a PostgreSQL-specific schema. Covers best-practices, data types, indexing,...)
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/database-design/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/database-design/agents/database-architect.md` [agent definition, read]
  - `plugins/database-design/agents/sql-pro.md` [agent definition, read]
  - `plugins/database-design/skills/postgresql/SKILL.md` [skill instruction, read]

### `database-migrations`

- Purpose: Database migration automation, observability, and cross-database migration strategies
- File count: 5
- Component counts: agents 2; commands 2; skills 0; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `database-admin` (Expert database administrator specializing in modern cloud databases, automation, and reliability engineering. Master...); `database-optimizer` (Expert database optimizer specializing in modern performance tuning, query optimization, and scalable architectures. ...)
- Commands and workflow shape: `migration-observability` (Migration monitoring, CDC, and observability infrastructure); `sql-migrations` (SQL database migrations with zero-downtime strategies for PostgreSQL, MySQL, SQL Server)
- Skills and activation patterns: none found
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/database-migrations/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/database-migrations/agents/database-admin.md` [agent definition, read]
  - `plugins/database-migrations/agents/database-optimizer.md` [agent definition, read]
  - `plugins/database-migrations/commands/migration-observability.md` [command workflow, read]
  - `plugins/database-migrations/commands/sql-migrations.md` [command workflow, read]

### `debugging-toolkit`

- Purpose: Interactive debugging, developer experience optimization, and smart debugging workflows
- File count: 4
- Component counts: agents 2; commands 1; skills 0; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: high priority
- Too domain-specific or heavy: review before adoption; distill only patterns
- Agents and roles: `debugger` (Debugging specialist for errors, test failures, and unexpected behavior. Use proactively when encountering any issues.); `dx-optimizer` (Developer Experience specialist. Improves tooling, setup, and workflows. Use PROACTIVELY when setting up new projects...)
- Commands and workflow shape: `smart-debug` (Context: You are an expert AI-assisted debugging specialist with deep knowledge of modern debugging tools, observabil...)
- Skills and activation patterns: none found
- High-priority distillation:
  - Adopt bounded roles, explicit ownership, progressive references, and review/checklist shapes.
  - Do not adopt Claude-only slash command syntax, marketplace install flow, tmux teammate assumptions, or hidden authority gates.
  - Codex mapping: capability pack plus optional custom agents, prompt recipes, and skills selected by the PM.
- Files:
  - `plugins/debugging-toolkit/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/debugging-toolkit/agents/debugger.md` [agent definition, read]
  - `plugins/debugging-toolkit/agents/dx-optimizer.md` [agent definition, read]
  - `plugins/debugging-toolkit/commands/smart-debug.md` [command workflow, read]

### `dependency-management`

- Purpose: Dependency auditing, version management, and security vulnerability scanning
- File count: 3
- Component counts: agents 1; commands 1; skills 0; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `legacy-modernizer` (Refactor legacy codebases, migrate outdated frameworks, and implement gradual modernization. Handles technical debt, ...)
- Commands and workflow shape: `deps-audit` (Dependency Audit and Security Analysis: You are a dependency security expert specializing in vulnerability scanning, ...)
- Skills and activation patterns: none found
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/dependency-management/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/dependency-management/agents/legacy-modernizer.md` [agent definition, read]
  - `plugins/dependency-management/commands/deps-audit.md` [command workflow, read]

### `deployment-strategies`

- Purpose: Deployment patterns, rollback automation, and infrastructure templates
- File count: 3
- Component counts: agents 2; commands 0; skills 0; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `deployment-engineer` (Expert deployment engineer specializing in modern CI/CD pipelines, GitOps workflows, and advanced deployment automati...); `terraform-specialist` (Expert Terraform/OpenTofu specialist mastering advanced IaC automation, state management, and enterprise infrastructu...)
- Commands and workflow shape: none found
- Skills and activation patterns: none found
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/deployment-strategies/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/deployment-strategies/agents/deployment-engineer.md` [agent definition, read]
  - `plugins/deployment-strategies/agents/terraform-specialist.md` [agent definition, read]

### `deployment-validation`

- Purpose: Pre-deployment checks, configuration validation, and deployment readiness assessment
- File count: 3
- Component counts: agents 1; commands 1; skills 0; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `cloud-architect` (Expert cloud architect specializing in AWS/Azure/GCP/OCI multi-cloud infrastructure design, advanced IaC (Terraform/O...)
- Commands and workflow shape: `config-validate` (Configuration Validation: You are a configuration management expert specializing in validating, testing, and ensuring...)
- Skills and activation patterns: none found
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/deployment-validation/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/deployment-validation/agents/cloud-architect.md` [agent definition, read]
  - `plugins/deployment-validation/commands/config-validate.md` [command workflow, read]

### `developer-essentials`

- Purpose: Essential developer skills including Git workflows, SQL optimization, error handling, code review, E2E testing, authentication, debugging, and monorepo management
- File count: 13
- Component counts: agents 1; commands 0; skills 11; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: high priority
- Too domain-specific or heavy: review before adoption; distill only patterns
- Agents and roles: `monorepo-architect` (Expert in monorepo architecture, build systems, and dependency management at scale. Masters Nx, Turborepo, Bazel, and...)
- Commands and workflow shape: none found
- Skills and activation patterns: `SKILL` (Master authentication and authorization patterns including JWT, OAuth2, session management, and RBAC to build secure,...); `SKILL` (Optimize Bazel builds for large-scale monorepos. Use when configuring Bazel, implementing remote execution, or optimi...); `SKILL` (Master effective code review practices to provide constructive feedback, catch bugs early, and foster knowledge shari...); `SKILL` (Master systematic debugging techniques, profiling tools, and root cause analysis to efficiently track down bugs acros...); `SKILL` (Master end-to-end testing with Playwright and Cypress to build reliable test suites that catch bugs, improve confiden...); `SKILL` (Master error handling patterns across languages including exceptions, Result types, error propagation, and graceful d...); `SKILL` (Master advanced Git workflows including rebasing, cherry-picking, bisect, worktrees, and reflog to maintain clean his...); `SKILL` (Master monorepo management with Turborepo, Nx, and pnpm workspaces to build efficient, scalable multi-package reposit...); +3 more
- High-priority distillation:
  - Adopt bounded roles, explicit ownership, progressive references, and review/checklist shapes.
  - Do not adopt Claude-only slash command syntax, marketplace install flow, tmux teammate assumptions, or hidden authority gates.
  - Codex mapping: capability pack plus optional custom agents, prompt recipes, and skills selected by the PM.
- Files:
  - `plugins/developer-essentials/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/developer-essentials/agents/monorepo-architect.md` [agent definition, read]
  - `plugins/developer-essentials/skills/auth-implementation-patterns/SKILL.md` [skill instruction, read]
  - `plugins/developer-essentials/skills/bazel-build-optimization/SKILL.md` [skill instruction, read]
  - `plugins/developer-essentials/skills/code-review-excellence/SKILL.md` [skill instruction, read]
  - `plugins/developer-essentials/skills/debugging-strategies/SKILL.md` [skill instruction, read]
  - `plugins/developer-essentials/skills/e2e-testing-patterns/SKILL.md` [skill instruction, read]
  - `plugins/developer-essentials/skills/error-handling-patterns/SKILL.md` [skill instruction, read]
  - `plugins/developer-essentials/skills/git-advanced-workflows/SKILL.md` [skill instruction, read]
  - `plugins/developer-essentials/skills/monorepo-management/SKILL.md` [skill instruction, read]
  - `plugins/developer-essentials/skills/nx-workspace-patterns/SKILL.md` [skill instruction, read]
  - `plugins/developer-essentials/skills/sql-optimization-patterns/SKILL.md` [skill instruction, read]
  - `plugins/developer-essentials/skills/turborepo-caching/SKILL.md` [skill instruction, read]

### `distributed-debugging`

- Purpose: Distributed system tracing and debugging across microservices
- File count: 4
- Component counts: agents 2; commands 1; skills 0; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: high priority
- Too domain-specific or heavy: review before adoption; distill only patterns
- Agents and roles: `devops-troubleshooter` (Expert DevOps troubleshooter specializing in rapid incident response, advanced debugging, and modern observability. M...); `error-detective` (Search logs and codebases for error patterns, stack traces, and anomalies. Correlates errors across systems and ident...)
- Commands and workflow shape: `debug-trace` (Debug and Trace Configuration: You are a debugging expert specializing in setting up comprehensive debugging environm...)
- Skills and activation patterns: none found
- High-priority distillation:
  - Adopt bounded roles, explicit ownership, progressive references, and review/checklist shapes.
  - Do not adopt Claude-only slash command syntax, marketplace install flow, tmux teammate assumptions, or hidden authority gates.
  - Codex mapping: capability pack plus optional custom agents, prompt recipes, and skills selected by the PM.
- Files:
  - `plugins/distributed-debugging/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/distributed-debugging/agents/devops-troubleshooter.md` [agent definition, read]
  - `plugins/distributed-debugging/agents/error-detective.md` [agent definition, read]
  - `plugins/distributed-debugging/commands/debug-trace.md` [command workflow, read]

### `documentation-generation`

- Purpose: OpenAPI specification generation, Mermaid diagram creation, tutorial writing, API reference documentation
- File count: 11
- Component counts: agents 5; commands 1; skills 3; references 1; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `api-documenter` (Master API documentation with OpenAPI 3.1, AI-powered tools, and modern developer experience practices. Create intera...); `docs-architect` (Creates comprehensive technical documentation from existing codebases. Analyzes architecture, design patterns, and im...); `mermaid-expert` (Create Mermaid diagrams for flowcharts, sequences, ERDs, and architectures. Masters syntax for all diagram types and ...); `reference-builder` (Creates exhaustive technical references and API documentation. Generates comprehensive parameter listings, configurat...); `tutorial-engineer` (Creates step-by-step tutorials and educational content from code. Transforms complex concepts into progressive learni...)
- Commands and workflow shape: `doc-generate` (Automated Documentation Generation: You are a documentation expert specializing in creating comprehensive, maintainab...)
- Skills and activation patterns: `SKILL` (Write and maintain Architecture Decision Records (ADRs) following best practices for technical decision documentation...); `SKILL` (Automate changelog generation from commits, PRs, and releases following Keep a Changelog format. Use when setting up ...); `SKILL` (Generate and maintain OpenAPI 3.1 specifications from code, design-first specs, and validation patterns. Use when cre...)
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/documentation-generation/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/documentation-generation/agents/api-documenter.md` [agent definition, read]
  - `plugins/documentation-generation/agents/docs-architect.md` [agent definition, read]
  - `plugins/documentation-generation/agents/mermaid-expert.md` [agent definition, read]
  - `plugins/documentation-generation/agents/reference-builder.md` [agent definition, read]
  - `plugins/documentation-generation/agents/tutorial-engineer.md` [agent definition, read]
  - `plugins/documentation-generation/commands/doc-generate.md` [command workflow, read]
  - `plugins/documentation-generation/skills/architecture-decision-records/SKILL.md` [skill instruction, read]
  - `plugins/documentation-generation/skills/changelog-automation/SKILL.md` [skill instruction, read]
  - `plugins/documentation-generation/skills/openapi-spec-generation/SKILL.md` [skill instruction, read]
  - `plugins/documentation-generation/skills/openapi-spec-generation/references/code-first-and-tooling.md` [skill reference, read]

### `documentation-standards`

- Purpose: HADS (Human-AI Document Standard) — semantic tagging convention for writing documentation that works efficiently for both human readers and AI models. Reduces token consumption and hallucination risk by separating machine-critical facts from human context.
- File count: 2
- Component counts: agents 0; commands 0; skills 1; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: none found
- Commands and workflow shape: none found
- Skills and activation patterns: `SKILL` (Use when writing technical documentation that needs to be readable by both humans and AI models, converting existing ...)
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/documentation-standards/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/documentation-standards/skills/hads/SKILL.md` [skill instruction, read]

### `dotnet-contribution`

- Purpose: Comprehensive .NET backend development with C#, ASP.NET Core, Entity Framework Core, and Dapper for production-grade applications
- File count: 8
- Component counts: agents 1; commands 0; skills 1; references 2; manifests 1; templates 2; source code 0; tests 0; other 1
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `dotnet-architect` (Expert .NET backend architect specializing in C#, ASP.NET Core, Entity Framework, Dapper, and enterprise application ...)
- Commands and workflow shape: none found
- Skills and activation patterns: `SKILL` (Master C#/.NET backend development patterns for building robust APIs, MCP servers, and enterprise applications. Cover...)
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/dotnet-contribution/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/dotnet-contribution/README.md` [documentation, read]
  - `plugins/dotnet-contribution/agents/dotnet-architect.md` [agent definition, read]
  - `plugins/dotnet-contribution/skills/dotnet-backend-patterns/SKILL.md` [skill instruction, read]
  - `plugins/dotnet-contribution/skills/dotnet-backend-patterns/assets/repository-template.cs` [skill reference, read]
  - `plugins/dotnet-contribution/skills/dotnet-backend-patterns/assets/service-template.cs` [skill reference, read]
  - `plugins/dotnet-contribution/skills/dotnet-backend-patterns/references/dapper-patterns.md` [skill reference, read]
  - `plugins/dotnet-contribution/skills/dotnet-backend-patterns/references/ef-core-best-practices.md` [skill reference, read]

### `error-debugging`

- Purpose: Error analysis, trace debugging, and multi-agent problem diagnosis
- File count: 6
- Component counts: agents 2; commands 3; skills 0; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: high priority
- Too domain-specific or heavy: review before adoption; distill only patterns
- Agents and roles: `debugger` (Debugging specialist for errors, test failures, and unexpected behavior. Use proactively when encountering any issues.); `error-detective` (Search logs and codebases for error patterns, stack traces, and anomalies. Correlates errors across systems and ident...)
- Commands and workflow shape: `error-analysis` (Error Analysis and Resolution: You are an expert error analysis specialist with deep expertise in debugging distribut...); `error-trace` (Error Tracking and Monitoring: You are an error tracking and observability expert specializing in implementing compre...); `multi-agent-review` (Multi-Agent Code Review Orchestration Tool: A sophisticated AI-powered code review system designed to provide compreh...)
- Skills and activation patterns: none found
- High-priority distillation:
  - Adopt bounded roles, explicit ownership, progressive references, and review/checklist shapes.
  - Do not adopt Claude-only slash command syntax, marketplace install flow, tmux teammate assumptions, or hidden authority gates.
  - Codex mapping: capability pack plus optional custom agents, prompt recipes, and skills selected by the PM.
- Files:
  - `plugins/error-debugging/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/error-debugging/agents/debugger.md` [agent definition, read]
  - `plugins/error-debugging/agents/error-detective.md` [agent definition, read]
  - `plugins/error-debugging/commands/error-analysis.md` [command workflow, read]
  - `plugins/error-debugging/commands/error-trace.md` [command workflow, read]
  - `plugins/error-debugging/commands/multi-agent-review.md` [command workflow, read]

### `error-diagnostics`

- Purpose: Error tracing, root cause analysis, and smart debugging for production systems
- File count: 6
- Component counts: agents 2; commands 3; skills 0; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: high priority
- Too domain-specific or heavy: review before adoption; distill only patterns
- Agents and roles: `debugger` (Debugging specialist for errors, test failures, and unexpected behavior. Use proactively when encountering any issues.); `error-detective` (Search logs and codebases for error patterns, stack traces, and anomalies. Correlates errors across systems and ident...)
- Commands and workflow shape: `error-analysis` (Analyze and resolve errors across the full application lifecycle — from stack traces to distributed tracing — using s...); `error-trace` (Set up error tracking and monitoring — implement structured logging, configure alerts, and integrate with error track...); `smart-debug` (AI-assisted smart debugging — parse error messages, stack traces, and failure patterns to identify root causes and pr...)
- Skills and activation patterns: none found
- High-priority distillation:
  - Adopt bounded roles, explicit ownership, progressive references, and review/checklist shapes.
  - Do not adopt Claude-only slash command syntax, marketplace install flow, tmux teammate assumptions, or hidden authority gates.
  - Codex mapping: capability pack plus optional custom agents, prompt recipes, and skills selected by the PM.
- Files:
  - `plugins/error-diagnostics/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/error-diagnostics/agents/debugger.md` [agent definition, read]
  - `plugins/error-diagnostics/agents/error-detective.md` [agent definition, read]
  - `plugins/error-diagnostics/commands/error-analysis.md` [command workflow, read]
  - `plugins/error-diagnostics/commands/error-trace.md` [command workflow, read]
  - `plugins/error-diagnostics/commands/smart-debug.md` [command workflow, read]

### `framework-migration`

- Purpose: Framework updates, migration planning, and architectural transformation workflows
- File count: 10
- Component counts: agents 2; commands 3; skills 4; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `architect-review` (Master software architect specializing in modern architecture patterns, clean architecture, microservices, event-driv...); `legacy-modernizer` (Refactor legacy codebases, migrate outdated frameworks, and implement gradual modernization. Handles technical debt, ...)
- Commands and workflow shape: `code-migrate` (Generate comprehensive migration plans and scripts for transitioning codebases between frameworks, languages, version...); `deps-upgrade` (Plan and execute safe, incremental dependency upgrades with minimal risk — including breaking-change migration paths ...); `legacy-modernize` (Orchestrate legacy system modernization using the strangler fig pattern with gradual component replacement)
- Skills and activation patterns: `SKILL` (Migrate from AngularJS to Angular using hybrid mode, incremental component rewriting, and dependency injection update...); `SKILL` (Execute database migrations across ORMs and platforms with zero-downtime strategies, data transformation, and rollbac...); `SKILL` (Manage major dependency version upgrades with compatibility analysis, staged rollout, and comprehensive testing. Use ...); `SKILL` (Upgrade React applications to latest versions, migrate from class components to hooks, and adopt concurrent features....)
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/framework-migration/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/framework-migration/agents/architect-review.md` [agent definition, read]
  - `plugins/framework-migration/agents/legacy-modernizer.md` [agent definition, read]
  - `plugins/framework-migration/commands/code-migrate.md` [command workflow, read]
  - `plugins/framework-migration/commands/deps-upgrade.md` [command workflow, read]
  - `plugins/framework-migration/commands/legacy-modernize.md` [command workflow, read]
  - `plugins/framework-migration/skills/angular-migration/SKILL.md` [skill instruction, read]
  - `plugins/framework-migration/skills/database-migration/SKILL.md` [skill instruction, read]
  - `plugins/framework-migration/skills/dependency-upgrade/SKILL.md` [skill instruction, read]
  - `plugins/framework-migration/skills/react-modernization/SKILL.md` [skill instruction, read]

### `frontend-mobile-development`

- Purpose: Frontend UI development and mobile application implementation across platforms
- File count: 9
- Component counts: agents 2; commands 1; skills 4; references 1; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `frontend-developer` (Build React components, implement responsive layouts, and handle client-side state management. Masters React 19, Next...); `mobile-developer` (Develop React Native, Flutter, or native mobile apps with modern architecture patterns. Masters cross-platform develo...)
- Commands and workflow shape: `component-scaffold` (React/React Native Component Scaffolding: You are a React component architecture expert specializing in scaffolding p...)
- Skills and activation patterns: `SKILL` (Master Next.js 14+ App Router with Server Components, streaming, parallel routes, and advanced data fetching. Use whe...); `SKILL` (Build production React Native apps with Expo, navigation, native modules, offline sync, and cross-platform patterns. ...); `SKILL` (Master modern React state management with Redux Toolkit, Zustand, Jotai, and React Query. Use when setting up global ...); `SKILL` (Build scalable design systems with Tailwind CSS v4, design tokens, component libraries, and responsive patterns. Use ...)
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/frontend-mobile-development/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/frontend-mobile-development/agents/frontend-developer.md` [agent definition, read]
  - `plugins/frontend-mobile-development/agents/mobile-developer.md` [agent definition, read]
  - `plugins/frontend-mobile-development/commands/component-scaffold.md` [command workflow, read]
  - `plugins/frontend-mobile-development/skills/nextjs-app-router-patterns/SKILL.md` [skill instruction, read]
  - `plugins/frontend-mobile-development/skills/react-native-architecture/SKILL.md` [skill instruction, read]
  - `plugins/frontend-mobile-development/skills/react-state-management/SKILL.md` [skill instruction, read]
  - `plugins/frontend-mobile-development/skills/tailwind-design-system/SKILL.md` [skill instruction, read]
  - `plugins/frontend-mobile-development/skills/tailwind-design-system/references/advanced-patterns.md` [skill reference, read]

### `frontend-mobile-security`

- Purpose: XSS prevention, CSRF protection, content security policies, mobile app security, and secure storage patterns
- File count: 5
- Component counts: agents 3; commands 1; skills 0; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: high priority
- Too domain-specific or heavy: review before adoption; distill only patterns
- Agents and roles: `frontend-developer` (Build React components, implement responsive layouts, and handle client-side state management. Masters React 19, Next...); `frontend-security-coder` (Expert in secure frontend coding practices specializing in XSS prevention, output sanitization, and client-side secur...); `mobile-security-coder` (Expert in secure mobile coding practices specializing in input validation, WebView security, and mobile-specific secu...)
- Commands and workflow shape: `xss-scan` (XSS Vulnerability Scanner for Frontend Code: You are a frontend security specialist focusing on Cross-Site Scripting ...)
- Skills and activation patterns: none found
- High-priority distillation:
  - Adopt bounded roles, explicit ownership, progressive references, and review/checklist shapes.
  - Do not adopt Claude-only slash command syntax, marketplace install flow, tmux teammate assumptions, or hidden authority gates.
  - Codex mapping: capability pack plus optional custom agents, prompt recipes, and skills selected by the PM.
- Files:
  - `plugins/frontend-mobile-security/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/frontend-mobile-security/agents/frontend-developer.md` [agent definition, read]
  - `plugins/frontend-mobile-security/agents/frontend-security-coder.md` [agent definition, read]
  - `plugins/frontend-mobile-security/agents/mobile-security-coder.md` [agent definition, read]
  - `plugins/frontend-mobile-security/commands/xss-scan.md` [command workflow, read]

### `full-stack-orchestration`

- Purpose: End-to-end feature orchestration with testing, security, performance, and deployment
- File count: 6
- Component counts: agents 4; commands 1; skills 0; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `deployment-engineer` (Expert deployment engineer specializing in modern CI/CD pipelines, GitOps workflows, and advanced deployment automati...); `performance-engineer` (Expert performance engineer specializing in modern observability, application optimization, and scalable system perfo...); `security-auditor` (Expert security auditor specializing in DevSecOps, comprehensive cybersecurity, and compliance frameworks. Masters vu...); `test-automator` (Master AI-powered test automation with modern frameworks, self-healing tests, and comprehensive quality engineering. ...)
- Commands and workflow shape: `full-stack-feature` (Orchestrate end-to-end full-stack feature development across backend, frontend, database, and infrastructure layers)
- Skills and activation patterns: none found
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/full-stack-orchestration/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/full-stack-orchestration/agents/deployment-engineer.md` [agent definition, read]
  - `plugins/full-stack-orchestration/agents/performance-engineer.md` [agent definition, read]
  - `plugins/full-stack-orchestration/agents/security-auditor.md` [agent definition, read]
  - `plugins/full-stack-orchestration/agents/test-automator.md` [agent definition, read]
  - `plugins/full-stack-orchestration/commands/full-stack-feature.md` [command workflow, read]

### `functional-programming`

- Purpose: Functional programming with Elixir, OTP patterns, Phoenix framework, and distributed systems
- File count: 3
- Component counts: agents 2; commands 0; skills 0; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `elixir-pro` (Write idiomatic Elixir code with OTP patterns, supervision trees, and Phoenix LiveView. Masters concurrency, fault to...); `haskell-pro` (Expert Haskell engineer specializing in advanced type systems, pure functional design, and high-reliability software....)
- Commands and workflow shape: none found
- Skills and activation patterns: none found
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/functional-programming/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/functional-programming/agents/elixir-pro.md` [agent definition, read]
  - `plugins/functional-programming/agents/haskell-pro.md` [agent definition, read]

### `game-development`

- Purpose: Unity game development with C# scripting, Minecraft server plugin development with Bukkit/Spigot APIs
- File count: 6
- Component counts: agents 2; commands 0; skills 2; references 1; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `minecraft-bukkit-pro` (Master Minecraft server plugin development with Bukkit, Spigot, and Paper APIs. Specializes in event-driven architect...); `unity-developer` (Build Unity games with optimized C# scripts, efficient rendering, and proper asset management. Masters Unity 6 LTS, U...)
- Commands and workflow shape: none found
- Skills and activation patterns: `SKILL` (Master Godot 4 GDScript patterns including signals, scenes, state machines, and optimization. Use when building Godot...); `SKILL` (Master Unity ECS (Entity Component System) with DOTS, Jobs, and Burst for high-performance game development. Use when...)
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/game-development/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/game-development/agents/minecraft-bukkit-pro.md` [agent definition, read]
  - `plugins/game-development/agents/unity-developer.md` [agent definition, read]
  - `plugins/game-development/skills/godot-gdscript-patterns/SKILL.md` [skill instruction, read]
  - `plugins/game-development/skills/godot-gdscript-patterns/references/advanced-patterns.md` [skill reference, read]
  - `plugins/game-development/skills/unity-ecs-patterns/SKILL.md` [skill instruction, read]

### `git-pr-workflows`

- Purpose: Git workflow automation, pull request enhancement, and team onboarding processes
- File count: 5
- Component counts: agents 1; commands 3; skills 0; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: high priority
- Too domain-specific or heavy: review before adoption; distill only patterns
- Agents and roles: `code-reviewer` (Elite code review expert specializing in modern AI-powered code analysis, security vulnerabilities, performance optim...)
- Commands and workflow shape: `git-workflow` (Orchestrate git workflow from code review through PR creation with quality gates); `onboard` (Onboard: You are an **expert onboarding specialist and knowledge transfer architect** with deep experience in remote-...); `pr-enhance` (Pull Request Enhancement: You are a PR optimization expert specializing in creating high-quality pull requests that f...)
- Skills and activation patterns: none found
- High-priority distillation:
  - Adopt bounded roles, explicit ownership, progressive references, and review/checklist shapes.
  - Do not adopt Claude-only slash command syntax, marketplace install flow, tmux teammate assumptions, or hidden authority gates.
  - Codex mapping: capability pack plus optional custom agents, prompt recipes, and skills selected by the PM.
- Files:
  - `plugins/git-pr-workflows/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/git-pr-workflows/agents/code-reviewer.md` [agent definition, read]
  - `plugins/git-pr-workflows/commands/git-workflow.md` [command workflow, read]
  - `plugins/git-pr-workflows/commands/onboard.md` [command workflow, read]
  - `plugins/git-pr-workflows/commands/pr-enhance.md` [command workflow, read]

### `hr-legal-compliance`

- Purpose: HR policy documentation, legal compliance templates (GDPR/SOC2/HIPAA), employment contracts, and regulatory documentation
- File count: 5
- Component counts: agents 2; commands 0; skills 2; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `hr-pro` (Professional, ethical HR partner for hiring, onboarding/offboarding, PTO and leave, performance, compliant policies, ...); `legal-advisor` (Draft privacy policies, terms of service, disclaimers, and legal notices. Creates GDPR-compliant texts, cookie polici...)
- Commands and workflow shape: none found
- Skills and activation patterns: `SKILL` (Create employment contracts, offer letters, and HR policy documents following legal best practices. Use when drafting...); `SKILL` (Implement GDPR-compliant data handling with consent management, data subject rights, and privacy by design. Use when ...)
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/hr-legal-compliance/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/hr-legal-compliance/agents/hr-pro.md` [agent definition, read]
  - `plugins/hr-legal-compliance/agents/legal-advisor.md` [agent definition, read]
  - `plugins/hr-legal-compliance/skills/employment-contract-templates/SKILL.md` [skill instruction, read]
  - `plugins/hr-legal-compliance/skills/gdpr-data-handling/SKILL.md` [skill instruction, read]

### `incident-response`

- Purpose: Production incident management, triage workflows, and automated incident resolution
- File count: 12
- Component counts: agents 6; commands 2; skills 3; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `code-reviewer` (Reviews code for logic flaws, type safety gaps, error handling issues, architectural concerns, and similar vulnerabil...); `debugger` (Performs deep root cause analysis through code path tracing, git bisect automation, dependency analysis, and systemat...); `devops-troubleshooter` (Expert DevOps troubleshooter specializing in rapid incident response, advanced debugging, and modern observability. M...); `error-detective` (Analyzes error traces, logs, and observability data to identify error signatures, reproduction steps, user impact, an...); `incident-responder` (Expert SRE incident responder specializing in rapid problem resolution, modern observability, and comprehensive incid...); `test-automator` (Creates comprehensive test suites including unit, integration, regression, and security tests. Validates fixes with f...)
- Commands and workflow shape: `incident-response` (Orchestrate multi-agent incident response with modern SRE practices for rapid resolution and learning); `smart-fix` (Intelligent issue resolution with multi-agent debugging, root cause analysis, and verified fix implementation)
- Skills and activation patterns: `SKILL` (Create structured incident response runbooks with step-by-step procedures, escalation paths, and recovery actions. Us...); `SKILL` (Master on-call shift handoffs with context transfer, escalation procedures, and documentation. Use this skill when tr...); `SKILL` (Write effective blameless postmortems with root cause analysis, timelines, and action items. Use when conducting inci...)
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/incident-response/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/incident-response/agents/code-reviewer.md` [agent definition, read]
  - `plugins/incident-response/agents/debugger.md` [agent definition, read]
  - `plugins/incident-response/agents/devops-troubleshooter.md` [agent definition, read]
  - `plugins/incident-response/agents/error-detective.md` [agent definition, read]
  - `plugins/incident-response/agents/incident-responder.md` [agent definition, read]
  - `plugins/incident-response/agents/test-automator.md` [agent definition, read]
  - `plugins/incident-response/commands/incident-response.md` [command workflow, read]
  - `plugins/incident-response/commands/smart-fix.md` [command workflow, read]
  - `plugins/incident-response/skills/incident-runbook-templates/SKILL.md` [skill instruction, read]
  - `plugins/incident-response/skills/on-call-handoff-patterns/SKILL.md` [skill instruction, read]
  - `plugins/incident-response/skills/postmortem-writing/SKILL.md` [skill instruction, read]

### `javascript-typescript`

- Purpose: JavaScript and TypeScript development with ES6+, Node.js, React, and modern web frameworks
- File count: 11
- Component counts: agents 2; commands 1; skills 4; references 3; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: high priority
- Too domain-specific or heavy: review before adoption; distill only patterns
- Agents and roles: `javascript-pro` (Master modern JavaScript with ES6+, async patterns, and Node.js APIs. Handles promises, event loops, and browser/Node...); `typescript-pro` (Master TypeScript with advanced types, generics, and strict type safety. Handles complex type systems, decorators, an...)
- Commands and workflow shape: `typescript-scaffold` (TypeScript Project Scaffolding: You are a TypeScript project architecture expert specializing in scaffolding producti...)
- Skills and activation patterns: `SKILL` (Implement comprehensive testing strategies using Jest, Vitest, and Testing Library for unit tests, integration tests,...); `SKILL` (Master ES6+ features including async/await, destructuring, spread operators, arrow functions, promises, modules, iter...); `SKILL` (Build production-ready Node.js backend services with Express/Fastify, implementing middleware patterns, error handlin...); `SKILL` (Master TypeScript's advanced type system including generics, conditional types, mapped types, template literals, and ...)
- High-priority distillation:
  - Adopt bounded roles, explicit ownership, progressive references, and review/checklist shapes.
  - Do not adopt Claude-only slash command syntax, marketplace install flow, tmux teammate assumptions, or hidden authority gates.
  - Codex mapping: capability pack plus optional custom agents, prompt recipes, and skills selected by the PM.
- Files:
  - `plugins/javascript-typescript/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/javascript-typescript/agents/javascript-pro.md` [agent definition, read]
  - `plugins/javascript-typescript/agents/typescript-pro.md` [agent definition, read]
  - `plugins/javascript-typescript/commands/typescript-scaffold.md` [command workflow, read]
  - `plugins/javascript-typescript/skills/javascript-testing-patterns/SKILL.md` [skill instruction, read]
  - `plugins/javascript-typescript/skills/javascript-testing-patterns/references/advanced-testing-patterns.md` [skill reference, read]
  - `plugins/javascript-typescript/skills/modern-javascript-patterns/SKILL.md` [skill instruction, read]
  - `plugins/javascript-typescript/skills/modern-javascript-patterns/references/advanced-patterns.md` [skill reference, read]
  - `plugins/javascript-typescript/skills/nodejs-backend-patterns/SKILL.md` [skill instruction, read]
  - `plugins/javascript-typescript/skills/nodejs-backend-patterns/references/advanced-patterns.md` [skill reference, read]
  - `plugins/javascript-typescript/skills/typescript-advanced-types/SKILL.md` [skill instruction, read]

### `julia-development`

- Purpose: Modern Julia development with Julia 1.10+, package management, scientific computing, high-performance numerical code, and production best practices
- File count: 2
- Component counts: agents 1; commands 0; skills 0; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `julia-pro` (Master Julia 1.10+ with modern features, performance optimization, multiple dispatch, and production-ready practices....)
- Commands and workflow shape: none found
- Skills and activation patterns: none found
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/julia-development/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/julia-development/agents/julia-pro.md` [agent definition, read]

### `jvm-languages`

- Purpose: JVM language development including Java, Scala, and C# with enterprise patterns and frameworks
- File count: 4
- Component counts: agents 3; commands 0; skills 0; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `csharp-pro` (Write modern C# code with advanced features like records, pattern matching, and async/await. Optimizes .NET applicati...); `java-pro` (Master Java 21+ with modern features like virtual threads, pattern matching, and Spring Boot 3.x. Expert in the lates...); `scala-pro` (Master enterprise-grade Scala development with functional programming, distributed systems, and big data processing. ...)
- Commands and workflow shape: none found
- Skills and activation patterns: none found
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/jvm-languages/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/jvm-languages/agents/csharp-pro.md` [agent definition, read]
  - `plugins/jvm-languages/agents/java-pro.md` [agent definition, read]
  - `plugins/jvm-languages/agents/scala-pro.md` [agent definition, read]

### `kubernetes-operations`

- Purpose: Kubernetes manifest generation, networking configuration, security policies, observability setup, GitOps workflows, and auto-scaling
- File count: 19
- Component counts: agents 1; commands 0; skills 5; references 6; manifests 1; templates 6; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `kubernetes-architect` (Expert Kubernetes architect specializing in cloud-native infrastructure, advanced GitOps workflows (ArgoCD/Flux), and...)
- Commands and workflow shape: none found
- Skills and activation patterns: `SKILL` (Implement GitOps workflows with ArgoCD and Flux for automated, declarative Kubernetes deployments with continuous rec...); `SKILL` (Design, organize, and manage Helm charts for templating and packaging Kubernetes applications with reusable configura...); `validate-chart` (!/bin/bash: set -e CHART_DIR="${1:-.}" RELEASE_NAME="test-release" echo "════════════════════════════════════════════...); `SKILL` (Create production-ready Kubernetes manifests for Deployments, Services, ConfigMaps, and Secrets following best practi...); `SKILL` (Implement Kubernetes security policies including NetworkPolicy, PodSecurityPolicy, and RBAC for production-grade secu...)
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files: 19 total; complete paths are in the JSON manifest.
- Reference/template examples: `plugins/kubernetes-operations/skills/gitops-workflow/references/argocd-setup.md`, `plugins/kubernetes-operations/skills/gitops-workflow/references/sync-policies.md`, `plugins/kubernetes-operations/skills/helm-chart-scaffolding/references/chart-structure.md`, `plugins/kubernetes-operations/skills/k8s-manifest-generator/references/deployment-spec.md`, `plugins/kubernetes-operations/skills/k8s-manifest-generator/references/service-spec.md`, `plugins/kubernetes-operations/skills/k8s-security-policies/references/rbac-patterns.md`

### `llm-application-dev`

- Purpose: LLM application development with LangGraph, RAG systems, vector search, and AI agent architectures for Claude 4.6 and GPT-5.4
- File count: 24
- Component counts: agents 3; commands 3; skills 9; references 5; manifests 1; templates 2; source code 0; tests 0; other 1
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `ai-engineer` (Build production-ready LLM applications, advanced RAG systems, and intelligent agents. Implements vector search, mult...); `prompt-engineer` (Expert prompt engineer specializing in advanced prompting techniques, LLM optimization, and AI system design. Masters...); `vector-database-engineer` (Expert in vector databases, embedding strategies, and semantic search implementation. Masters Pinecone, Weaviate, Qdr...)
- Commands and workflow shape: `ai-assistant` (Build AI assistant application with NLU, dialog management, and integrations); `langchain-agent` (Create LangGraph-based agent with modern patterns); `prompt-optimize` (Optimize prompts for production with CoT, few-shot, and constitutional AI patterns)
- Skills and activation patterns: `SKILL` (Select and optimize embedding models for semantic search and RAG applications. Use when choosing embedding models, im...); `SKILL` (Combine vector and keyword search for improved retrieval. Use when implementing RAG systems, building search engines,...); `SKILL` (Design LLM applications using LangChain 1.x and LangGraph for agents, memory, and tool integration. Use when building...); `SKILL` (Implement comprehensive evaluation strategies for LLM applications using automated metrics, human feedback, and bench...); `SKILL` (Master advanced prompt engineering techniques to maximize LLM performance, reliability, and controllability in produc...); `optimize-prompt` (!/usr/bin/env python3: """ Prompt Optimization Script Automatically test and optimize prompts using A/B testing and m...); `SKILL` (Build Retrieval-Augmented Generation (RAG) systems for LLM applications with vector databases and semantic search. Us...); `SKILL` (Implement efficient similarity search with vector databases. Use when building semantic search, implementing nearest ...); +1 more
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files: 24 total; complete paths are in the JSON manifest.
- Reference/template examples: `plugins/llm-application-dev/skills/prompt-engineering-patterns/references/chain-of-thought.md`, `plugins/llm-application-dev/skills/prompt-engineering-patterns/references/few-shot-learning.md`, `plugins/llm-application-dev/skills/prompt-engineering-patterns/references/prompt-optimization.md`, `plugins/llm-application-dev/skills/prompt-engineering-patterns/references/prompt-templates.md`, `plugins/llm-application-dev/skills/prompt-engineering-patterns/references/system-prompts.md`, `plugins/llm-application-dev/skills/prompt-engineering-patterns/assets/few-shot-examples.json`

### `machine-learning-ops`

- Purpose: ML model training pipelines, hyperparameter tuning, model deployment automation, experiment tracking, and MLOps workflows
- File count: 6
- Component counts: agents 3; commands 1; skills 1; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `data-scientist` (Expert data scientist for advanced analytics, machine learning, and statistical modeling. Handles complex data analys...); `ml-engineer` (Build production ML systems with PyTorch 2.x, TensorFlow, and modern ML frameworks. Implements model serving, feature...); `mlops-engineer` (Build comprehensive ML pipelines, experiment tracking, and model registries with MLflow, Kubeflow, and modern MLOps t...)
- Commands and workflow shape: `ml-pipeline` (Machine Learning Pipeline - Multi-Agent MLOps Orchestration: Design and implement a complete ML pipeline for: $ARGUME...)
- Skills and activation patterns: `SKILL` (Build end-to-end MLOps pipelines from data preparation through model training, validation, and production deployment....)
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/machine-learning-ops/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/machine-learning-ops/agents/data-scientist.md` [agent definition, read]
  - `plugins/machine-learning-ops/agents/ml-engineer.md` [agent definition, read]
  - `plugins/machine-learning-ops/agents/mlops-engineer.md` [agent definition, read]
  - `plugins/machine-learning-ops/commands/ml-pipeline.md` [command workflow, read]
  - `plugins/machine-learning-ops/skills/ml-pipeline-workflow/SKILL.md` [skill instruction, read]

### `meigen-ai-design`

- Purpose: AI image generation with creative workflow orchestration, parallel multi-direction output, prompt engineering, and a 1,300+ curated inspiration library. Requires MeiGen MCP server (supports MeiGen Cloud, local ComfyUI, and OpenAI-compatible APIs).
- File count: 7
- Component counts: agents 3; commands 2; skills 0; references 0; manifests 1; templates 0; source code 0; tests 0; other 1
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `gallery-researcher` (>-); `image-generator` (>-); `prompt-crafter` (>-)
- Commands and workflow shape: `find` (>-); `gen` (>-)
- Skills and activation patterns: none found
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/meigen-ai-design/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/meigen-ai-design/README.md` [documentation, read]
  - `plugins/meigen-ai-design/agents/gallery-researcher.md` [agent definition, read]
  - `plugins/meigen-ai-design/agents/image-generator.md` [agent definition, read]
  - `plugins/meigen-ai-design/agents/prompt-crafter.md` [agent definition, read]
  - `plugins/meigen-ai-design/commands/find.md` [command workflow, read]
  - `plugins/meigen-ai-design/commands/gen.md` [command workflow, read]

### `multi-platform-apps`

- Purpose: Cross-platform application development coordinating web, iOS, Android, and desktop implementations
- File count: 8
- Component counts: agents 6; commands 1; skills 0; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `backend-architect` (Expert backend architect specializing in scalable API design, microservices architecture, and distributed systems. Ma...); `flutter-expert` (Master Flutter development with Dart 3, advanced widgets, and multi-platform deployment. Handles state management, an...); `frontend-developer` (Build React components, implement responsive layouts, and handle client-side state management. Masters React 19, Next...); `ios-developer` (Develop native iOS applications with Swift/SwiftUI. Masters iOS 18, SwiftUI, UIKit integration, Core Data, networking...); `mobile-developer` (Develop React Native, Flutter, or native mobile apps with modern architecture patterns. Masters cross-platform develo...); `ui-ux-designer` (Create interface designs, wireframes, and design systems. Masters user research, accessibility standards, and modern ...)
- Commands and workflow shape: `multi-platform` (Orchestrate cross-platform feature development across web, mobile, and desktop with API-first architecture)
- Skills and activation patterns: none found
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/multi-platform-apps/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/multi-platform-apps/agents/backend-architect.md` [agent definition, read]
  - `plugins/multi-platform-apps/agents/flutter-expert.md` [agent definition, read]
  - `plugins/multi-platform-apps/agents/frontend-developer.md` [agent definition, read]
  - `plugins/multi-platform-apps/agents/ios-developer.md` [agent definition, read]
  - `plugins/multi-platform-apps/agents/mobile-developer.md` [agent definition, read]
  - `plugins/multi-platform-apps/agents/ui-ux-designer.md` [agent definition, read]
  - `plugins/multi-platform-apps/commands/multi-platform.md` [command workflow, read]

### `observability-monitoring`

- Purpose: Metrics collection, logging infrastructure, distributed tracing, SLO implementation, and monitoring dashboards
- File count: 11
- Component counts: agents 4; commands 2; skills 4; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `database-optimizer` (Expert database optimizer specializing in modern performance tuning, query optimization, and scalable architectures. ...); `network-engineer` (Expert network engineer specializing in modern cloud networking, security architectures, and performance optimization...); `observability-engineer` (Build production-ready monitoring, logging, and tracing systems. Implements comprehensive observability strategies, S...); `performance-engineer` (Expert performance engineer specializing in modern observability, application optimization, and scalable system perfo...)
- Commands and workflow shape: `monitor-setup` (Monitoring and Observability Setup: You are a monitoring and observability expert specializing in implementing compre...); `slo-implement` (SLO Implementation Guide: You are an SLO (Service Level Objective) expert specializing in implementing reliability st...)
- Skills and activation patterns: `SKILL` (Implement distributed tracing with Jaeger and Tempo to track requests across microservices and identify performance b...); `SKILL` (Create and manage production Grafana dashboards for real-time visualization of system and application metrics. Use wh...); `SKILL` (Set up Prometheus for comprehensive metric collection, storage, and monitoring of infrastructure and applications. Us...); `SKILL` (Define and implement Service Level Indicators (SLIs) and Service Level Objectives (SLOs) with error budgets and alert...)
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/observability-monitoring/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/observability-monitoring/agents/database-optimizer.md` [agent definition, read]
  - `plugins/observability-monitoring/agents/network-engineer.md` [agent definition, read]
  - `plugins/observability-monitoring/agents/observability-engineer.md` [agent definition, read]
  - `plugins/observability-monitoring/agents/performance-engineer.md` [agent definition, read]
  - `plugins/observability-monitoring/commands/monitor-setup.md` [command workflow, read]
  - `plugins/observability-monitoring/commands/slo-implement.md` [command workflow, read]
  - `plugins/observability-monitoring/skills/distributed-tracing/SKILL.md` [skill instruction, read]
  - `plugins/observability-monitoring/skills/grafana-dashboards/SKILL.md` [skill instruction, read]
  - `plugins/observability-monitoring/skills/prometheus-configuration/SKILL.md` [skill instruction, read]
  - `plugins/observability-monitoring/skills/slo-implementation/SKILL.md` [skill instruction, read]

### `payment-processing`

- Purpose: Payment gateway integration with Stripe, PayPal, checkout flow implementation, subscription billing, and PCI compliance
- File count: 6
- Component counts: agents 1; commands 0; skills 4; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `payment-integration` (Integrate Stripe, PayPal, and payment processors. Handles checkout flows, subscriptions, webhooks, and PCI compliance...)
- Commands and workflow shape: none found
- Skills and activation patterns: `SKILL` (Build automated billing systems for recurring payments, invoicing, subscription lifecycle, and dunning management. Us...); `SKILL` (Integrate PayPal payment processing with support for express checkout, subscriptions, and refund management. Use when...); `SKILL` (Implement PCI DSS compliance requirements for secure handling of payment card data and payment systems. Use when secu...); `SKILL` (Implement Stripe payment processing for robust, PCI-compliant payment flows including checkout, subscriptions, and we...)
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/payment-processing/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/payment-processing/agents/payment-integration.md` [agent definition, read]
  - `plugins/payment-processing/skills/billing-automation/SKILL.md` [skill instruction, read]
  - `plugins/payment-processing/skills/paypal-integration/SKILL.md` [skill instruction, read]
  - `plugins/payment-processing/skills/pci-compliance/SKILL.md` [skill instruction, read]
  - `plugins/payment-processing/skills/stripe-integration/SKILL.md` [skill instruction, read]

### `performance-testing-review`

- Purpose: Performance analysis, test coverage review, and AI-powered code quality assessment
- File count: 5
- Component counts: agents 2; commands 2; skills 0; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: high priority
- Too domain-specific or heavy: review before adoption; distill only patterns
- Agents and roles: `performance-engineer` (Expert performance engineer specializing in modern observability, application optimization, and scalable system perfo...); `test-automator` (Master AI-powered test automation with modern frameworks, self-healing tests, and comprehensive quality engineering. ...)
- Commands and workflow shape: `ai-review` (AI-Powered Code Review Specialist: You are an expert AI-powered code review specialist combining automated static ana...); `multi-agent-review` (Multi-Agent Code Review Orchestration Tool: A sophisticated AI-powered code review system designed to provide compreh...)
- Skills and activation patterns: none found
- High-priority distillation:
  - Adopt bounded roles, explicit ownership, progressive references, and review/checklist shapes.
  - Do not adopt Claude-only slash command syntax, marketplace install flow, tmux teammate assumptions, or hidden authority gates.
  - Codex mapping: capability pack plus optional custom agents, prompt recipes, and skills selected by the PM.
- Files:
  - `plugins/performance-testing-review/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/performance-testing-review/agents/performance-engineer.md` [agent definition, read]
  - `plugins/performance-testing-review/agents/test-automator.md` [agent definition, read]
  - `plugins/performance-testing-review/commands/ai-review.md` [command workflow, read]
  - `plugins/performance-testing-review/commands/multi-agent-review.md` [command workflow, read]

### `plugin-eval`

- Purpose: plugin-eval
- File count: 40
- Component counts: agents 2; commands 3; skills 1; references 1; manifests 1; templates 0; source code 14; tests 14; other 4
- Useful for PM-main workflow: high priority
- Too domain-specific or heavy: review before adoption; distill only patterns
- Agents and roles: `eval-judge` (LLM judge for plugin quality assessment. Scores skills on triggering accuracy, orchestration fitness, output quality,...); `eval-orchestrator` (Orchestrates plugin quality evaluation. Use PROACTIVELY when evaluating, scoring, or certifying plugin quality.)
- Commands and workflow shape: `certify` (Full quality certification with badge); `compare` (Compare two skills head-to-head); `eval` (Evaluate a plugin or skill for quality)
- Skills and activation patterns: `SKILL` (PluginEval quality methodology — dimensions, rubrics, statistical methods, and scoring formulas. Use this skill when ...)
- High-priority distillation:
  - Adopt bounded roles, explicit ownership, progressive references, and review/checklist shapes.
  - Do not adopt Claude-only slash command syntax, marketplace install flow, tmux teammate assumptions, or hidden authority gates.
  - Codex mapping: capability pack plus optional custom agents, prompt recipes, and skills selected by the PM.
- Files: 40 total; complete paths are in the JSON manifest.
- Reference/template examples: `plugins/plugin-eval/skills/evaluation-methodology/references/rubrics.md`

### `protect-mcp`

- Purpose: Cedar policy enforcement + Ed25519 signed receipts for every Claude Code tool call. First cryptographic governance plugin — receipts independently verifiable offline.
- File count: 18
- Component counts: agents 2; commands 2; skills 1; references 0; manifests 1; templates 0; source code 3; tests 0; other 9
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `policy-enforcer` (Cedar policy author and reviewer for Claude Code tool calls. Writes, audits, and explains Cedar policies that govern ...); `receipt-verifier` (Expert in Ed25519 signed receipts, JCS canonicalization, hash chains, and offline verification. Use when you need to ...)
- Commands and workflow shape: `audit-chain` (Walk the receipt chain in ./receipts/ verifying every signature and hash link. Detects insertions, deletions, and tam...); `verify-receipt` (Verify a single Ed25519-signed receipt file. Returns exit 0 if valid, 1 if tampered, 2 if malformed.)
- Skills and activation patterns: `SKILL` (Configure Cedar policy enforcement and Ed25519 signed receipts for Claude Code tool calls. Use when setting up projec...)
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/protect-mcp/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/protect-mcp/README.md` [documentation, read]
  - `plugins/protect-mcp/agents/policy-enforcer.md` [agent definition, read]
  - `plugins/protect-mcp/agents/receipt-verifier.md` [agent definition, read]
  - `plugins/protect-mcp/commands/audit-chain.md` [command workflow, read]
  - `plugins/protect-mcp/commands/verify-receipt.md` [command workflow, read]
  - `plugins/protect-mcp/hooks/hooks.json` [documentation, read]
  - `plugins/protect-mcp/skills/protect-mcp-setup/SKILL.md` [skill instruction, read]
  - `plugins/protect-mcp/test/README.md` [documentation, read]
  - `plugins/protect-mcp/test/expected/receipt-schema.json` [documentation, read]
  - `plugins/protect-mcp/test/fixtures/posttool-signing-input.json` [documentation, read]
  - `plugins/protect-mcp/test/fixtures/pretool-allow-bash-safe.json` [documentation, read]
  - `plugins/protect-mcp/test/fixtures/pretool-allow-read.json` [documentation, read]
  - `plugins/protect-mcp/test/fixtures/pretool-deny-bash-destructive.json` [documentation, read]
  - `plugins/protect-mcp/test/fixtures/pretool-deny-write.json` [documentation, read]
  - `plugins/protect-mcp/test/fixtures/test-policy.cedar` [source code, read]
  - `plugins/protect-mcp/test/run-tests.sh` [source code, read]
  - `plugins/protect-mcp/test/verify-fixtures.sh` [source code, read]

### `python-development`

- Purpose: Modern Python development with Python 3.12+, Django, FastAPI, async patterns, and production best practices
- File count: 25
- Component counts: agents 3; commands 1; skills 16; references 4; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: high priority
- Too domain-specific or heavy: review before adoption; distill only patterns
- Agents and roles: `django-pro` (Master Django 5.x with async views, DRF, Celery, and Django Channels. Build scalable web applications with proper arc...); `fastapi-pro` (Build high-performance async APIs with FastAPI, SQLAlchemy 2.0, and Pydantic V2. Master microservices, WebSockets, an...); `python-pro` (Master Python 3.12+ with modern features, async programming, performance optimization, and production-ready practices...)
- Commands and workflow shape: `python-scaffold` (Python Project Scaffolding: You are a Python project architecture expert specializing in scaffolding production-ready...)
- Skills and activation patterns: `SKILL` (Master Python asyncio, concurrent programming, and async/await patterns for high-performance applications. Use when b...); `SKILL` (Use this skill when reviewing Python code for common anti-patterns to avoid. Use as a checklist when reviewing code, ...); `SKILL` (Python background job patterns including task queues, workers, and event-driven architecture. Use when implementing a...); `SKILL` (Python code style, linting, formatting, naming conventions, and documentation standards. Use when writing new code, r...); `SKILL` (Python configuration management via environment variables and typed settings. Use when externalizing config, setting ...); `SKILL` (Python design patterns including KISS, Separation of Concerns, Single Responsibility, and composition over inheritanc...); `SKILL` (Python error handling patterns including input validation, exception hierarchies, and partial failure handling. Use w...); `SKILL` (Python observability patterns including structured logging, metrics, and distributed tracing. Use when adding logging...); +8 more
- High-priority distillation:
  - Adopt bounded roles, explicit ownership, progressive references, and review/checklist shapes.
  - Do not adopt Claude-only slash command syntax, marketplace install flow, tmux teammate assumptions, or hidden authority gates.
  - Codex mapping: capability pack plus optional custom agents, prompt recipes, and skills selected by the PM.
- Files: 25 total; complete paths are in the JSON manifest.
- Reference/template examples: `plugins/python-development/skills/python-packaging/references/advanced-patterns.md`, `plugins/python-development/skills/python-performance-optimization/references/advanced-patterns.md`, `plugins/python-development/skills/python-testing-patterns/references/advanced-patterns.md`, `plugins/python-development/skills/uv-package-manager/references/advanced-patterns.md`

### `quantitative-trading`

- Purpose: Quantitative analysis, algorithmic trading strategies, financial modeling, portfolio risk management, and backtesting
- File count: 5
- Component counts: agents 2; commands 0; skills 2; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `quant-analyst` (Build financial models, backtest trading strategies, and analyze market data. Implements risk metrics, portfolio opti...); `risk-manager` (Monitor portfolio risk, R-multiples, and position limits. Creates hedging strategies, calculates expectancy, and impl...)
- Commands and workflow shape: none found
- Skills and activation patterns: `SKILL` (Build robust backtesting systems for trading strategies with proper handling of look-ahead bias, survivorship bias, a...); `SKILL` (Calculate portfolio risk metrics including VaR, CVaR, Sharpe, Sortino, and drawdown analysis. Use when measuring port...)
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/quantitative-trading/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/quantitative-trading/agents/quant-analyst.md` [agent definition, read]
  - `plugins/quantitative-trading/agents/risk-manager.md` [agent definition, read]
  - `plugins/quantitative-trading/skills/backtesting-frameworks/SKILL.md` [skill instruction, read]
  - `plugins/quantitative-trading/skills/risk-metrics-calculation/SKILL.md` [skill instruction, read]

### `reverse-engineering`

- Purpose: Binary reverse engineering, malware analysis, firmware security, and software protection research for authorized security research, CTF competitions, and defensive security
- File count: 9
- Component counts: agents 3; commands 0; skills 4; references 1; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `firmware-analyst` (Expert firmware analyst specializing in embedded systems, IoT security, and hardware reverse engineering. Masters fir...); `malware-analyst` (Expert malware analyst specializing in defensive malware research, threat intelligence, and incident response. Master...); `reverse-engineer` (Expert reverse engineer specializing in binary analysis, disassembly, decompilation, and software analysis. Masters I...)
- Commands and workflow shape: none found
- Skills and activation patterns: `SKILL` (Understand anti-reversing, obfuscation, and protection techniques encountered during software analysis. Use this skil...); `SKILL` (Master binary analysis patterns including disassembly, decompilation, control flow analysis, and code pattern recogni...); `SKILL` (Master memory forensics techniques including memory acquisition, process analysis, and artifact extraction using Vola...); `SKILL` (Master network protocol reverse engineering including packet analysis, protocol dissection, and custom protocol docum...)
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/reverse-engineering/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/reverse-engineering/agents/firmware-analyst.md` [agent definition, read]
  - `plugins/reverse-engineering/agents/malware-analyst.md` [agent definition, read]
  - `plugins/reverse-engineering/agents/reverse-engineer.md` [agent definition, read]
  - `plugins/reverse-engineering/skills/anti-reversing-techniques/SKILL.md` [skill instruction, read]
  - `plugins/reverse-engineering/skills/anti-reversing-techniques/references/advanced-techniques.md` [skill reference, read]
  - `plugins/reverse-engineering/skills/binary-analysis-patterns/SKILL.md` [skill instruction, read]
  - `plugins/reverse-engineering/skills/memory-forensics/SKILL.md` [skill instruction, read]
  - `plugins/reverse-engineering/skills/protocol-reverse-engineering/SKILL.md` [skill instruction, read]

### `review-agent-governance`

- Purpose: Require a human approval signal before an AI agent can post PR reviews, comments, merges, or writes to CI config. Cedar-gated, receipt-signed, designed for the Hermes-style failure mode where a review bot posts without oversight.
- File count: 8
- Component counts: agents 1; commands 2; skills 1; references 0; manifests 1; templates 0; source code 1; tests 0; other 2
- Useful for PM-main workflow: high priority
- Too domain-specific or heavy: review before adoption; distill only patterns
- Agents and roles: `review-policy-author` (Cedar policy author specialized in gating AI agent review actions (PR comments, reviews, merges, CI edits) behind hum...)
- Commands and workflow shape: `approve-review` (Open a review-action approval window by creating the ./.review-approved flag file. Takes an optional reason string th...); `list-pending` (List recent denied review actions from the receipt chain. Shows what the agent tried to do that was blocked by the re...)
- Skills and activation patterns: `SKILL` (Configure human-in-the-loop gating for AI agent review actions in Claude Code. Use when setting up a project where an...)
- High-priority distillation:
  - Adopt bounded roles, explicit ownership, progressive references, and review/checklist shapes.
  - Do not adopt Claude-only slash command syntax, marketplace install flow, tmux teammate assumptions, or hidden authority gates.
  - Codex mapping: capability pack plus optional custom agents, prompt recipes, and skills selected by the PM.
- Files:
  - `plugins/review-agent-governance/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/review-agent-governance/README.md` [documentation, read]
  - `plugins/review-agent-governance/agents/review-policy-author.md` [agent definition, read]
  - `plugins/review-agent-governance/commands/approve-review.md` [command workflow, read]
  - `plugins/review-agent-governance/commands/list-pending.md` [command workflow, read]
  - `plugins/review-agent-governance/hooks/hooks.json` [documentation, read]
  - `plugins/review-agent-governance/policies/review-agent-governance.cedar` [source code, read]
  - `plugins/review-agent-governance/skills/review-agent-setup/SKILL.md` [skill instruction, read]

### `security-compliance`

- Purpose: SOC2, HIPAA, and GDPR compliance validation, secrets scanning, compliance checklists, and regulatory documentation
- File count: 3
- Component counts: agents 1; commands 1; skills 0; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: high priority
- Too domain-specific or heavy: review before adoption; distill only patterns
- Agents and roles: `security-auditor` (Expert security auditor specializing in DevSecOps, comprehensive cybersecurity, and compliance frameworks. Masters vu...)
- Commands and workflow shape: `compliance-check` (Regulatory Compliance Check: You are a compliance expert specializing in regulatory requirements for software systems...)
- Skills and activation patterns: none found
- High-priority distillation:
  - Adopt bounded roles, explicit ownership, progressive references, and review/checklist shapes.
  - Do not adopt Claude-only slash command syntax, marketplace install flow, tmux teammate assumptions, or hidden authority gates.
  - Codex mapping: capability pack plus optional custom agents, prompt recipes, and skills selected by the PM.
- Files:
  - `plugins/security-compliance/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/security-compliance/agents/security-auditor.md` [agent definition, read]
  - `plugins/security-compliance/commands/compliance-check.md` [command workflow, read]

### `security-scanning`

- Purpose: SAST analysis, dependency vulnerability scanning, OWASP Top 10 compliance, container security scanning, and automated security hardening
- File count: 11
- Component counts: agents 2; commands 3; skills 5; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: high priority
- Too domain-specific or heavy: review before adoption; distill only patterns
- Agents and roles: `security-auditor` (Expert security auditor specializing in DevSecOps, comprehensive cybersecurity, and compliance frameworks. Masters vu...); `threat-modeling-expert` (Expert in threat modeling methodologies, security architecture review, and risk assessment. Masters STRIDE, PASTA, at...)
- Commands and workflow shape: `security-dependencies` (Dependency Vulnerability Scanning: You are a security expert specializing in dependency vulnerability analysis, SBOM ...); `security-hardening` (Orchestrate comprehensive security hardening with defense-in-depth strategy across all application layers); `security-sast` (Static Application Security Testing (SAST) for code vulnerability analysis across multiple languages and frameworks)
- Skills and activation patterns: `SKILL` (Build comprehensive attack trees to visualize threat paths. Use when mapping attack scenarios, identifying defense ga...); `SKILL` (Configure Static Application Security Testing (SAST) tools for automated vulnerability detection in application code....); `SKILL` (Derive security requirements from threat models and business context. Use when translating threats into actionable re...); `SKILL` (Apply STRIDE methodology to systematically identify threats. Use when analyzing system security, conducting threat mo...); `SKILL` (Map identified threats to appropriate security controls and mitigations. Use when prioritizing security investments, ...)
- High-priority distillation:
  - Adopt bounded roles, explicit ownership, progressive references, and review/checklist shapes.
  - Do not adopt Claude-only slash command syntax, marketplace install flow, tmux teammate assumptions, or hidden authority gates.
  - Codex mapping: capability pack plus optional custom agents, prompt recipes, and skills selected by the PM.
- Files:
  - `plugins/security-scanning/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/security-scanning/agents/security-auditor.md` [agent definition, read]
  - `plugins/security-scanning/agents/threat-modeling-expert.md` [agent definition, read]
  - `plugins/security-scanning/commands/security-dependencies.md` [command workflow, read]
  - `plugins/security-scanning/commands/security-hardening.md` [command workflow, read]
  - `plugins/security-scanning/commands/security-sast.md` [command workflow, read]
  - `plugins/security-scanning/skills/attack-tree-construction/SKILL.md` [skill instruction, read]
  - `plugins/security-scanning/skills/sast-configuration/SKILL.md` [skill instruction, read]
  - `plugins/security-scanning/skills/security-requirement-extraction/SKILL.md` [skill instruction, read]
  - `plugins/security-scanning/skills/stride-analysis-patterns/SKILL.md` [skill instruction, read]
  - `plugins/security-scanning/skills/threat-mitigation-mapping/SKILL.md` [skill instruction, read]

### `seo-analysis-monitoring`

- Purpose: Content freshness analysis, cannibalization detection, and authority building for SEO
- File count: 4
- Component counts: agents 3; commands 0; skills 0; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `seo-authority-builder` (Analyzes content for E-E-A-T signals and suggests improvements to build authority and trust. Identifies missing credi...); `seo-cannibalization-detector` (Analyzes multiple provided pages to identify keyword overlap and potential cannibalization issues. Suggests different...); `seo-content-refresher` (Identifies outdated elements in provided content and suggests updates to maintain freshness. Finds statistics, dates,...)
- Commands and workflow shape: none found
- Skills and activation patterns: none found
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/seo-analysis-monitoring/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/seo-analysis-monitoring/agents/seo-authority-builder.md` [agent definition, read]
  - `plugins/seo-analysis-monitoring/agents/seo-cannibalization-detector.md` [agent definition, read]
  - `plugins/seo-analysis-monitoring/agents/seo-content-refresher.md` [agent definition, read]

### `seo-content-creation`

- Purpose: SEO content writing, planning, and quality auditing with E-E-A-T optimization
- File count: 4
- Component counts: agents 3; commands 0; skills 0; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `seo-content-auditor` (Analyzes provided content for quality, E-E-A-T signals, and SEO best practices. Scores content and provides improveme...); `seo-content-planner` (Creates comprehensive content outlines and topic clusters for SEO. Plans content calendars and identifies topic gaps....); `seo-content-writer` (Writes SEO-optimized content based on provided keywords and topic briefs. Creates engaging, comprehensive content fol...)
- Commands and workflow shape: none found
- Skills and activation patterns: none found
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/seo-content-creation/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/seo-content-creation/agents/seo-content-auditor.md` [agent definition, read]
  - `plugins/seo-content-creation/agents/seo-content-planner.md` [agent definition, read]
  - `plugins/seo-content-creation/agents/seo-content-writer.md` [agent definition, read]

### `seo-technical-optimization`

- Purpose: Technical SEO optimization including meta tags, keywords, structure, and featured snippets
- File count: 5
- Component counts: agents 4; commands 0; skills 0; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `seo-keyword-strategist` (Analyzes keyword usage in provided content, calculates density, suggests semantic variations and LSI keywords based o...); `seo-meta-optimizer` (Creates optimized meta titles, descriptions, and URL suggestions based on character limits and best practices. Genera...); `seo-snippet-hunter` (Formats content to be eligible for featured snippets and SERP features. Creates snippet-optimized content blocks base...); `seo-structure-architect` (Analyzes and optimizes content structure including header hierarchy, suggests schema markup, and internal linking opp...)
- Commands and workflow shape: none found
- Skills and activation patterns: none found
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/seo-technical-optimization/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/seo-technical-optimization/agents/seo-keyword-strategist.md` [agent definition, read]
  - `plugins/seo-technical-optimization/agents/seo-meta-optimizer.md` [agent definition, read]
  - `plugins/seo-technical-optimization/agents/seo-snippet-hunter.md` [agent definition, read]
  - `plugins/seo-technical-optimization/agents/seo-structure-architect.md` [agent definition, read]

### `shell-scripting`

- Purpose: Production-grade Bash scripting with defensive programming, POSIX compliance, and comprehensive testing
- File count: 6
- Component counts: agents 2; commands 0; skills 3; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `bash-pro` (Master of defensive Bash scripting for production automation, CI/CD pipelines, and system utilities. Expert in safe, ...); `posix-shell-pro` (Expert in strict POSIX sh scripting for maximum portability across Unix-like systems. Specializes in shell scripts th...)
- Commands and workflow shape: none found
- Skills and activation patterns: `SKILL` (Master defensive Bash programming techniques for production-grade scripts. Use when writing robust shell scripts, CI/...); `SKILL` (Master Bash Automated Testing System (Bats) for comprehensive shell script testing. Use when writing tests for shell ...); `SKILL` (Master ShellCheck static analysis configuration and usage for shell script quality. Use when setting up linting infra...)
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/shell-scripting/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/shell-scripting/agents/bash-pro.md` [agent definition, read]
  - `plugins/shell-scripting/agents/posix-shell-pro.md` [agent definition, read]
  - `plugins/shell-scripting/skills/bash-defensive-patterns/SKILL.md` [skill instruction, read]
  - `plugins/shell-scripting/skills/bats-testing-patterns/SKILL.md` [skill instruction, read]
  - `plugins/shell-scripting/skills/shellcheck-configuration/SKILL.md` [skill instruction, read]

### `signed-audit-trails`

- Purpose: Teaching skill: signed audit trails for Claude Code tool calls. Cookbook-style walkthrough of Cedar-gated tool calls with Ed25519 receipts, offline verification, and CI/CD integration. Pairs with the protect-mcp plugin.
- File count: 3
- Component counts: agents 0; commands 0; skills 1; references 0; manifests 1; templates 0; source code 0; tests 0; other 1
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: none found
- Commands and workflow shape: none found
- Skills and activation patterns: `SKILL` (Step-by-step cookbook for setting up cryptographically signed audit trails on Claude Code tool calls. Use when explai...)
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/signed-audit-trails/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/signed-audit-trails/README.md` [documentation, read]
  - `plugins/signed-audit-trails/skills/signed-audit-trails-recipe/SKILL.md` [skill instruction, read]

### `startup-business-analyst`

- Purpose: Comprehensive startup business analysis with market sizing (TAM/SAM/SOM), financial modeling, team planning, and strategic research
- File count: 13
- Component counts: agents 1; commands 3; skills 6; references 1; manifests 1; templates 0; source code 0; tests 0; other 1
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `startup-analyst` (Expert startup business analyst specializing in market sizing, financial modeling, competitive analysis, and strategi...)
- Commands and workflow shape: `business-case` (Generate comprehensive investor-ready business case document with market, solution, financials, and strategy); `financial-projections` (Create detailed 3-5 year financial model with revenue, costs, cash flow, and scenarios); `market-opportunity` (Generate comprehensive market opportunity analysis with TAM/SAM/SOM calculations)
- Skills and activation patterns: `SKILL` (Analyze competition, identify differentiation opportunities, and develop winning market positioning strategies using ...); `SKILL` (Calculate TAM/SAM/SOM for market opportunities using top-down, bottom-up, and value theory methodologies. Use this sk...); `saas-market-sizing` (SaaS Market Sizing Example: AI-Powered Email Marketing for E-Commerce: Complete TAM/SAM/SOM calculation for a B2B Saa...); `SKILL` (Build comprehensive 3-5 year financial models with revenue projections, cost structures, cash flow analysis, and scen...); `SKILL` (Track, calculate, and optimize key performance metrics for SaaS, marketplace, consumer, and B2B startups from seed th...); `SKILL` (Design optimal team structures, hiring plans, compensation strategies, and equity allocation for early-stage startups...)
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/startup-business-analyst/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/startup-business-analyst/README.md` [documentation, read]
  - `plugins/startup-business-analyst/agents/startup-analyst.md` [agent definition, read]
  - `plugins/startup-business-analyst/commands/business-case.md` [command workflow, read]
  - `plugins/startup-business-analyst/commands/financial-projections.md` [command workflow, read]
  - `plugins/startup-business-analyst/commands/market-opportunity.md` [command workflow, read]
  - `plugins/startup-business-analyst/skills/competitive-landscape/SKILL.md` [skill instruction, read]
  - `plugins/startup-business-analyst/skills/market-sizing-analysis/SKILL.md` [skill instruction, read]
  - `plugins/startup-business-analyst/skills/market-sizing-analysis/examples/saas-market-sizing.md` [documentation, read]
  - `plugins/startup-business-analyst/skills/market-sizing-analysis/references/data-sources.md` [skill reference, read]
  - `plugins/startup-business-analyst/skills/startup-financial-modeling/SKILL.md` [skill instruction, read]
  - `plugins/startup-business-analyst/skills/startup-metrics-framework/SKILL.md` [skill instruction, read]
  - `plugins/startup-business-analyst/skills/team-composition-analysis/SKILL.md` [skill instruction, read]

### `systems-programming`

- Purpose: Systems programming with Rust, Go, C, and C++ for performance-critical and low-level development
- File count: 9
- Component counts: agents 4; commands 1; skills 3; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: high priority
- Too domain-specific or heavy: review before adoption; distill only patterns
- Agents and roles: `c-pro` (Write efficient C code with proper memory management, pointer arithmetic, and system calls. Handles embedded systems,...); `cpp-pro` (Write idiomatic C++ code with modern features, RAII, smart pointers, and STL algorithms. Handles templates, move sema...); `golang-pro` (Master Go 1.21+ with modern patterns, advanced concurrency, performance optimization, and production-ready microservi...); `rust-pro` (Master Rust 1.75+ with modern async patterns, advanced type system features, and production-ready systems programming...)
- Commands and workflow shape: `rust-project` (Rust Project Scaffolding: You are a Rust project architecture expert specializing in scaffolding production-ready Rus...)
- Skills and activation patterns: `SKILL` (Master Go concurrency with goroutines, channels, sync primitives, and context. Use when building concurrent Go applic...); `SKILL` (Implement memory-safe programming with RAII, ownership, smart pointers, and resource management across Rust, C++, and...); `SKILL` (Master Rust async programming with Tokio, async traits, error handling, and concurrent patterns. Use when building as...)
- High-priority distillation:
  - Adopt bounded roles, explicit ownership, progressive references, and review/checklist shapes.
  - Do not adopt Claude-only slash command syntax, marketplace install flow, tmux teammate assumptions, or hidden authority gates.
  - Codex mapping: capability pack plus optional custom agents, prompt recipes, and skills selected by the PM.
- Files:
  - `plugins/systems-programming/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/systems-programming/agents/c-pro.md` [agent definition, read]
  - `plugins/systems-programming/agents/cpp-pro.md` [agent definition, read]
  - `plugins/systems-programming/agents/golang-pro.md` [agent definition, read]
  - `plugins/systems-programming/agents/rust-pro.md` [agent definition, read]
  - `plugins/systems-programming/commands/rust-project.md` [command workflow, read]
  - `plugins/systems-programming/skills/go-concurrency-patterns/SKILL.md` [skill instruction, read]
  - `plugins/systems-programming/skills/memory-safety-patterns/SKILL.md` [skill instruction, read]
  - `plugins/systems-programming/skills/rust-async-patterns/SKILL.md` [skill instruction, read]

### `tdd-workflows`

- Purpose: Test-driven development methodology with red-green-refactor cycles and code review
- File count: 7
- Component counts: agents 2; commands 4; skills 0; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: high priority
- Too domain-specific or heavy: review before adoption; distill only patterns
- Agents and roles: `code-reviewer` (Elite code review expert specializing in modern AI-powered code analysis, security vulnerabilities, performance optim...); `tdd-orchestrator` (Master TDD orchestrator specializing in red-green-refactor discipline, multi-agent workflow coordination, and compreh...)
- Commands and workflow shape: `tdd-cycle` (Execute a comprehensive TDD workflow with strict red-green-refactor discipline); `tdd-green` (Implement minimal code to make failing tests pass in TDD green phase); `tdd-red` (Write comprehensive failing tests following TDD red phase principles); `tdd-refactor` (Usage: Refactor code with confidence using comprehensive test safety net: [Extended thinking: This tool uses the tdd-...)
- Skills and activation patterns: none found
- High-priority distillation:
  - Adopt bounded roles, explicit ownership, progressive references, and review/checklist shapes.
  - Do not adopt Claude-only slash command syntax, marketplace install flow, tmux teammate assumptions, or hidden authority gates.
  - Codex mapping: capability pack plus optional custom agents, prompt recipes, and skills selected by the PM.
- Files:
  - `plugins/tdd-workflows/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/tdd-workflows/agents/code-reviewer.md` [agent definition, read]
  - `plugins/tdd-workflows/agents/tdd-orchestrator.md` [agent definition, read]
  - `plugins/tdd-workflows/commands/tdd-cycle.md` [command workflow, read]
  - `plugins/tdd-workflows/commands/tdd-green.md` [command workflow, read]
  - `plugins/tdd-workflows/commands/tdd-red.md` [command workflow, read]
  - `plugins/tdd-workflows/commands/tdd-refactor.md` [command workflow, read]

### `team-collaboration`

- Purpose: Team workflows, issue management, standup automation, and developer experience optimization
- File count: 4
- Component counts: agents 1; commands 2; skills 0; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `dx-optimizer` (Developer Experience specialist. Improves tooling, setup, and workflows. Use PROACTIVELY when setting up new projects...)
- Commands and workflow shape: `issue` (GitHub Issue Resolution Expert: You are a GitHub issue resolution expert specializing in systematic bug investigation...); `standup-notes` (Standup Notes Generator: You are an expert team communication specialist focused on async-first standup practices, AI...)
- Skills and activation patterns: none found
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/team-collaboration/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/team-collaboration/agents/dx-optimizer.md` [agent definition, read]
  - `plugins/team-collaboration/commands/issue.md` [command workflow, read]
  - `plugins/team-collaboration/commands/standup-notes.md` [command workflow, read]

### `ui-design`

- Purpose: Comprehensive UI/UX design plugin for mobile (iOS, Android, React Native) and web applications with design systems, accessibility, and modern patterns
- File count: 45
- Component counts: agents 3; commands 4; skills 9; references 27; manifests 1; templates 0; source code 0; tests 0; other 1
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `accessibility-expert` (Expert accessibility specialist ensuring WCAG compliance, inclusive design, and assistive technology compatibility. M...); `design-system-architect` (Expert design system architect specializing in design tokens, component libraries, theming infrastructure, and scalab...); `ui-designer` (Expert UI designer specializing in component creation, layout systems, and visual design implementation. Masters mode...)
- Commands and workflow shape: `accessibility-audit` (Audit UI code for WCAG compliance); `create-component` (Guided component creation with proper patterns); `design-review` (Review existing UI for issues and improvements); `design-system-setup` (Initialize a design system with tokens)
- Skills and activation patterns: `SKILL` (Implement WCAG 2.2 compliant interfaces with mobile accessibility, inclusive design patterns, and assistive technolog...); `SKILL` (Build scalable design systems with design tokens, theming infrastructure, and component architecture patterns. Use wh...); `SKILL` (Design and implement microinteractions, motion design, transitions, and user feedback patterns. Use when adding polis...); `SKILL` (Master Material Design 3 and Jetpack Compose patterns for building native Android apps. Use when designing Android in...); `SKILL` (Master iOS Human Interface Guidelines and SwiftUI patterns for building native iOS apps. Use when designing iOS inter...); `SKILL` (Master React Native styling, navigation, and Reanimated animations for cross-platform mobile development. Use when bu...); `SKILL` (Implement modern responsive layouts using container queries, fluid typography, CSS Grid, and mobile-first breakpoint ...); `SKILL` (Apply typography, color theory, spacing systems, and iconography principles to create cohesive visual designs. Use wh...); +1 more
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files: 45 total; complete paths are in the JSON manifest.
- Reference/template examples: `plugins/ui-design/skills/accessibility-compliance/references/aria-patterns.md`, `plugins/ui-design/skills/accessibility-compliance/references/mobile-accessibility.md`, `plugins/ui-design/skills/accessibility-compliance/references/wcag-guidelines.md`, `plugins/ui-design/skills/design-system-patterns/references/component-architecture.md`, `plugins/ui-design/skills/design-system-patterns/references/design-tokens.md`, `plugins/ui-design/skills/design-system-patterns/references/theming-architecture.md`

### `unit-testing`

- Purpose: Unit and integration test automation for Python and JavaScript with debugging support
- File count: 4
- Component counts: agents 2; commands 1; skills 0; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `debugger` (Debugging specialist for errors, test failures, and unexpected behavior. Use proactively when encountering any issues.); `test-automator` (Master AI-powered test automation with modern frameworks, self-healing tests, and comprehensive quality engineering. ...)
- Commands and workflow shape: `test-generate` (Automated Unit Test Generation: You are a test automation expert specializing in generating comprehensive, maintainab...)
- Skills and activation patterns: none found
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/unit-testing/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/unit-testing/agents/debugger.md` [agent definition, read]
  - `plugins/unit-testing/agents/test-automator.md` [agent definition, read]
  - `plugins/unit-testing/commands/test-generate.md` [command workflow, read]

### `web-scripting`

- Purpose: Web scripting with PHP and Ruby for web applications, CMS development, and backend services
- File count: 3
- Component counts: agents 2; commands 0; skills 0; references 0; manifests 1; templates 0; source code 0; tests 0; other 0
- Useful for PM-main workflow: situational
- Too domain-specific or heavy: likely reference-only unless the domain is active
- Agents and roles: `php-pro` (Write idiomatic PHP code with generators, iterators, SPL data structures, and modern OOP features. Use PROACTIVELY fo...); `ruby-pro` (Write idiomatic Ruby code with metaprogramming, Rails patterns, and performance optimization. Specializes in Ruby on ...)
- Commands and workflow shape: none found
- Skills and activation patterns: none found
- Representative distillation: keep as reference for domain-specific capability-pack design; avoid global installation.
- Files:
  - `plugins/web-scripting/.claude-plugin/plugin.json` [plugin manifest, read]
  - `plugins/web-scripting/agents/php-pro.md` [agent definition, read]
  - `plugins/web-scripting/agents/ruby-pro.md` [agent definition, read]

## Minimal Codex Role/Team/Workflow Distillation

- Use PM-selected team presets rather than always-on teams.
- Spawn or reuse subagents only for bounded, non-overlapping work.
- Treat workers as artifact producers and reviewers as evidence producers.
- Preserve file ownership, dependency ordering, and graceful shutdown patterns.
- Keep plugin-eval style checks as quality review, not hard completion gates.

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
