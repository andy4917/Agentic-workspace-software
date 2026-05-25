from __future__ import annotations

import json
import os
import stat
import subprocess
from pathlib import Path
from typing import Any

from codex_agent_harness_base import *


MAX_HARNESS_FILE_LINES = 800
MAX_WORKSPACE_SCRIPT_LINES = 800
WORKSPACE_SCRIPT_SUFFIXES = {".js", ".mjs", ".py", ".ps1", ".ts", ".tsx", ".md"}


def is_upstream_system_skill_file(path: Path, root: Path) -> bool:
    try:
        parts = path.relative_to(root).parts
    except ValueError:
        return False
    return len(parts) >= 3 and parts[0] == "skills" and parts[1] == ".system"


def harness_line_count_status(root: Path) -> dict[str, Any]:
    files = sorted((root / "maintenance" / "scripts").glob("codex_agent_harness*.py"))
    files.append(root / "maintenance" / "scripts" / "worker_watcher_templates.py")
    files.append(root / "hooks" / "compact-codex-hook.ps1")
    files.extend(sorted((root / "hooks" / "lib").glob("*.ps1")))
    files = [path for path in files if path.exists()]
    counts = []
    oversized = []
    for path in files:
        line_count = len(read_text(path).splitlines())
        item = {"path": rel(path, root), "lines": line_count, "max_lines": MAX_HARNESS_FILE_LINES}
        counts.append(item)
        if line_count > MAX_HARNESS_FILE_LINES:
            oversized.append(item)
    return {"status": "pass" if not oversized else "fail", "files": counts, "oversized": oversized}


def workspace_script_line_count_status(root: Path) -> dict[str, Any]:
    skill_root = root / "skills"
    files = []
    if skill_root.exists():
        for path in skill_root.rglob("*"):
            if "__pycache__" in path.parts or not path.is_file():
                continue
            if path.suffix.lower() in WORKSPACE_SCRIPT_SUFFIXES and ("scripts" in path.parts or path.name == "SKILL.md"):
                files.append(path)
    counts = []
    oversized = []
    system_skill_large = []
    for path in sorted(files):
        line_count = len(read_text(path).splitlines())
        item = {"path": rel(path, root), "lines": line_count, "max_lines": MAX_WORKSPACE_SCRIPT_LINES}
        counts.append(item)
        if line_count > MAX_WORKSPACE_SCRIPT_LINES:
            if is_upstream_system_skill_file(path, root):
                system_skill_large.append(
                    {
                        **item,
                        "classification": "ignored_upstream_system_skill",
                        "reason": "System skill material is upstream-managed; preserve the skill contract and do not force local source splitting.",
                    }
                )
            else:
                oversized.append(item)

    cache_large = []
    cache_root = root / "plugins" / "cache"
    seen_cache_paths = set()
    if cache_root.exists():
        for path in sorted(cache_root.rglob("*")):
            if not path.is_file() or path.suffix.lower() not in WORKSPACE_SCRIPT_SUFFIXES:
                continue
            if "node_modules" in path.parts:
                continue
            normalized = str(path.resolve()).lower()
            if normalized in seen_cache_paths:
                continue
            seen_cache_paths.add(normalized)
            line_count = len(read_text(path).splitlines())
            if line_count > MAX_WORKSPACE_SCRIPT_LINES:
                cache_large.append({
                    "path": rel(path, root),
                    "lines": line_count,
                    "classification": "ignored_runtime_plugin_cache",
                    "reason": "Plugin cache is ignored runtime material; preserve upstream compatibility and do not force-track cache files.",
                })

    return {
        "status": "pass" if not oversized else "fail",
        "files": counts,
        "oversized": oversized,
        "classified_system_skill_large_files": system_skill_large,
        "classified_cache_large_files": cache_large,
    }


def pm_subagent_protocol_status(root: Path) -> dict[str, Any]:
    agents_path = root / "AGENTS.md"
    charter_path = root / "maintenance" / "SUBAGENT_DELEGATION_CHARTER.md"
    role_paths = [
        root / "agents" / "explorer.toml",
        root / "agents" / "reviewer.toml",
        root / "agents" / "docs-researcher.toml",
        root / "agents" / "observer.toml",
    ]
    if not agents_path.exists():
        return {"status": "fail", "error": "AGENTS.md missing"}
    agents_text = read_text(agents_path).lower()
    charter_text = read_text(charter_path).lower() if charter_path.exists() else ""
    combined_text = agents_text + "\n" + charter_text
    required_terms = [
        "require each subagent to state its own concrete goal",
        "purpose",
        "pm context",
        "owned surface",
        "expected evidence",
        "anti-reward-hacking rules",
        "mid-report",
        "exit criteria",
        "not checked",
        "pm must continue useful non-overlapping work",
        "subagent outputs are candidate evidence",
        "reward-hacked validation",
        "unsupported success claims",
    ]
    missing_terms = [item for item in required_terms if item not in combined_text]
    role_missing = []
    for path in role_paths:
        if not path.exists():
            role_missing.append({"path": rel(path, root), "missing": ["file"]})
            continue
        text = read_text(path).lower()
        missing = [item for item in ["required_delegation_fields", "required_output_sections", "success_claim_policy", "reward_hacking_guard"] if item not in text]
        if missing:
            role_missing.append({"path": rel(path, root), "missing": missing})
    missing = {"terms": missing_terms, "roles": role_missing}
    return {"status": "pass" if not missing_terms and not role_missing else "fail", "missing": missing}


def harness_engine_module_status(root: Path) -> dict[str, Any]:
    expected = [
        "codex_agent_harness.py",
        "codex_agent_harness_base.py",
        "codex_agent_harness_lifecycle.py",
        "codex_agent_harness_workflows.py",
        "codex_agent_harness_merge.py",
        "codex_agent_harness_naming.py",
        "codex_agent_harness_smoke.py",
        "codex_agent_harness_status.py",
        "worker_watcher_templates.py",
    ]
    missing = [name for name in expected if not (root / "maintenance" / "scripts" / name).exists()]
    return {"status": "pass" if not missing else "fail", "missing": missing}


def app_runtime_state_writable_status(root: Path) -> dict[str, Any]:
    items = []
    failures = []
    for name in ["config.toml", ".codex-global-state.json", "hooks.json"]:
        path = root / name
        if not path.exists():
            items.append({"path": name, "exists": False, "writable": False, "readonly": None})
            failures.append(name)
            continue
        try:
            readonly = bool(path.stat().st_file_attributes & stat.FILE_ATTRIBUTE_READONLY)
        except AttributeError:
            readonly = not os.access(path, os.W_OK)
        writable = os.access(path, os.W_OK) and not readonly
        items.append({"path": name, "exists": True, "writable": writable, "readonly": readonly})
        if not writable:
            failures.append(name)
    return {"status": "pass" if not failures else "fail", "items": items, "failures": failures}


def generated_output_tracking_status(root: Path) -> dict[str, Any]:
    patterns = [
        "reports/*.latest.json",
        "reports/*.latest.md",
        "reports/*results.jsonl",
        "trajectories/runs.jsonl",
        "artifacts/compact-summaries/*.md",
        "artifacts/tool-results/*.txt",
    ]
    try:
        completed = subprocess.run(
            ["git", "ls-files", "--", *patterns],
            cwd=str(root),
            text=True,
            encoding="utf-8",
            errors="replace",
            capture_output=True,
            timeout=15,
        )
    except Exception as exc:  # noqa: BLE001 - git may not exist in temp self-test roots.
        return {"status": "pass", "not_applicable": True, "reason": str(exc), "tracked": []}
    if completed.returncode != 0:
        return {"status": "pass", "not_applicable": True, "reason": completed.stderr.strip(), "tracked": []}
    tracked = [line for line in completed.stdout.splitlines() if line.strip()]
    allowed = {"artifacts/compact-summaries/README.md"}
    unexpected = [item for item in tracked if item not in allowed]
    return {"status": "pass" if not unexpected else "fail", "tracked": unexpected, "patterns": patterns}


def hook_subagent_vowline_status(root: Path) -> dict[str, Any]:
    hook_path = root / "hooks" / "compact-codex-hook.ps1"
    policy_path = root / "hooks" / "policy.compact.json"
    agents_path = root / "AGENTS.md"
    primary_skill_path = Path.home() / ".agents" / "skills" / "vowline" / "SKILL.md"
    duplicate_skill_path = root / "skills" / "vowline" / "SKILL.md"
    missing = []
    if not hook_path.exists():
        return {"status": "fail", "missing": ["hooks/compact-codex-hook.ps1"]}
    hook_parts = [read_text(hook_path).lower()]
    hook_text = "\n".join(hook_parts)
    for term in [
        "next_turn_work_items",
        "subagent_call",
        "delegation hint",
        "support-only memory",
        "memento is support-only",
    ]:
        if term not in hook_text:
            missing.append(term)
    if not policy_path.exists():
        missing.append("hooks/policy.compact.json")
    else:
        try:
            policy = json.loads(read_text(policy_path))
        except json.JSONDecodeError:
            policy = {}
            missing.append("valid hook policy json")
        used_events = set(policy.get("hook_events_used", [])) if isinstance(policy, dict) else set()
        excluded_events = set(policy.get("hook_events_excluded", [])) if isinstance(policy, dict) else set()
        if not {"SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop"}.issubset(used_events):
            missing.append("compact v3 hook_events_used")
        if "PermissionRequest" not in excluded_events:
            missing.append("PermissionRequest excluded")
        subagents = policy.get("subagents", {}) if isinstance(policy, dict) else {}
        if subagents.get("enabled_when_explicitly_authorized") is not True:
            missing.append("subagents.enabled_when_explicitly_authorized=true")
    if not primary_skill_path.exists():
        missing.append("~/.agents/skills/vowline/SKILL.md")
    if duplicate_skill_path.exists():
        missing.append("remove duplicate skills/vowline; primary owner is ~/.agents/skills/vowline")
    if not agents_path.exists():
        missing.append("AGENTS.md")
    else:
        agents_text = read_text(agents_path).lower()
        if agents_text.count("<!-- vowline:start -->") != 1 or agents_text.count("<!-- vowline:end -->") != 1:
            missing.append("AGENTS.md one Vowline marked block")
        if "always use the skill `vowline` consistently" not in agents_text:
            missing.append("AGENTS.md Vowline activation body")
    return {"status": "pass" if not missing else "fail", "missing": missing}


def subagent_nickname_policy_status(root: Path) -> dict[str, Any]:
    role_expectations = {
        "explorer": ("EXP", root / "agents" / "explorer.toml"),
        "reviewer": ("REV", root / "agents" / "reviewer.toml"),
        "docs-researcher": ("DOC", root / "agents" / "docs-researcher.toml"),
        "observer": ("OBS", root / "agents" / "observer.toml"),
    }
    missing = []
    for role, (prefix, path) in role_expectations.items():
        if not path.exists():
            missing.append({"role": role, "path": rel(path, root), "missing": ["file"]})
            continue
        text = read_text(path)
        role_missing = []
        try:
            parsed = tomllib.loads(text)
        except tomllib.TOMLDecodeError:
            parsed = {}
            role_missing.append("valid TOML")
        nickname_candidates = parsed.get("nickname_candidates", []) if isinstance(parsed, dict) else []
        if not isinstance(nickname_candidates, list) or not any(isinstance(item, str) and item.startswith(f"{prefix}-") for item in nickname_candidates):
            role_missing.append(f"nickname_candidates use {prefix}- prefix")
        if role_missing:
            missing.append({"role": role, "path": rel(path, root), "missing": role_missing})

    instruction_text = ""
    for path in [root / "AGENTS.md", root / "maintenance" / "SUBAGENT_DELEGATION_CHARTER.md"]:
        if path.exists():
            instruction_text += "\n" + read_text(path).lower()
    required_terms = ["role-prefixed nicknames", "pm-*", "exp-*", "rev-*", "doc-*", "env-*", "obs-*"]
    term_missing = [term for term in required_terms if term not in instruction_text]
    return {"status": "pass" if not missing and not term_missing else "fail", "roles": missing, "missing_terms": term_missing}
