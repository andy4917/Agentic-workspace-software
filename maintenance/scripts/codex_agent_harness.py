#!/usr/bin/env python3
"""Small deterministic Codex harness for the local CODEX_HOME root.

This intentionally does not clone external harnesses. It distills the local
operating rules into reversible, state-tracked commands.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import textwrap
import tomllib
from pathlib import Path
from typing import Any


SCHEMA_VERSION = "1"
RUBRIC_VERSION = "codex-harness-audit-v1"
OWNER = "codex-agent-harness"
DEFAULT_PROFILE = "developer"
SOURCE_PLAN = Path("C:/Users/anise/Downloads/codex-agent-harness-distillation-plan.md")

MODULES: dict[str, dict[str, str]] = {
    "codex-baseline": {"purpose": "Codex baseline config, global instructions, and role agents"},
    "rules-core": {"purpose": "Durable instruction and context-loading rules"},
    "skills-core": {"purpose": "Compact repo-local skill index and draft isolation"},
    "workflow-quality": {"purpose": "Verification, compaction, learning, and report workflows"},
    "security": {"purpose": "Secret hygiene and external action boundaries"},
    "orchestration": {"purpose": "Multi-agent role routing and iterative retrieval guidance"},
    "mcp-baseline": {"purpose": "Safe MCP recommendations and loading diagnostics"},
    "benchmarking": {"purpose": "Small deterministic eval and benchmark harness"},
}

PROFILES: dict[str, list[str]] = {
    "minimal": ["codex-baseline", "rules-core"],
    "core": ["codex-baseline", "rules-core", "skills-core", "workflow-quality", "mcp-baseline"],
    "developer": [
        "codex-baseline",
        "rules-core",
        "skills-core",
        "workflow-quality",
        "mcp-baseline",
        "benchmarking",
        "orchestration",
    ],
    "security": ["codex-baseline", "rules-core", "skills-core", "workflow-quality", "security"],
    "full": list(MODULES),
}

ROLE_CONFIGS = {
    "agents/explorer.toml": """# Managed by codex-agent-harness.
name = "explorer"
mode = "read-only"
purpose = "Gather focused evidence before implementation."
allowed_work = ["file_search", "file_read", "structure_summary", "evidence_report"]
disallowed_work = ["file_write", "external_mutation", "secret_content_read"]
sandbox = "read-only"
""",
    "agents/reviewer.toml": """# Managed by codex-agent-harness.
name = "reviewer"
mode = "read-only"
purpose = "Review correctness, security, behavior, missing tests, and maintainability."
allowed_work = ["diff_review", "risk_report", "test_gap_report", "security_review"]
disallowed_work = ["file_write", "external_mutation", "secret_content_read"]
sandbox = "read-only"
""",
    "agents/docs-researcher.toml": """# Managed by codex-agent-harness.
name = "docs-researcher"
mode = "read-only"
purpose = "Verify version-sensitive claims against primary documentation."
allowed_work = ["official_docs_lookup", "citation_summary", "version_policy_report"]
disallowed_work = ["file_write", "external_mutation", "secret_content_read"]
sandbox = "read-only"
""",
}

SKILL_TEMPLATES = {
    "skills/_drafts/README.md": """# Draft Skills

Draft skills live here until explicitly approved. Do not auto-install or load
draft skills as active instructions.
""",
    "skills/agent-harness-construction/SKILL.md": """---
name: agent-harness-construction
description: Build or repair the local Codex harness with reversible, deterministic changes.
version: 0.1.0
tags: [codex, harness, verification, maintenance]
required_tools: [python, powershell]
---

# Agent Harness Construction

Use this when changing the local Codex harness. Work in small phases:
discover, plan, apply, doctor, verify, audit, then report evidence and risks.
Do not clone external harnesses, store secrets, or mutate external services.
""",
    "skills/verification-loop/SKILL.md": """---
name: verification-loop
description: Repeat deterministic checks until the local harness has no known failing checks.
version: 0.1.0
tags: [verification, audit, repair]
required_tools: [python]
---

# Verification Loop

Run doctor, verify, eval, and audit. Fix confirmed failures only, then rerun
the same checks. Record checks not run with reasons.
""",
    "skills/iterative-retrieval/SKILL.md": """---
name: iterative-retrieval
description: Retrieve focused context for subagents without dumping the whole tree.
version: 0.1.0
tags: [subagents, retrieval, context]
required_tools: [rg]
---

# Iterative Retrieval

Use up to three cycles: broad search, score files, refine query, select context,
and record the stop reason.
""",
}

EVAL_TEMPLATES = {
    "evals/config-parse.json": {
        "eval_id": "config-parse",
        "task": "Parse root config.toml with Python tomllib.",
        "setup": "Run from CODEX_HOME.",
        "success_criteria": ["config.toml parses", "stable workflow feature keys are present"],
        "grader": "python maintenance/scripts/codex_agent_harness.py doctor --json",
        "timeout_seconds": 30,
        "risk_notes": "Does not prove app runtime reloaded the config.",
    },
    "evals/managed-files.json": {
        "eval_id": "managed-files",
        "task": "Verify harness-managed files are present and match install-state digests.",
        "setup": "Run after harness apply.",
        "success_criteria": ["install-state exists", "managed files exist", "digests match"],
        "grader": "python maintenance/scripts/codex_agent_harness.py doctor --json",
        "timeout_seconds": 30,
        "risk_notes": "Only checks files owned by this harness.",
    },
    "evals/audit-threshold.json": {
        "eval_id": "audit-threshold",
        "task": "Run deterministic harness audit and require no critical failures.",
        "setup": "Run after harness apply.",
        "success_criteria": ["audit JSON exists", "overall score is at least 80"],
        "grader": "python maintenance/scripts/codex_agent_harness.py audit --json",
        "timeout_seconds": 30,
        "risk_notes": "Score is deterministic but intentionally conservative.",
    },
}


def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()


def local_stamp() -> str:
    return dt.datetime.now().strftime("%Y%m%d-%H%M%S")


def root_path(args: argparse.Namespace) -> Path:
    return Path(args.root).expanduser().resolve()


def rel(path: Path, root: Path) -> str:
    return path.resolve().relative_to(root.resolve()).as_posix()


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def write_text(path: Path, content: str) -> None:
    ensure_dir(path.parent)
    path.write_text(content, encoding="utf-8", errors="replace", newline="\n")


def write_json(path: Path, data: Any) -> None:
    write_text(path, json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n")


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def backup_file(path: Path, root: Path) -> Path:
    backup_root = root / "maintenance" / "backups" / f"codex-harness-{local_stamp()}"
    ensure_dir(backup_root)
    destination = backup_root / rel(path, root)
    ensure_dir(destination.parent)
    shutil.copy2(path, destination)
    return destination


def load_json(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    return json.loads(read_text(path))


def install_state_path(root: Path) -> Path:
    return root / ".codex-harness" / "install-state.json"


def selected_modules(profile: str, modules: list[str] | None = None) -> list[str]:
    if modules:
        unknown = [m for m in modules if m not in MODULES]
        if unknown:
            raise SystemExit(f"Unknown modules: {', '.join(unknown)}")
        return modules
    if profile not in PROFILES:
        raise SystemExit(f"Unknown profile: {profile}")
    return PROFILES[profile]


def wrapper_script(command: str) -> str:
    return f"""param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Args)
$ErrorActionPreference = 'Stop'
$Script = Join-Path $PSScriptRoot 'codex_agent_harness.py'
python $Script {command} @Args
"""


def managed_templates(root: Path, modules: list[str]) -> dict[str, str]:
    templates: dict[str, str] = {}

    templates[".codex-harness/manifests/modules.json"] = json.dumps(MODULES, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    templates[".codex-harness/manifests/profiles.json"] = json.dumps(PROFILES, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    templates[".codex-harness/schemas/install-state.schema.json"] = json.dumps(
        {
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "title": "Codex Harness Install State",
            "type": "object",
            "required": ["schema_version", "installed_at", "target", "requested_profile", "selected_modules", "applied_operations"],
            "properties": {
                "schema_version": {"type": "string"},
                "installed_at": {"type": "string"},
                "target": {"type": "object"},
                "requested_profile": {"type": "string"},
                "requested_modules": {"type": "array"},
                "selected_modules": {"type": "array"},
                "skipped_modules": {"type": "array"},
                "source": {"type": "object"},
                "applied_operations": {"type": "array"},
            },
        },
        ensure_ascii=False,
        indent=2,
        sort_keys=True,
    ) + "\n"

    if "codex-baseline" in modules or "orchestration" in modules:
        templates.update(ROLE_CONFIGS)

    if "skills-core" in modules:
        templates.update(SKILL_TEMPLATES)
        templates["skills/SKILL_INDEX.md"] = skill_index_content(SKILL_TEMPLATES)

    if "workflow-quality" in modules:
        templates["reports/README.md"] = "# Codex Harness Reports\n\nGenerated discovery, context, verification, eval, benchmark, and audit reports live here.\n"
        templates["artifacts/tool-results/README.md"] = "# Tool Result Artifacts\n\nLarge command outputs can be stored here with metadata references from trajectories.\n"
        templates["artifacts/compact-summaries/README.md"] = "# Compact Summaries\n\nStructured phase-boundary summaries live here.\n"
        templates["trajectories/README.md"] = "# Trajectories\n\nJSONL run records for successes and failures live here.\n"
        templates["learning/README.md"] = "# Learning Drafts\n\nOnly unapproved, project-scoped instincts and skill candidates live here. Do not store raw private conversations or secrets.\n"
        templates["reports/context-inspection.template.md"] = context_template()
        templates["reports/retrieval-report.template.md"] = retrieval_template()

    if "benchmarking" in modules:
        for path, content in EVAL_TEMPLATES.items():
            templates[path] = json.dumps(content, ensure_ascii=False, indent=2, sort_keys=True) + "\n"

    wrappers = {
        "codex-harness-plan.ps1": "plan",
        "codex-harness-apply.ps1": "apply",
        "codex-harness-doctor.ps1": "doctor",
        "codex-harness-repair.ps1": "repair",
        "codex-harness-uninstall.ps1": "uninstall",
        "codex-harness-audit.ps1": "audit",
        "codex-verify.ps1": "verify",
        "codex-eval.ps1": "eval",
        "codex-merge-config.ps1": "merge-config",
        "codex-global-scan.ps1": "global-scan",
    }
    for name, command in wrappers.items():
        templates[f"maintenance/scripts/{name}"] = wrapper_script(command)

    return templates


def skill_index_content(skill_templates: dict[str, str]) -> str:
    entries = []
    for path, content in sorted(skill_templates.items()):
        if not path.endswith("/SKILL.md"):
            continue
        frontmatter = parse_frontmatter(content)
        entries.append(
            f"| {frontmatter.get('name', Path(path).parent.name)} | {frontmatter.get('description', '')} | {', '.join(frontmatter.get('tags', []))} |"
        )
    return "# Skill Index\n\nFull skill bodies are loaded only when their trigger matches.\n\n| Name | Description | Tags |\n|---|---|---|\n" + "\n".join(entries) + "\n"


def parse_frontmatter(content: str) -> dict[str, Any]:
    if not content.startswith("---\n"):
        return {}
    end = content.find("\n---", 4)
    if end == -1:
        return {}
    data: dict[str, Any] = {}
    for raw in content[4:end].splitlines():
        if ":" not in raw:
            continue
        key, value = raw.split(":", 1)
        value = value.strip()
        if value.startswith("[") and value.endswith("]"):
            data[key.strip()] = [v.strip() for v in value[1:-1].split(",") if v.strip()]
        else:
            data[key.strip()] = value.strip('"')
    return data


def context_template() -> str:
    return """# Context Inspection

- discovered instruction files:
- selected primary instruction source:
- skipped instruction sources:
- truncation decisions:
- warnings:
- estimated context size:
"""


def retrieval_template() -> str:
    return """# Iterative Retrieval Report

- cycles:
- query per cycle:
- candidate files:
- relevance scores:
- relevance reasons:
- missing context:
- refined query:
- selected context:
- stop reason:
"""


def command_exists(command: str) -> bool:
    return shutil.which(command) is not None


def run_command(command: list[str], cwd: Path, timeout: int = 60) -> dict[str, Any]:
    started = dt.datetime.now()
    try:
        completed = subprocess.run(
            command,
            cwd=str(cwd),
            text=True,
            encoding="utf-8",
            errors="replace",
            capture_output=True,
            timeout=timeout,
        )
        status = "pass" if completed.returncode == 0 else "fail"
        return {
            "command": command,
            "status": status,
            "exit_code": completed.returncode,
            "stdout_preview": completed.stdout[-4000:],
            "stderr_preview": completed.stderr[-4000:],
            "duration_seconds": (dt.datetime.now() - started).total_seconds(),
        }
    except Exception as exc:  # noqa: BLE001 - diagnostics command wrapper
        return {
            "command": command,
            "status": "error",
            "exit_code": None,
            "stdout_preview": "",
            "stderr_preview": str(exc),
            "duration_seconds": (dt.datetime.now() - started).total_seconds(),
        }


def discover_instruction_files(root: Path) -> list[dict[str, Any]]:
    candidates = [
        root / "instructions.md",
        root / "AGENTS.md",
        root / "agent.md",
        root / "CLAUDE.md",
        root / ".cursorrules",
    ]
    cursor_rules = root / ".cursor" / "rules"
    if cursor_rules.exists():
        candidates.extend(sorted(cursor_rules.glob("*.mdc")))
    result = []
    for path in candidates:
        if path.exists():
            result.append({"path": rel(path, root), "bytes": path.stat().st_size})
    return result


def discovery_data(root: Path) -> dict[str, Any]:
    files = set(p.as_posix() for p in iter_files(root, max_files=20000))
    commands = {
        "test": ["python maintenance/scripts/codex_agent_harness.py verify"],
        "lint": [],
        "typecheck": [],
        "build": [],
        "security": ["python maintenance/scripts/codex_agent_harness.py audit --json"],
    }
    if "package.json" in files:
        commands["test"].append("npm test")
    if "pyproject.toml" in files:
        commands["test"].append("pytest")
    return {
        "generated_at": utc_now(),
        "project_type": "Codex global state and local development-environment harness",
        "language_runtime": ["PowerShell", "Python", "TOML", "JSON"],
        "package_manager": "toolchain shims under toolchains/shims; no repo package manager required",
        "detected_commands": commands,
        "existing_harness_instruction_files": discover_instruction_files(root),
        "proposed_harness_script_language": "Python engine with PowerShell wrappers",
        "implementation_assumptions": [
            "C:/Users/anise/.codex is CODEX_HOME and GlobalSSOT root.",
            "Desktop is user-facing and must not be mutated by harness commands.",
            "Global config mutation requires backup and explicit apply path.",
            "Secrets and credential contents are not read.",
        ],
        "risks": [
            "Already-running Codex sessions may not reload newly enabled MCP tools until restart.",
            "Sentinel blocker files intentionally cause PATH/temp creation warnings for commands that try to create blocked roots.",
            "SQLite runtime DB files are live and are audited metadata-only.",
        ],
    }


def iter_files(root: Path, max_files: int = 100000) -> list[Path]:
    ignored = {
        ".git",
        "archived_sessions",
        "generated_images",
        "node_modules",
        ".sandbox",
        ".sandbox-bin",
        ".sandbox-secrets",
        "browser",
        "log",
        "sessions",
        "sqlite",
    }
    result: list[Path] = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in ignored]
        current = Path(dirpath)
        for filename in filenames:
            result.append((current / filename).relative_to(root))
            if len(result) >= max_files:
                return result
    return result


def cmd_discovery(args: argparse.Namespace) -> int:
    root = root_path(args)
    data = discovery_data(root)
    ensure_dir(root / "reports")
    write_json(root / "reports" / "discovery.json", data)
    lines = [
        "# Discovery",
        "",
        f"- generated_at: {data['generated_at']}",
        f"- project_type: {data['project_type']}",
        f"- language_runtime: {', '.join(data['language_runtime'])}",
        f"- package_manager: {data['package_manager']}",
        f"- proposed_harness_script_language: {data['proposed_harness_script_language']}",
        "",
        "## Existing Instruction Files",
    ]
    for item in data["existing_harness_instruction_files"]:
        lines.append(f"- {item['path']} ({item['bytes']} bytes)")
    lines.extend(["", "## Risks"])
    lines.extend(f"- {risk}" for risk in data["risks"])
    write_text(root / "reports" / "discovery.md", "\n".join(lines) + "\n")
    print(root / "reports" / "discovery.md")
    return 0


def cmd_plan(args: argparse.Namespace) -> int:
    root = root_path(args)
    modules = selected_modules(args.profile, args.module)
    templates = managed_templates(root, modules)
    existing = []
    missing = []
    for path in sorted(templates):
        full = root / path
        (existing if full.exists() else missing).append(path)
    plan = {
        "generated_at": utc_now(),
        "root": str(root),
        "profile": args.profile,
        "selected_modules": modules,
        "will_create": missing,
        "already_exists": existing,
        "mutation_required": bool(missing),
        "apply_command": "python maintenance/scripts/codex_agent_harness.py apply --profile " + args.profile,
    }
    ensure_dir(root / "reports")
    write_json(root / "reports" / "harness-plan.latest.json", plan)
    if args.json:
        print(json.dumps(plan, ensure_ascii=False, indent=2, sort_keys=True))
    else:
        print(f"Profile: {args.profile}")
        print(f"Modules: {', '.join(modules)}")
        print(f"Will create: {len(missing)}")
        for item in missing:
            print(f"  + {item}")
    return 0


def cmd_apply(args: argparse.Namespace) -> int:
    root = root_path(args)
    modules = selected_modules(args.profile, args.module)
    templates = managed_templates(root, modules)
    operations = []
    for path, content in sorted(templates.items()):
        full = root / path
        digest = sha256_text(content)
        if full.exists():
            current = sha256_file(full)
            action = "unchanged" if current == digest else "exists_unmanaged_preserved"
            operations.append({"path": path, "action": action, "digest": current, "owner": OWNER})
            continue
        write_text(full, content)
        operations.append({"path": path, "action": "created", "digest": digest, "owner": OWNER})
    state = {
        "schema_version": SCHEMA_VERSION,
        "installed_at": utc_now(),
        "target": {"id": "codex-home-global-ssot", "root": str(root)},
        "requested_profile": args.profile,
        "requested_modules": args.module or [],
        "selected_modules": modules,
        "skipped_modules": [],
        "source": source_plan_metadata(),
        "applied_operations": operations,
    }
    write_json(install_state_path(root), state)
    print(f"Applied harness state: {install_state_path(root)}")
    return 0


def source_plan_metadata() -> dict[str, Any]:
    if SOURCE_PLAN.exists():
        return {
            "plan": str(SOURCE_PLAN),
            "plan_sha256": sha256_file(SOURCE_PLAN),
            "implementation": "local-distillation",
        }
    return {
        "plan": str(SOURCE_PLAN),
        "plan_sha256": None,
        "implementation": "local-distillation",
        "warning": "source plan path was not present during apply",
    }


def clean_report_string(value: str, limit: int = 500) -> str:
    cleaned = "".join(ch if (ch == "\t" or ord(ch) >= 32) else "?" for ch in value)
    return cleaned[:limit]


def load_state(root: Path) -> dict[str, Any]:
    return load_json(install_state_path(root), {})


def stale_active_references(root: Path) -> list[dict[str, Any]]:
    active = [root / "config.toml", root / ".codex-global-state.json", root / "hooks.json", root / "AGENTS.md", root / "agent.md"]
    pattern = re.compile(r"(\\\.tmp\\|\\tmp\\|vendor_imports|bundled-marketplaces|plugins\\cache|plugins\\plugins)", re.I)
    matches = []
    for path in active:
        if not path.exists() or path.name in {"auth.json", ".credentials.json"}:
            continue
        try:
            for number, line in enumerate(read_text(path).splitlines(), 1):
                if pattern.search(line):
                    matches.append({"path": rel(path, root), "line": number, "text": line.strip()})
        except UnicodeDecodeError:
            continue
    return matches


def sentinel_checks(root: Path) -> list[dict[str, Any]]:
    targets = [
        ".tmp",
        "tmp",
        "vendor_imports",
        "plugins/cache",
        "plugins/plugins",
        "plugins/local-marketplaces/openai-bundled",
        "plugins/local-marketplaces/openai-primary-runtime",
    ]
    out = []
    for item in targets:
        path = root / item
        out.append(
            {
                "path": item,
                "exists": path.exists(),
                "is_file": path.is_file(),
                "readonly": bool(path.exists() and os.access(path, os.R_OK) and not os.access(path, os.W_OK)),
            }
        )
    return out


def check_config(root: Path) -> dict[str, Any]:
    path = root / "config.toml"
    if not path.exists():
        return {"status": "fail", "error": "config.toml missing"}
    try:
        data = tomllib.loads(read_text(path))
    except Exception as exc:  # noqa: BLE001
        return {"status": "fail", "error": str(exc)}
    features = data.get("features", {})
    expected_true = ["plugins", "codex_hooks", "multi_agent", "child_agents_md", "tool_search", "tool_suggest", "skill_mcp_dependency_install"]
    missing = [key for key in expected_true if features.get(key) is not True]
    unexpected = [key for key in ["enable_fanout", "multi_agent_v2"] if features.get(key) is True]
    return {"status": "pass" if not missing and not unexpected else "fail", "missing_true": missing, "unexpected_true": unexpected}


def check_managed_files(root: Path) -> dict[str, Any]:
    state = load_state(root)
    if not state:
        return {"status": "fail", "error": "install-state missing"}
    missing = []
    drifted = []
    for op in state.get("applied_operations", []):
        if op.get("action") not in {"created", "unchanged"}:
            continue
        path = root / op["path"]
        if not path.exists():
            missing.append(op["path"])
            continue
        digest = sha256_file(path)
        if digest != op.get("digest"):
            drifted.append(op["path"])
    return {"status": "pass" if not missing and not drifted else "fail", "missing": missing, "drifted": drifted}


def check_skill_frontmatter(root: Path) -> dict[str, Any]:
    state = load_state(root)
    managed = {
        op.get("path")
        for op in state.get("applied_operations", [])
        if isinstance(op, dict) and str(op.get("path", "")).startswith("skills/")
    }
    missing = []
    warnings = []
    for path in (root / "skills").glob("*/SKILL.md") if (root / "skills").exists() else []:
        data = parse_frontmatter(read_text(path))
        required = ["name", "description", "version", "tags"]
        absent = [key for key in required if key not in data]
        if absent:
            item = {"path": rel(path, root), "missing": absent}
            if rel(path, root) in managed:
                missing.append(item)
            else:
                warnings.append(item)
    return {"status": "pass" if not missing else "fail", "missing": missing, "warnings": warnings}


def doctor_data(root: Path) -> dict[str, Any]:
    checks = {
        "config": check_config(root),
        "managed_files": check_managed_files(root),
        "skill_frontmatter": check_skill_frontmatter(root),
        "stale_active_references": {"status": "pass", "matches": stale_active_references(root)},
        "sentinel_blockers": {"status": "pass", "items": sentinel_checks(root)},
    }
    if checks["stale_active_references"]["matches"]:
        checks["stale_active_references"]["status"] = "fail"
    failed = [name for name, result in checks.items() if result.get("status") != "pass"]
    return {"generated_at": utc_now(), "root": str(root), "status": "pass" if not failed else "fail", "failed": failed, "checks": checks}


def cmd_doctor(args: argparse.Namespace) -> int:
    root = root_path(args)
    data = doctor_data(root)
    ensure_dir(root / "reports")
    write_json(root / "reports" / "doctor.latest.json", data)
    if args.json:
        print(json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True))
    else:
        print(f"Doctor: {data['status']}")
        for name, result in data["checks"].items():
            print(f"- {name}: {result.get('status')}")
    return 0 if data["status"] == "pass" else 1


def cmd_repair(args: argparse.Namespace) -> int:
    root = root_path(args)
    state = load_state(root)
    if not state:
        print("install-state missing; run apply first", file=sys.stderr)
        return 1
    modules = state.get("selected_modules", PROFILES[DEFAULT_PROFILE])
    templates = managed_templates(root, modules)
    repaired = []
    for op in state.get("applied_operations", []):
        path = op.get("path")
        if path not in templates or op.get("action") not in {"created", "unchanged"}:
            continue
        full = root / path
        desired = templates[path]
        if full.exists() and sha256_file(full) == sha256_text(desired):
            continue
        if args.apply:
            if full.exists():
                backup_file(full, root)
            write_text(full, desired)
            repaired.append(path)
        else:
            repaired.append(path)
    print(json.dumps({"apply": args.apply, "repair_targets": repaired}, ensure_ascii=False, indent=2))
    return 0


def cmd_uninstall(args: argparse.Namespace) -> int:
    root = root_path(args)
    state = load_state(root)
    if not state:
        print("install-state missing; nothing to uninstall")
        return 0
    targets = []
    for op in state.get("applied_operations", []):
        if op.get("action") == "created":
            path = root / op["path"]
            if path.exists() and sha256_file(path) == op.get("digest"):
                targets.append(op["path"])
    if not args.apply:
        print(json.dumps({"dry_run": True, "would_remove": targets}, ensure_ascii=False, indent=2))
        return 0
    for item in sorted(targets, reverse=True):
        path = root / item
        backup_file(path, root)
        path.unlink()
    print(json.dumps({"dry_run": False, "removed": targets}, ensure_ascii=False, indent=2))
    return 0


def audit_data(root: Path) -> dict[str, Any]:
    doctor = doctor_data(root)
    global_scan = load_json(root / "reports" / "global-scan.latest.json", {})
    verification = load_json(root / "reports" / "verification.latest.json", {})
    verification_checks = {item.get("name"): item.get("status") for item in verification.get("checks", []) if isinstance(item, dict)}
    checks = {
        "Tool Coverage": [
            ("toolchain shims exist", (root / "toolchains" / "shims").exists()),
            ("codex verify command exists", (root / "maintenance" / "scripts" / "codex-verify.ps1").exists()),
            ("MCP status documented", (root / "maintenance" / "MCP_RUNTIME_STATUS.md").exists()),
            ("PowerShell wrappers installed", len(list((root / "maintenance" / "scripts").glob("codex-*.ps1"))) >= 3),
        ],
        "Context Efficiency": [
            ("AGENTS.md exists", (root / "AGENTS.md").exists()),
            ("context inspection template exists", (root / "reports" / "context-inspection.template.md").exists()),
            ("compact summaries directory exists", (root / "artifacts" / "compact-summaries").exists()),
            ("global scan redacts content", global_scan.get("content_redacted") is True),
        ],
        "Quality Gates": [
            ("doctor command exists", (root / "maintenance" / "scripts" / "codex-harness-doctor.ps1").exists()),
            ("verify command exists", (root / "maintenance" / "scripts" / "codex-verify.ps1").exists()),
            ("hook script parses by existence", (root / "hooks" / "lightweight-codex-hook.ps1").exists()),
            ("doctor currently passes", doctor.get("status") == "pass"),
            ("latest verification passes", verification.get("status") == "pass"),
            ("latest verification includes lifecycle dry-runs", all(verification_checks.get(name) == "pass" for name in ["self_test", "repair_dry_run", "uninstall_dry_run"])),
        ],
        "Memory Persistence": [
            ("trajectories directory exists", (root / "trajectories").exists()),
            ("learning drafts directory exists", (root / "learning").exists()),
            ("install-state exists", install_state_path(root).exists()),
            ("source plan metadata recorded", bool(load_state(root).get("source", {}).get("plan"))),
        ],
        "Eval Coverage": [
            ("at least three eval definitions", len(list((root / "evals").glob("*.json"))) >= 3 if (root / "evals").exists() else False),
            ("benchmark runner wrapper exists", (root / "maintenance" / "scripts" / "codex-eval.ps1").exists()),
            ("audit command exists", (root / "maintenance" / "scripts" / "codex-harness-audit.ps1").exists()),
            ("eval results exist", (root / "reports" / "eval-results.jsonl").exists()),
        ],
        "Security Guardrails": [
            (".gitignore exists", (root / ".gitignore").exists()),
            ("security module available", "security" in MODULES),
            ("stale active references absent", not stale_active_references(root)),
            ("global scan active hits absent", global_scan.get("active_hit_count", 0) == 0),
        ],
        "Cost Efficiency": [
            ("tool result artifact directory exists", (root / "artifacts" / "tool-results").exists()),
            ("workspace dependencies disabled in config", check_config(root).get("status") == "pass"),
            ("large-output storage documented", (root / "artifacts" / "tool-results" / "README.md").exists()),
            ("reports directory excluded from global scan recursion", "reports/**" in " ".join(global_scan.get("patterns", [])) or global_scan.get("content_redacted") is True),
        ],
    }
    categories = []
    total_pass = 0
    total_count = 0
    top_actions = []
    for category, items in checks.items():
        passed = sum(1 for _, ok in items if ok)
        total = len(items)
        total_pass += passed
        total_count += total
        failures = [name for name, ok in items if not ok]
        if failures:
            top_actions.append(f"{category}: {failures[0]}")
        categories.append({"name": category, "passed": passed, "total": total, "failures": failures})
    score = round((total_pass / total_count) * 100, 2) if total_count else 0
    return {
        "rubric_version": RUBRIC_VERSION,
        "generated_at": utc_now(),
        "score": score,
        "status": "pass" if score >= 80 and not top_actions else "fail",
        "categories": categories,
        "top_actions": top_actions[:7],
    }


def cmd_audit(args: argparse.Namespace) -> int:
    root = root_path(args)
    data = audit_data(root)
    ensure_dir(root / "reports")
    write_json(root / "reports" / "harness-audit.latest.json", data)
    text = ["# Harness Audit", "", f"- rubric_version: {data['rubric_version']}", f"- score: {data['score']}", f"- status: {data['status']}", "", "## Categories"]
    for category in data["categories"]:
        text.append(f"- {category['name']}: {category['passed']}/{category['total']}")
    text.extend(["", "## Top Actions"])
    text.extend(f"- {item}" for item in data["top_actions"] or ["None"])
    write_text(root / "reports" / "harness-audit.latest.md", "\n".join(text) + "\n")
    if args.json:
        print(json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True))
    else:
        print("\n".join(text))
    return 0 if data["status"] == "pass" else 1


def cmd_context(args: argparse.Namespace) -> int:
    root = root_path(args)
    files = discover_instruction_files(root)
    selected = files[0]["path"] if files else None
    report = {
        "generated_at": utc_now(),
        "discovered_instruction_files": files,
        "selected_primary_instruction_source": selected,
        "skipped_instruction_sources": [f["path"] for f in files[1:]],
        "truncation_decisions": [],
        "warnings": [],
        "estimated_context_size_bytes": sum(f["bytes"] for f in files[:2]),
    }
    write_json(root / "reports" / "context-inspection.latest.json", report)
    lines = ["# Context Inspection", "", f"- selected_primary_instruction_source: {selected}", f"- estimated_context_size_bytes: {report['estimated_context_size_bytes']}", "", "## Discovered"]
    lines.extend(f"- {f['path']} ({f['bytes']} bytes)" for f in files)
    write_text(root / "reports" / "context-inspection.latest.md", "\n".join(lines) + "\n")
    print(root / "reports" / "context-inspection.latest.md")
    return 0


def cmd_verify(args: argparse.Namespace) -> int:
    root = root_path(args)
    checks = []
    checks.append({"name": "doctor", **run_command([sys.executable, "maintenance/scripts/codex_agent_harness.py", "doctor", "--json"], root)})
    checks.append({"name": "global_scan", **run_command([sys.executable, "maintenance/scripts/codex_agent_harness.py", "global-scan"], root, timeout=240)})
    checks.append({"name": "audit", **run_command([sys.executable, "maintenance/scripts/codex_agent_harness.py", "audit", "--json"], root)})
    checks.append({"name": "python_compile", **run_command([sys.executable, "-m", "py_compile", "maintenance/scripts/codex_agent_harness.py"], root)})
    checks.append({"name": "self_test", **run_command([sys.executable, "maintenance/scripts/codex_agent_harness.py", "self-test"], root)})
    checks.append({"name": "repair_dry_run", **run_command([sys.executable, "maintenance/scripts/codex_agent_harness.py", "repair"], root)})
    checks.append({"name": "uninstall_dry_run", **run_command([sys.executable, "maintenance/scripts/codex_agent_harness.py", "uninstall"], root)})
    if command_exists("pwsh"):
        checks.append(
            {
                "name": "hook_ast_parse",
                **run_command(
                    [
                        "pwsh",
                        "-NoProfile",
                        "-Command",
                        "$tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseFile('hooks/lightweight-codex-hook.ps1',[ref]$tokens,[ref]$errors)>$null; if($errors.Count){$errors | ConvertTo-Json; exit 1}else{'OK'}",
                    ],
                    root,
                ),
            }
        )
    status = "pass" if all(item["status"] == "pass" for item in checks) else "fail"
    report = {"generated_at": utc_now(), "status": status, "checks": checks}
    write_json(root / "reports" / "verification.latest.json", report)
    write_text(
        root / "reports" / "verification.latest.md",
        "# Verification\n\n" + "\n".join(f"- {c['name']}: {c['status']} ({c['exit_code']})" for c in checks) + "\n",
    )
    print(root / "reports" / "verification.latest.md")
    return 0 if status == "pass" else 1


def cmd_eval(args: argparse.Namespace) -> int:
    root = root_path(args)
    eval_ids = [args.eval_id] if args.eval_id else [p.stem for p in sorted((root / "evals").glob("*.json"))]
    results = []
    for eval_id in eval_ids:
        if eval_id == "config-parse":
            passed = check_config(root).get("status") == "pass"
        elif eval_id == "managed-files":
            passed = check_managed_files(root).get("status") == "pass"
        elif eval_id == "audit-threshold":
            passed = audit_data(root).get("score", 0) >= 80
        else:
            passed = False
        results.append({"eval_id": eval_id, "status": "pass" if passed else "fail", "timestamp": utc_now()})
    ensure_dir(root / "reports")
    result_path = root / "reports" / "eval-results.jsonl"
    with result_path.open("a", encoding="utf-8", newline="\n") as f:
        for item in results:
            f.write(json.dumps(item, ensure_ascii=False, sort_keys=True) + "\n")
    print(result_path)
    return 0 if all(item["status"] == "pass" for item in results) else 1


def cmd_global_scan(args: argparse.Namespace) -> int:
    root = root_path(args)
    user_home = root.parent
    candidate_roots = [
        root,
        user_home / "code",
        user_home / "Documents" / "Codex",
        user_home / "AppData" / "Roaming" / "npm",
        user_home / "AppData" / "Local" / "Programs",
    ]
    scan_roots = [path for path in candidate_roots if path.exists()]
    patterns = [
        r"c:\\users\\anise\\documents\\codex\\2026-05-09\\codex",
        r"bundled-marketplaces",
        r"vendor_imports",
        r"wshobson-agents-scan",
        r"plugins\\cache",
        r"plugins\\plugins",
        r"\\\.tmp\\",
        r"\\tmp\\",
        r"runCodexInWindowsSubsystemForLinux\"\s*:\s*true",
        r"wsl\.exe|VmmemWSL|\\\\wsl",
    ]
    globs = [
        "--glob",
        "!Desktop/**",
        "--glob",
        "!reports/**",
        "--glob",
        "!maintenance/reports/**",
        "--glob",
        "!maintenance/scripts/codex_agent_harness.py",
        "--glob",
        "!**/node_modules/**",
        "--glob",
        "!**/.git/**",
        "--glob",
        "!**/*.sqlite",
        "--glob",
        "!**/*.sqlite-*",
        "--glob",
        "!**/*.db",
        "--glob",
        "!**/auth.json",
        "--glob",
        "!**/.credentials.json",
        "--glob",
        "!**/.env",
    ]
    matches: list[dict[str, Any]] = []
    if command_exists("rg"):
        for pattern in patterns:
            command = ["rg", "--hidden", "--line-number", "--no-heading", "--fixed-strings"]
            if pattern.startswith("runCodex") or "wsl" in pattern.lower():
                command = ["rg", "--hidden", "--line-number", "--no-heading"]
            command.extend(globs)
            command.append(pattern)
            command.extend(str(path) for path in scan_roots)
            result = run_command(command, root, timeout=180)
            if result["exit_code"] in {0, 1}:
                for line in result["stdout_preview"].splitlines():
                    parsed = re.match(r"^(.+):(\d+):(.*)$", line)
                    if parsed:
                        path_text, line_text, _text = parsed.groups()
                        matches.append(
                            {
                                "pattern": clean_report_string(pattern),
                                "path": clean_report_string(path_text, 1000),
                                "line": clean_report_string(line_text, 32),
                            }
                        )
            else:
                matches.append({"pattern": clean_report_string(pattern), "path": "<scan-error>", "line": "", "error": clean_report_string(result["stderr_preview"])})
    else:
        matches.append({"pattern": "<all>", "path": "<not-run>", "line": "", "error": "rg not available"})

    active_roots = [str(root / "config.toml"), str(root / ".codex-global-state.json"), str(root / "hooks.json"), str(root / "AGENTS.md")]
    active_hits = []
    for match in matches:
        if match["path"] in {"<scan-error>", "<not-run>"}:
            continue
        try:
            match_path = Path(match["path"]).resolve()
        except OSError:
            continue
        if any(match_path == Path(p).resolve() for p in active_roots):
            active_hits.append(match)
    report = {
        "generated_at": utc_now(),
        "scan_roots": [str(path) for path in scan_roots],
        "desktop_excluded": True,
        "content_redacted": True,
        "patterns": patterns,
        "match_count": len(matches),
        "active_hit_count": len(active_hits),
        "status": "pass" if not active_hits else "fail",
        "active_hits": active_hits,
        "matches_preview": matches[:200],
    }
    write_json(root / "reports" / "global-scan.latest.json", report)
    lines = [
        "# Global Development Environment Scan",
        "",
        f"- status: {report['status']}",
        f"- match_count: {report['match_count']}",
        f"- active_hit_count: {report['active_hit_count']}",
        f"- desktop_excluded: {report['desktop_excluded']}",
        "",
        "## Scan Roots",
    ]
    lines.extend(f"- {path}" for path in report["scan_roots"])
    lines.extend(["", "## Active Hits"])
    lines.extend(f"- {hit['path']}:{hit['line']} pattern={hit['pattern']}" for hit in active_hits or [])
    if not active_hits:
        lines.append("- None")
    write_text(root / "reports" / "global-scan.latest.md", "\n".join(lines) + "\n")
    print(root / "reports" / "global-scan.latest.md")
    return 0 if report["status"] == "pass" else 1


def cmd_merge_config(args: argparse.Namespace) -> int:
    root = root_path(args)
    source = Path(args.source).resolve()
    target = Path(args.target).resolve()
    try:
        source_data = tomllib.loads(read_text(source))
        target_data = tomllib.loads(read_text(target))
    except Exception as exc:  # noqa: BLE001
        print(f"invalid TOML: {exc}", file=sys.stderr)
        return 2
    missing_lines = []
    drift = []
    for key, value in source_data.items():
        if key not in target_data:
            missing_lines.append(format_toml_value(key, value))
        elif target_data[key] != value:
            drift.append(key)
    result = {"source": str(source), "target": str(target), "missing_root_keys": len(missing_lines), "drift": drift, "dry_run": not args.apply}
    if args.apply and missing_lines:
        backup = backup_file(target, root)
        with target.open("a", encoding="utf-8", newline="\n") as f:
            f.write("\n# Added by codex-agent-harness merge-config\n")
            for line in missing_lines:
                f.write(line + "\n")
        result["backup"] = str(backup)
    print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


def format_toml_value(key: str, value: Any) -> str:
    if isinstance(value, bool):
        return f"{key} = {'true' if value else 'false'}"
    if isinstance(value, str):
        return f'{key} = "{value}"'
    if isinstance(value, (int, float)):
        return f"{key} = {value}"
    return f"# {key}: complex table omitted; append manually after review"


def cmd_self_test(args: argparse.Namespace) -> int:
    import tempfile

    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        write_text(root / "config.toml", "[features]\nplugins = true\ncodex_hooks = true\nmulti_agent = true\nchild_agents_md = true\ntool_search = true\ntool_suggest = true\nskill_mcp_dependency_install = true\nworkspace_dependencies = false\n")
        write_text(root / "AGENTS.md", "# Test\n")
        write_text(root / ".gitignore", "auth.json\n.codex-global-state.json\n__pycache__/\n*.pyc\n")
        write_text(root / "maintenance" / "MCP_RUNTIME_STATUS.md", "# MCP\n")
        write_text(root / "hooks" / "lightweight-codex-hook.ps1", "$ErrorActionPreference = 'Stop'\n")
        ensure_dir(root / "toolchains" / "shims")
        write_json(root / "reports" / "global-scan.latest.json", {"content_redacted": True, "active_hit_count": 0})
        write_text(root / "reports" / "eval-results.jsonl", "")
        ns = argparse.Namespace(root=str(root), profile="developer", module=None)
        cmd_apply(ns)
        if doctor_data(root)["status"] != "pass":
            print("doctor failed in self-test", file=sys.stderr)
            return 1
        if audit_data(root)["score"] < 80:
            print("audit score too low in self-test", file=sys.stderr)
            return 1
    print("self-test pass")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Local Codex harness")
    parser.add_argument("--root", default=".", help="CODEX_HOME / harness root")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("discovery").set_defaults(func=cmd_discovery)
    p = sub.add_parser("plan")
    p.add_argument("--profile", default=DEFAULT_PROFILE)
    p.add_argument("--module", action="append")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_plan)
    p = sub.add_parser("apply")
    p.add_argument("--profile", default=DEFAULT_PROFILE)
    p.add_argument("--module", action="append")
    p.set_defaults(func=cmd_apply)
    p = sub.add_parser("doctor")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_doctor)
    p = sub.add_parser("repair")
    p.add_argument("--apply", action="store_true")
    p.set_defaults(func=cmd_repair)
    p = sub.add_parser("uninstall")
    p.add_argument("--apply", action="store_true")
    p.set_defaults(func=cmd_uninstall)
    p = sub.add_parser("audit")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_audit)
    sub.add_parser("context").set_defaults(func=cmd_context)
    sub.add_parser("verify").set_defaults(func=cmd_verify)
    p = sub.add_parser("eval")
    p.add_argument("--eval-id")
    p.set_defaults(func=cmd_eval)
    sub.add_parser("global-scan").set_defaults(func=cmd_global_scan)
    p = sub.add_parser("merge-config")
    p.add_argument("--source", required=True)
    p.add_argument("--target", required=True)
    p.add_argument("--apply", action="store_true")
    p.add_argument("--update-managed", action="store_true")
    p.set_defaults(func=cmd_merge_config)
    sub.add_parser("self-test").set_defaults(func=cmd_self_test)
    return parser


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
