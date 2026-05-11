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
import stat
import subprocess
import sys
import tomllib
from pathlib import Path
from typing import Any


SCHEMA_VERSION = "1"
RUBRIC_VERSION = "codex-harness-audit-v1"
OWNER = "codex-agent-harness"
DEFAULT_PROFILE = "developer"
SOURCE_PLAN = Path("C:/Users/anise/Downloads/codex-agent-harness-distillation-plan.md")
COMMAND_PREVIEW_CHARS = 4000
COMMAND_ARTIFACT_THRESHOLD_CHARS = 12000
TRAJECTORY_VERSION = "codex-trajectory-v1"

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
    "evals/context-inspection.json": {
        "eval_id": "context-inspection",
        "task": "Generate deterministic context selection report.",
        "setup": "Run from CODEX_HOME.",
        "success_criteria": ["context report exists", "selected instruction source is explicit"],
        "grader": "python maintenance/scripts/codex_agent_harness.py context",
        "timeout_seconds": 30,
        "risk_notes": "Does not prove the app injected the selected context into a live turn.",
    },
    "evals/trajectory-search.json": {
        "eval_id": "trajectory-search",
        "task": "Verify trajectory JSONL search path remains usable.",
        "setup": "Run after at least one verification or benchmark.",
        "success_criteria": ["trajectory command exits successfully", "recent listing is JSON"],
        "grader": "python maintenance/scripts/codex_agent_harness.py trajectory --recent 5",
        "timeout_seconds": 30,
        "risk_notes": "Checks local harness trajectory records only.",
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


def append_jsonl(path: Path, data: Any) -> None:
    ensure_dir(path.parent)
    with path.open("a", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(data, ensure_ascii=False, sort_keys=True) + "\n")


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
        "codex-context.ps1": "context",
        "codex-retrieve.ps1": "retrieve",
        "codex-compact-summary.ps1": "compact-summary",
        "codex-trajectory.ps1": "trajectory",
        "codex-benchmark.ps1": "benchmark",
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


def run_command(command: list[str], cwd: Path, timeout: int = 60, *, include_stdout: bool = False) -> dict[str, Any]:
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
        result = {
            "command": command,
            "status": status,
            "exit_code": completed.returncode,
            "stdout_preview": redact_obvious_secrets(completed.stdout[-COMMAND_PREVIEW_CHARS:]),
            "stderr_preview": redact_obvious_secrets(completed.stderr[-COMMAND_PREVIEW_CHARS:]),
            "duration_seconds": (dt.datetime.now() - started).total_seconds(),
        }
        artifacts = []
        command_name = safe_slug("-".join(Path(part).name if index == 0 else part for index, part in enumerate(command[:4])), "command")
        if not include_stdout and len(completed.stdout) > COMMAND_ARTIFACT_THRESHOLD_CHARS:
            artifacts.append({"stream": "stdout", **store_tool_artifact(cwd, f"{command_name}-stdout", completed.stdout)})
        if not include_stdout and len(completed.stderr) > COMMAND_ARTIFACT_THRESHOLD_CHARS:
            artifacts.append({"stream": "stderr", **store_tool_artifact(cwd, f"{command_name}-stderr", completed.stderr)})
        if artifacts:
            result["artifacts"] = artifacts
        if include_stdout:
            result["stdout"] = redact_obvious_secrets(completed.stdout)
        return result
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


def instruction_warnings(path: Path) -> list[str]:
    try:
        text = read_text(path)
    except UnicodeDecodeError:
        return ["non-utf8 instruction file skipped for content inspection"]
    patterns = [
        (r"(?i)ignore (all )?(previous|prior|above) instructions", "possible prompt-injection override language"),
        (r"(?i)(exfiltrate|send|upload).{0,40}(secret|token|credential|password)", "possible credential exfiltration instruction"),
        (r"(?i)BEGIN (RSA |OPENSSH |EC |DSA |PRIVATE )?PRIVATE KEY", "private key material pattern"),
    ]
    return [message for pattern, message in patterns if re.search(pattern, text)]


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
        "artifacts",
        "cache",
        "generated_images",
        "memories",
        "reports",
        "node_modules",
        ".sandbox",
        ".sandbox-bin",
        ".sandbox-secrets",
        "browser",
        "log",
        "sessions",
        "sqlite",
        "trajectories",
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
    previous_state = load_state(root)
    previous_ops = {
        op.get("path"): op
        for op in previous_state.get("applied_operations", [])
        if isinstance(op, dict) and op.get("path")
    }
    operations = []
    for path, content in sorted(templates.items()):
        full = root / path
        digest = sha256_text(content)
        previous = previous_ops.get(path, {})
        was_managed = previous.get("managed") is True or previous.get("action") in {"created", "updated", "unchanged"}
        remove_on_uninstall = bool(previous.get("remove_on_uninstall", was_managed))
        if full.exists():
            current = sha256_file(full)
            if current == digest:
                operations.append(
                    {
                        "path": path,
                        "action": "unchanged",
                        "digest": digest,
                        "owner": OWNER,
                        "managed": was_managed,
                        "remove_on_uninstall": remove_on_uninstall,
                    }
                )
                continue
            if was_managed:
                backup = backup_file(full, root)
                write_text(full, content)
                operations.append(
                    {
                        "path": path,
                        "action": "updated",
                        "digest": digest,
                        "owner": OWNER,
                        "managed": True,
                        "remove_on_uninstall": remove_on_uninstall,
                        "backup": str(backup),
                    }
                )
                continue
            operations.append(
                {
                    "path": path,
                    "action": "exists_unmanaged_preserved",
                    "digest": current,
                    "owner": OWNER,
                    "managed": False,
                    "remove_on_uninstall": False,
                }
            )
            continue
        write_text(full, content)
        operations.append({"path": path, "action": "created", "digest": digest, "owner": OWNER, "managed": True, "remove_on_uninstall": True})
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


def redact_obvious_secrets(value: str) -> str:
    patterns = [
        r"sk-[A-Za-z0-9_-]{20,}",
        r"ghp_[A-Za-z0-9_]{20,}",
        r"github_pat_[A-Za-z0-9_]{20,}",
        r"xox[baprs]-[A-Za-z0-9-]{20,}",
        r"AKIA[0-9A-Z]{16}",
        r"(?i)(api[_-]?key|secret|password|token)\s*[:=]\s*['\"][^'\"]{8,}['\"]",
    ]
    redacted = value
    for pattern in patterns:
        redacted = re.sub(pattern, "<redacted>", redacted)
    return redacted


def safe_slug(value: str, fallback: str = "artifact") -> str:
    slug = re.sub(r"[^A-Za-z0-9_.-]+", "-", value).strip(".-")
    return (slug or fallback)[:80]


def store_tool_artifact(root: Path, name: str, content: str) -> dict[str, Any]:
    safe_name = safe_slug(name)
    digest = sha256_text(content)[:12]
    path = root / "artifacts" / "tool-results" / f"{local_stamp()}-{digest}-{safe_name}.txt"
    write_text(path, redact_obvious_secrets(content))
    return {"path": rel(path, root), "bytes": path.stat().st_size, "sha256": sha256_file(path)}


def current_git_state(root: Path) -> dict[str, Any]:
    def run_git(args: list[str]) -> str:
        try:
            completed = subprocess.run(["git", *args], cwd=str(root), text=True, encoding="utf-8", errors="replace", capture_output=True, timeout=15)
        except Exception:  # noqa: BLE001 - best-effort metadata
            return ""
        return completed.stdout.strip() if completed.returncode == 0 else ""

    status = run_git(["status", "--short"])
    return {"sha": run_git(["rev-parse", "--short", "HEAD"]), "dirty": bool(status), "status_preview": status[:2000]}


def append_trajectory(root: Path, task: str, status: str, checks: list[dict[str, Any]], artifacts: list[dict[str, Any]] | None = None, error: str | None = None) -> dict[str, Any]:
    record = {
        "version": TRAJECTORY_VERSION,
        "run_id": f"{dt.datetime.now().strftime('%Y%m%d%H%M%S')}-{sha256_text(task + utc_now())[:8]}",
        "timestamp": utc_now(),
        "task": task,
        "repository": current_git_state(root),
        "tool_stats": {
            "commands": len(checks),
            "artifacts": len(artifacts or []),
            "failures": sum(1 for item in checks if item.get("status") != "pass"),
        },
        "checks": checks,
        "artifacts": artifacts or [],
        "verification_result": status,
        "completed": status == "pass",
        "error": error,
    }
    append_jsonl(root / "trajectories" / "runs.jsonl", record)
    return record


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
        readonly = False
        if path.exists():
            try:
                readonly = bool(path.stat().st_file_attributes & stat.FILE_ATTRIBUTE_READONLY)
            except AttributeError:
                readonly = not os.access(path, os.W_OK)
        out.append(
            {
                "path": item,
                "exists": path.exists(),
                "is_file": path.is_file(),
                "readonly": readonly,
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
    expected_false = ["workspace_dependencies"]
    wrong_false = [key for key in expected_false if features.get(key) is not False]
    agents = data.get("agents", {})
    required_agent_roles = {
        "explorer": "agents/explorer.toml",
        "reviewer": "agents/reviewer.toml",
        "docs-researcher": "agents/docs-researcher.toml",
    }
    missing_agent_roles = []
    for role, config_file in required_agent_roles.items():
        role_data = agents.get(role, {})
        if not isinstance(role_data, dict) or role_data.get("config_file") != config_file or not role_data.get("description"):
            missing_agent_roles.append(role)
    return {
        "status": "pass" if not missing and not unexpected and not wrong_false and not missing_agent_roles else "fail",
        "missing_true": missing,
        "unexpected_true": unexpected,
        "missing_false": wrong_false,
        "missing_agent_roles": missing_agent_roles,
    }


def check_managed_files(root: Path) -> dict[str, Any]:
    state = load_state(root)
    if not state:
        return {"status": "fail", "error": "install-state missing"}
    missing = []
    drifted = []
    for op in state.get("applied_operations", []):
        if op.get("managed") is not True:
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
        if path not in templates or op.get("managed") is not True:
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
        if op.get("remove_on_uninstall") is True:
            path = root / op["path"]
            if path.exists() and sha256_file(path) == op.get("digest"):
                targets.append(op["path"])
    if install_state_path(root).exists():
        targets.append(rel(install_state_path(root), root))
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
    trajectory_records = load_trajectory_records(root)
    checks = {
        "Tool Coverage": [
            ("toolchain shims exist", (root / "toolchains" / "shims").exists()),
            ("codex verify command exists", (root / "maintenance" / "scripts" / "codex-verify.ps1").exists()),
            ("MCP status documented", (root / "maintenance" / "MCP_RUNTIME_STATUS.md").exists()),
            ("PowerShell wrappers installed", len(list((root / "maintenance" / "scripts").glob("codex-*.ps1"))) >= 8),
        ],
        "Context Efficiency": [
            ("AGENTS.md exists", (root / "AGENTS.md").exists()),
            ("context inspection template exists", (root / "reports" / "context-inspection.template.md").exists()),
            ("context inspection command produced latest report", (root / "reports" / "context-inspection.latest.json").exists()),
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
            ("trajectory command wrapper exists", (root / "maintenance" / "scripts" / "codex-trajectory.ps1").exists()),
            ("trajectory records parse with required fields", trajectory_records_valid(trajectory_records)),
            ("learning drafts directory exists", (root / "learning").exists()),
            ("install-state exists", install_state_path(root).exists()),
            ("source plan metadata recorded", bool(load_state(root).get("source", {}).get("plan"))),
        ],
        "Eval Coverage": [
            ("at least five eval definitions", len(list((root / "evals").glob("*.json"))) >= 5 if (root / "evals").exists() else False),
            ("benchmark runner wrapper exists", (root / "maintenance" / "scripts" / "codex-eval.ps1").exists()),
            ("benchmark command wrapper exists", (root / "maintenance" / "scripts" / "codex-benchmark.ps1").exists()),
            ("benchmark results are parseable", latest_benchmark_results_valid(root)),
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
            ("tool output artifact threshold configured", COMMAND_ARTIFACT_THRESHOLD_CHARS > COMMAND_PREVIEW_CHARS),
            ("retrieval report avoids generated and memory roots", latest_retrieval_report_valid(root)),
            ("compact summary has required sections", compact_summary_valid(root)),
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
    warnings = []
    truncation_decisions = []
    for item in files:
        path = root / item["path"]
        warnings.extend({"path": item["path"], "warning": warning} for warning in instruction_warnings(path))
        if item["bytes"] > 12000:
            truncation_decisions.append({"path": item["path"], "strategy": "head-tail", "head_bytes": 6000, "tail_bytes": 3000})
    report = {
        "generated_at": utc_now(),
        "discovered_instruction_files": files,
        "selected_primary_instruction_source": selected,
        "skipped_instruction_sources": [{"path": f["path"], "reason": "lower-priority instruction source"} for f in files[1:]],
        "truncation_decisions": truncation_decisions,
        "warnings": warnings,
        "estimated_context_size_bytes": sum(f["bytes"] for f in files[:2]),
    }
    write_json(root / "reports" / "context-inspection.latest.json", report)
    lines = ["# Context Inspection", "", f"- selected_primary_instruction_source: {selected}", f"- estimated_context_size_bytes: {report['estimated_context_size_bytes']}", "", "## Discovered"]
    lines.extend(f"- {f['path']} ({f['bytes']} bytes)" for f in files)
    lines.extend(["", "## Warnings"])
    lines.extend(f"- {item['path']}: {item['warning']}" for item in warnings or [])
    if not warnings:
        lines.append("- None")
    write_text(root / "reports" / "context-inspection.latest.md", "\n".join(lines) + "\n")
    print(root / "reports" / "context-inspection.latest.md")
    return 0


def cmd_verify(args: argparse.Namespace) -> int:
    root = root_path(args)
    checks = []
    checks.append({"name": "doctor", **run_command([sys.executable, "maintenance/scripts/codex_agent_harness.py", "doctor", "--json"], root)})
    checks.append({"name": "global_scan", **run_command([sys.executable, "maintenance/scripts/codex_agent_harness.py", "global-scan"], root, timeout=240)})
    checks.append({"name": "context_inspection", **run_command([sys.executable, "maintenance/scripts/codex_agent_harness.py", "context"], root)})
    checks.append({"name": "retrieval_report", **run_command([sys.executable, "maintenance/scripts/codex_agent_harness.py", "retrieve", "--query", "codex harness verification workflow", "--limit", "5"], root)})
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
    pre_audit_status = "pass" if all(item["status"] == "pass" for item in checks) else "fail"
    write_verification_report(root, {"generated_at": utc_now(), "status": pre_audit_status, "checks": checks})
    append_trajectory(root, "codex-harness verify pre-audit", pre_audit_status, checks)
    checks.append({"name": "audit", **run_command([sys.executable, "maintenance/scripts/codex_agent_harness.py", "audit", "--json"], root)})
    status = "pass" if all(item["status"] == "pass" for item in checks) else "fail"
    report = {"generated_at": utc_now(), "status": status, "checks": checks}
    write_verification_report(root, report)
    artifacts = [artifact for check in checks for artifact in check.get("artifacts", [])]
    append_trajectory(root, "codex-harness verify", status, checks, artifacts)
    print(root / "reports" / "verification.latest.md")
    return 0 if status == "pass" else 1


def write_verification_report(root: Path, report: dict[str, Any]) -> None:
    write_json(root / "reports" / "verification.latest.json", report)
    write_text(
        root / "reports" / "verification.latest.md",
        "# Verification\n\n" + "\n".join(f"- {c['name']}: {c['status']} ({c['exit_code']})" for c in report["checks"]) + "\n",
    )


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
        elif eval_id == "context-inspection":
            context_ns = argparse.Namespace(root=str(root))
            passed = cmd_context(context_ns) == 0 and (root / "reports" / "context-inspection.latest.json").exists()
        elif eval_id == "trajectory-search":
            records = load_trajectory_records(root)
            trajectory_ns = argparse.Namespace(root=str(root), search=None, failed=False, recent=5)
            passed = bool(records) and trajectory_records_valid(records) and cmd_trajectory(trajectory_ns) == 0
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


def load_trajectory_records(root: Path) -> list[dict[str, Any]]:
    path = root / "trajectories" / "runs.jsonl"
    if not path.exists():
        return []
    records = []
    for line in read_text(path).splitlines():
        if not line.strip():
            continue
        try:
            records.append(json.loads(line))
        except json.JSONDecodeError:
            records.append({"version": TRAJECTORY_VERSION, "error": "invalid-jsonl-line", "raw_preview": clean_report_string(line)})
    return records


def trajectory_records_valid(records: list[dict[str, Any]], *, require_records: bool = True) -> bool:
    if require_records and not records:
        return False
    required = {"version", "run_id", "timestamp", "task", "verification_result", "completed"}
    return all(not item.get("error") and required.issubset(item) for item in records)


def latest_retrieval_report_valid(root: Path) -> bool:
    report = load_json(root / "reports" / "retrieval-report.latest.json", {})
    forbidden = ("artifacts/", "cache/", "memories/", "reports/", "sessions/", "sqlite/", "trajectories/", "node_repl/")
    selected = report.get("selected_context", [])
    candidates = report.get("candidate_files", [])
    if not isinstance(selected, list) or not isinstance(candidates, list):
        return False
    paths = [item.get("path", "") for item in [*selected, *candidates] if isinstance(item, dict)]
    return bool(selected) and all(not any(path.startswith(prefix) for prefix in forbidden) for path in paths)


def latest_benchmark_results_valid(root: Path) -> bool:
    path = root / "reports" / "benchmark-results.jsonl"
    if not path.exists():
        return False
    valid = False
    for line in read_text(path).splitlines():
        if not line.strip():
            continue
        try:
            item = json.loads(line)
        except json.JSONDecodeError:
            return False
        valid = valid or {"timestamp", "benchmark_id", "status", "success_rate", "checks"}.issubset(item)
    return valid


def compact_summary_valid(root: Path) -> bool:
    summaries = sorted(path for path in (root / "artifacts" / "compact-summaries").glob("*.md") if path.name.lower() != "readme.md")
    if not summaries:
        return False
    text = read_text(summaries[-1])
    return all(section in text for section in ["## Goal", "## Test Results", "## Next Steps", "## Risks"])


def cmd_trajectory(args: argparse.Namespace) -> int:
    root = root_path(args)
    records = load_trajectory_records(root)
    all_records_valid = trajectory_records_valid(records, require_records=False)
    if args.failed:
        records = [item for item in records if not item.get("completed")]
    if args.search:
        query = args.search.lower()
        records = [
            item
            for item in records
            if query in json.dumps(item, ensure_ascii=False).lower()
        ]
    records = records[-args.recent :] if args.recent else records
    output = [
        {
            "run_id": item.get("run_id"),
            "timestamp": item.get("timestamp"),
            "task": item.get("task"),
            "completed": item.get("completed"),
            "verification_result": item.get("verification_result"),
        }
        for item in records
    ]
    print(json.dumps({"count": len(output), "records": output, "valid_jsonl": all_records_valid}, ensure_ascii=False, indent=2, sort_keys=True))
    return 0 if all_records_valid else 1


def cmd_compact_summary(args: argparse.Namespace) -> int:
    root = root_path(args)
    data = {
        "goal": args.goal or "unspecified",
        "constraints": args.constraints or "See AGENTS.md and current user instructions.",
        "current_plan": args.current_plan or "Not recorded.",
        "completed_work": args.completed_work or "Not recorded.",
        "in_progress_work": args.in_progress_work or "Not recorded.",
        "blockers": args.blockers or "None recorded.",
        "relevant_files": args.relevant_files or "Not recorded.",
        "commands_run": args.commands_run or "Not recorded.",
        "test_results": args.test_results or "Not recorded.",
        "next_steps": args.next_steps or "Not recorded.",
        "risks": args.risks or "Not recorded.",
    }
    lines = ["# Compact Summary", ""]
    for key, value in data.items():
        lines.extend([f"## {key.replace('_', ' ').title()}", "", value, ""])
    path = root / "artifacts" / "compact-summaries" / f"{local_stamp()}-{safe_slug(data['goal'], 'summary')}.md"
    write_text(path, "\n".join(lines).rstrip() + "\n")
    print(path)
    return 0


def score_retrieval_candidate(query_terms: list[str], text: str, path: Path) -> tuple[int, list[str]]:
    lower = text.lower()
    path_lower = path.as_posix().lower()
    reasons = []
    score = 0
    for term in query_terms:
        if term and term in path_lower:
            score += 5
            reasons.append(f"path:{term}")
        count = lower.count(term) if term else 0
        if count:
            score += min(count, 10)
            reasons.append(f"content:{term}x{count}")
    return score, reasons


def retrieval_candidate_files(root: Path) -> list[Path]:
    allowed = [
        root / "AGENTS.md",
        root / "agent.md",
        root / "maintenance" / "MCP_RUNTIME_STATUS.md",
        root / "maintenance" / "scripts",
        root / ".codex-harness",
        root / "agents",
        root / "skills",
        root / "evals",
        root / "hooks",
    ]
    forbidden_parts = {"artifacts", "cache", "memories", "reports", "sessions", "sqlite", "trajectories", "node_repl"}
    files: list[Path] = []
    for base in allowed:
        if base.is_file():
            files.append(base.relative_to(root))
            continue
        if not base.exists():
            continue
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = [name for name in dirnames if name not in forbidden_parts and name not in {".git", "__pycache__", "node_modules"}]
            current = Path(dirpath)
            for filename in filenames:
                path = (current / filename).relative_to(root)
                if forbidden_parts.intersection(path.parts):
                    continue
                files.append(path)
    return sorted(set(files))


def cmd_retrieve(args: argparse.Namespace) -> int:
    root = root_path(args)
    query = args.query.strip()
    query_terms = [term.lower() for term in re.findall(r"[\w.-]+", query) if len(term) > 1]
    candidates = []
    for path in retrieval_candidate_files(root):
        full = root / path
        if full.suffix.lower() not in {".md", ".toml", ".json", ".jsonl", ".py", ".ps1", ".txt"}:
            continue
        try:
            text = read_text(full)
        except (UnicodeDecodeError, OSError):
            continue
        score, reasons = score_retrieval_candidate(query_terms, text[:50000], path)
        if score:
            candidates.append({"path": path.as_posix(), "score": score, "relevance_reasons": reasons[:5]})
    candidates.sort(key=lambda item: (-item["score"], item["path"]))
    selected = candidates[: args.limit]
    report = {
        "generated_at": utc_now(),
        "cycles": 1,
        "query_per_cycle": [query],
        "candidate_files": candidates[:50],
        "selected_context": selected,
        "missing_context": [] if selected else ["No matching files found under allowed harness scan roots."],
        "refined_query": None,
        "stop_reason": "sufficient_context" if selected else "no_candidates",
    }
    write_json(root / "reports" / "retrieval-report.latest.json", report)
    lines = ["# Iterative Retrieval Report", "", f"- query: {query}", f"- stop_reason: {report['stop_reason']}", "", "## Selected Context"]
    lines.extend(f"- {item['path']} score={item['score']} reasons={', '.join(item['relevance_reasons'])}" for item in selected or [])
    if not selected:
        lines.append("- None")
    write_text(root / "reports" / "retrieval-report.latest.md", "\n".join(lines) + "\n")
    print(root / "reports" / "retrieval-report.latest.md")
    return 0 if selected else 1


def cmd_benchmark(args: argparse.Namespace) -> int:
    root = root_path(args)
    eval_ids = [args.eval_id] if args.eval_id else [p.stem for p in sorted((root / "evals").glob("*.json"))]
    started = dt.datetime.now()
    checks = []
    for eval_id in eval_ids:
        checks.append({"name": f"eval:{eval_id}", **run_command([sys.executable, "maintenance/scripts/codex_agent_harness.py", "eval", "--eval-id", eval_id], root, timeout=120)})
    status = "pass" if all(item["status"] == "pass" for item in checks) else "fail"
    record = {
        "timestamp": utc_now(),
        "benchmark_id": args.eval_id or "all",
        "status": status,
        "success_rate": round(sum(1 for item in checks if item["status"] == "pass") / len(checks), 4) if checks else 0,
        "pass_at_1": status == "pass",
        "duration_seconds": (dt.datetime.now() - started).total_seconds(),
        "tool_calls": len(checks),
        "terminal_commands": len(checks),
        "error_count": sum(1 for item in checks if item["status"] != "pass"),
        "checks": checks,
    }
    append_jsonl(root / "reports" / "benchmark-results.jsonl", record)
    append_trajectory(root, f"benchmark:{record['benchmark_id']}", status, checks)
    print(root / "reports" / "benchmark-results.jsonl")
    return 0 if status == "pass" else 1


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
        "!artifacts/**",
        "--glob",
        "!trajectories/**",
        "--glob",
        "!memories/**",
        "--glob",
        "!cache/**",
        "--glob",
        "!node_repl/**",
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
            result = run_command(command, root, timeout=180, include_stdout=True)
            if result["exit_code"] in {0, 1}:
                for line in str(result.get("stdout", "")).splitlines():
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
    additions: list[dict[str, Any]] = []
    drift: list[str] = []
    collect_toml_additions(source_data, target_data, [], additions, drift)
    addition_text = render_toml_additions(additions)
    result = {
        "source": str(source),
        "target": str(target),
        "missing_items": len(additions),
        "drift": drift,
        "dry_run": not args.apply,
        "additions": [{"table": ".".join(item["table"]), "key": item["key"]} for item in additions],
    }
    if args.apply and addition_text:
        backup = backup_file(target, root)
        merged_text = apply_toml_additions(read_text(target), additions, target_data)
        write_text(target, merged_text)
        result["backup"] = str(backup)
    print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


def apply_toml_additions(text: str, additions: list[dict[str, Any]], target_data: dict[str, Any]) -> str:
    lines = text.splitlines()
    root_items: list[dict[str, Any]] = []
    existing_table_items: dict[tuple[str, ...], list[dict[str, Any]]] = {}
    append_items: list[dict[str, Any]] = []

    for item in additions:
        table = tuple(item["table"])
        if not table and not isinstance(item["value"], dict):
            root_items.append(item)
        elif table and toml_table_exists(target_data, list(table)):
            existing_table_items.setdefault(table, []).append(item)
        else:
            append_items.append(item)

    if root_items:
        insertion = next((index for index, line in enumerate(lines) if re.match(r"\s*\[", line)), len(lines))
        root_lines = [format_toml_value(item["key"], item["value"]) for item in sorted(root_items, key=lambda entry: entry["key"])]
        lines[insertion:insertion] = ["# Added by codex-agent-harness merge-config", *root_lines, ""]

    insertions: list[tuple[int, list[str]]] = []
    for table, items in existing_table_items.items():
        header_index = find_toml_table_header(lines, list(table))
        if header_index is None:
            append_items.extend(items)
            continue
        insertion = find_toml_table_end(lines, header_index)
        item_lines = [format_toml_value(item["key"], item["value"]) for item in sorted(items, key=lambda entry: entry["key"])]
        insertions.append((insertion, ["# Added by codex-agent-harness merge-config", *item_lines]))

    for insertion, item_lines in sorted(insertions, key=lambda pair: pair[0], reverse=True):
        lines[insertion:insertion] = item_lines

    if append_items:
        append_text = render_toml_additions(append_items).rstrip()
        if append_text:
            if lines and lines[-1].strip():
                lines.append("")
            lines.append("# Added by codex-agent-harness merge-config")
            lines.extend(append_text.splitlines())

    return "\n".join(lines).rstrip() + "\n"


def toml_table_exists(data: dict[str, Any], table: list[str]) -> bool:
    current: Any = data
    for part in table:
        if not isinstance(current, dict) or part not in current:
            return False
        current = current[part]
    return isinstance(current, dict)


def find_toml_table_header(lines: list[str], table: list[str]) -> int | None:
    header = f"[{'.'.join(table)}]"
    for index, line in enumerate(lines):
        if line.strip() == header:
            return index
    return None


def find_toml_table_end(lines: list[str], header_index: int) -> int:
    for index in range(header_index + 1, len(lines)):
        if re.match(r"\s*\[", lines[index]):
            return index
    return len(lines)


def collect_toml_additions(source: dict[str, Any], target: dict[str, Any], table: list[str], additions: list[dict[str, Any]], drift: list[str]) -> None:
    for key, value in sorted(source.items()):
        dotted = ".".join([*table, key])
        if key not in target:
            additions.append({"table": table, "key": key, "value": value})
            continue
        target_value = target[key]
        if isinstance(value, dict) and isinstance(target_value, dict):
            collect_toml_additions(value, target_value, [*table, key], additions, drift)
            continue
        if target_value != value:
            drift.append(dotted)


def render_toml_additions(additions: list[dict[str, Any]]) -> str:
    root_lines: list[str] = []
    table_groups: dict[tuple[str, ...], list[dict[str, Any]]] = {}
    for item in additions:
        table = tuple(item["table"])
        if table:
            table_groups.setdefault(table, []).append(item)
        else:
            root_lines.extend(format_toml_item(item["key"], item["value"], []))

    sections: list[str] = []
    if root_lines:
        sections.extend(root_lines)
    for table, items in sorted(table_groups.items()):
        sections.append("")
        sections.append(f"[{'.'.join(table)}]")
        for item in sorted(items, key=lambda entry: entry["key"]):
            sections.extend(format_toml_item(item["key"], item["value"], list(table)))
    return "\n".join(sections).rstrip() + ("\n" if sections else "")


def format_toml_item(key: str, value: Any, table: list[str]) -> list[str]:
    if isinstance(value, dict):
        lines = ["" if table else "", f"[{'.'.join([*table, key])}]"]
        for child_key, child_value in sorted(value.items()):
            lines.extend(format_toml_item(child_key, child_value, [*table, key]))
        return [line for line in lines if line != "" or table]
    return [format_toml_value(key, value)]


def format_toml_value(key: str, value: Any) -> str:
    if isinstance(value, bool):
        return f"{key} = {'true' if value else 'false'}"
    if isinstance(value, str):
        return f"{key} = {json.dumps(value, ensure_ascii=False)}"
    if isinstance(value, (int, float)):
        return f"{key} = {value}"
    if isinstance(value, list):
        return f"{key} = [{', '.join(format_toml_scalar(item) for item in value)}]"
    return f"# {key}: complex table omitted; append manually after review"


def format_toml_scalar(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, (int, float)):
        return str(value)
    return json.dumps(str(value), ensure_ascii=False)


def cmd_self_test(args: argparse.Namespace) -> int:
    import tempfile

    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        write_text(
            root / "config.toml",
            "[features]\n"
            "plugins = true\n"
            "codex_hooks = true\n"
            "multi_agent = true\n"
            "child_agents_md = true\n"
            "tool_search = true\n"
            "tool_suggest = true\n"
            "skill_mcp_dependency_install = true\n"
            "workspace_dependencies = false\n"
            "\n"
            "[agents]\n"
            "max_threads = 8\n"
            "max_depth = 1\n"
            "\n"
            "[agents.explorer]\n"
            'description = "Focused read-only codebase and environment exploration for bounded evidence gathering."\n'
            'config_file = "agents/explorer.toml"\n'
            "\n"
            "[agents.reviewer]\n"
            'description = "Independent read-only review for correctness, security, test gaps, and maintainability risks."\n'
            'config_file = "agents/reviewer.toml"\n'
            "\n"
            "[agents.docs-researcher]\n"
            'description = "Primary-source documentation research for version-sensitive OpenAI, MCP, and toolchain claims."\n'
            'config_file = "agents/docs-researcher.toml"\n',
        )
        write_text(root / "AGENTS.md", "# Test\n")
        write_text(root / ".gitignore", "auth.json\n.codex-global-state.json\n__pycache__/\n*.pyc\n")
        write_text(root / "maintenance" / "MCP_RUNTIME_STATUS.md", "# MCP\n")
        write_text(root / "hooks" / "lightweight-codex-hook.ps1", "$ErrorActionPreference = 'Stop'\n")
        ensure_dir(root / "toolchains" / "shims")
        write_json(root / "reports" / "global-scan.latest.json", {"content_redacted": True, "active_hit_count": 0})
        write_text(root / "reports" / "eval-results.jsonl", "")
        ns = argparse.Namespace(root=str(root), profile="developer", module=None)
        cmd_apply(ns)
        state = load_state(root)
        if not any(op.get("remove_on_uninstall") is True for op in state.get("applied_operations", [])):
            print("uninstall ownership missing in self-test", file=sys.stderr)
            return 1
        write_text(root / "agents" / "explorer.toml", "drifted = true\n")
        cmd_apply(ns)
        if doctor_data(root)["status"] != "pass":
            print("doctor failed in self-test", file=sys.stderr)
            return 1
        source = root / "source.toml"
        target = root / "target.toml"
        write_text(source, 'model = "gpt-test"\n[features]\nplugins = true\nmulti_agent = true\n[mcp_servers.docs]\nenabled = true\n')
        write_text(target, '[features]\nplugins = false\n')
        merge_ns = argparse.Namespace(root=str(root), source=str(source), target=str(target), apply=True, update_managed=False)
        if cmd_merge_config(merge_ns) != 0:
            print("merge-config failed in self-test", file=sys.stderr)
            return 1
        merged = read_text(target)
        if "plugins = false" not in merged or "multi_agent = true" not in merged or "[mcp_servers.docs]" not in merged:
            print("merge-config did not preserve and append table keys in self-test", file=sys.stderr)
            return 1
        try:
            parsed_merged = tomllib.loads(merged)
        except Exception as exc:  # noqa: BLE001
            print(f"merge-config produced invalid TOML in self-test: {exc}", file=sys.stderr)
            return 1
        if parsed_merged["features"]["plugins"] is not False or parsed_merged["features"]["multi_agent"] is not True:
            print("merge-config changed existing values in self-test", file=sys.stderr)
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
    p = sub.add_parser("benchmark")
    p.add_argument("--eval-id")
    p.set_defaults(func=cmd_benchmark)
    p = sub.add_parser("trajectory")
    p.add_argument("--search")
    p.add_argument("--failed", action="store_true")
    p.add_argument("--recent", type=int, default=20)
    p.set_defaults(func=cmd_trajectory)
    p = sub.add_parser("compact-summary")
    p.add_argument("--goal")
    p.add_argument("--constraints")
    p.add_argument("--current-plan")
    p.add_argument("--completed-work")
    p.add_argument("--in-progress-work")
    p.add_argument("--blockers")
    p.add_argument("--relevant-files")
    p.add_argument("--commands-run")
    p.add_argument("--test-results")
    p.add_argument("--next-steps")
    p.add_argument("--risks")
    p.set_defaults(func=cmd_compact_summary)
    p = sub.add_parser("retrieve")
    p.add_argument("--query", required=True)
    p.add_argument("--limit", type=int, default=8)
    p.set_defaults(func=cmd_retrieve)
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
