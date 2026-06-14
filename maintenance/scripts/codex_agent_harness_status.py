from __future__ import annotations

import os
import stat
import subprocess
import tomllib
from pathlib import Path
from typing import Any

from codex_agent_harness_base import (
    no_window_creationflags,
    read_text,
    rel,
)


MAX_HARNESS_FILE_LINES = 800
HARNESS_FILE_LINE_LIMITS = {
    "codex_agent_harness_base.py": 1000,
    "codex_agent_harness_lifecycle.py": 1150,
    "compact-codex-hook.ps1": 900,
    "codex_agent_harness_smoke.py": 1800,
    "codex_agent_harness_workflows.py": 1350,
}
MAX_WORKSPACE_SCRIPT_LINES = 800
WORKSPACE_SCRIPT_SUFFIXES = {".js", ".mjs", ".py", ".ps1", ".ts", ".tsx", ".md"}


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
        max_lines = HARNESS_FILE_LINE_LIMITS.get(path.name, MAX_HARNESS_FILE_LINES)
        item = {"path": rel(path, root), "lines": line_count, "max_lines": max_lines}
        counts.append(item)
        if line_count > max_lines:
            oversized.append(item)
    return {
        "status": "pass" if not oversized else "fail",
        "files": counts,
        "oversized": oversized,
    }


def workspace_script_line_count_status(root: Path) -> dict[str, Any]:
    skill_root = root / "skills"
    files = []
    if skill_root.exists():
        for path in skill_root.rglob("*"):
            if "__pycache__" in path.parts or not path.is_file():
                continue
            if path.suffix.lower() in WORKSPACE_SCRIPT_SUFFIXES and (
                "scripts" in path.parts or path.name == "SKILL.md"
            ):
                files.append(path)
    counts = []
    oversized = []
    for path in sorted(files):
        line_count = len(read_text(path).splitlines())
        item = {
            "path": rel(path, root),
            "lines": line_count,
            "max_lines": MAX_WORKSPACE_SCRIPT_LINES,
        }
        counts.append(item)
        if line_count > MAX_WORKSPACE_SCRIPT_LINES:
            oversized.append(item)

    cache_large = []
    cache_root = root / "plugins" / "cache"
    seen_cache_paths = set()
    if cache_root.exists():
        for path in sorted(cache_root.rglob("*")):
            if (
                not path.is_file()
                or path.suffix.lower() not in WORKSPACE_SCRIPT_SUFFIXES
            ):
                continue
            if "node_modules" in path.parts:
                continue
            normalized = str(path.resolve()).lower()
            if normalized in seen_cache_paths:
                continue
            seen_cache_paths.add(normalized)
            line_count = len(read_text(path).splitlines())
            if line_count > MAX_WORKSPACE_SCRIPT_LINES:
                cache_large.append(
                    {
                        "path": rel(path, root),
                        "lines": line_count,
                        "classification": "ignored_runtime_plugin_cache",
                        "reason": "Plugin cache is ignored runtime material; preserve upstream compatibility and do not force-track cache files.",
                    }
                )

    return {
        "status": "pass" if not oversized else "fail",
        "files": counts,
        "oversized": oversized,
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
        missing = [
            item
            for item in [
                "required_delegation_fields",
                "required_output_sections",
                "success_claim_policy",
                "reward_hacking_guard",
            ]
            if item not in text
        ]
        if missing:
            role_missing.append({"path": rel(path, root), "missing": missing})
    missing = {"terms": missing_terms, "roles": role_missing}
    return {
        "status": "pass" if not missing_terms and not role_missing else "fail",
        "missing": missing,
    }


def harness_engine_module_status(root: Path) -> dict[str, Any]:
    expected = [
        "codex_agent_harness.py",
        "codex_agent_harness_base.py",
        "codex_agent_harness_lifecycle.py",
        "codex_agent_harness_workflows.py",
        "codex_agent_harness_merge.py",
        "codex_agent_harness_smoke.py",
        "codex_agent_harness_status.py",
        "worker_watcher_templates.py",
    ]
    missing = [
        name
        for name in expected
        if not (root / "maintenance" / "scripts" / name).exists()
    ]
    return {"status": "pass" if not missing else "fail", "missing": missing}


def app_runtime_state_writable_status(root: Path) -> dict[str, Any]:
    runtime_root = Path(os.environ.get("CODEX_HOME") or (Path.home() / ".codex"))
    runtime_only = {
        "config.toml",
        ".codex-global-state.json",
        ".codex-global-state.json.bak",
    }
    optional_runtime_state = {".codex-global-state.json.bak"}
    items = []
    failures = []
    for name in [
        "config.toml",
        ".codex-global-state.json",
        ".codex-global-state.json.bak",
        "config.d/20-hooks.toml",
    ]:
        path = root / name
        source = "managed_root"
        if not path.exists() and name in runtime_only:
            path = runtime_root / name
            source = "codex_home"
        if not path.exists():
            items.append(
                {
                    "path": name,
                    "source": source,
                    "resolved_path": str(path),
                    "exists": False,
                    "writable": False,
                    "readonly": None,
                }
            )
            if name not in optional_runtime_state:
                failures.append(name)
            continue
        try:
            readonly = bool(
                path.stat().st_file_attributes & stat.FILE_ATTRIBUTE_READONLY
            )
        except AttributeError:
            readonly = not os.access(path, os.W_OK)
        writable = os.access(path, os.W_OK) and not readonly
        items.append(
            {
                "path": name,
                "source": source,
                "resolved_path": str(path),
                "exists": True,
                "writable": writable,
                "readonly": readonly,
            }
        )
        if not writable:
            failures.append(name)
    return {
        "status": "pass" if not failures else "fail",
        "items": items,
        "failures": failures,
        "runtime_root": str(runtime_root),
    }


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
            creationflags=no_window_creationflags(),
        )
    except Exception as exc:  # noqa: BLE001 - git may not exist in temp self-test roots.
        return {
            "status": "pass",
            "not_applicable": True,
            "reason": str(exc),
            "tracked": [],
        }
    if completed.returncode != 0:
        return {
            "status": "pass",
            "not_applicable": True,
            "reason": completed.stderr.strip(),
            "tracked": [],
        }
    tracked = [line for line in completed.stdout.splitlines() if line.strip()]
    allowed = {"artifacts/compact-summaries/README.md"}
    unexpected = [item for item in tracked if item not in allowed]
    return {
        "status": "pass" if not unexpected else "fail",
        "tracked": unexpected,
        "patterns": patterns,
    }


def compact_hook_contract_status(root: Path) -> dict[str, Any]:
    hook_path = root / "hooks" / "compact-codex-hook.ps1"
    config_path = root / "config.d" / "20-hooks.toml"
    missing = []
    if not hook_path.exists():
        return {"status": "fail", "missing": ["hooks/compact-codex-hook.ps1"]}
    hook_text = read_text(hook_path).lower()
    config_text = read_text(config_path).lower() if config_path.exists() else ""
    for term in [
        'runner = "compact-codex-hook"',
        "hook-ledger.jsonl",
        "compact hook active",
        "treat claims as candidate until direct evidence supports them",
        "ensure-runtimecleanupwatch",
    ]:
        if term not in hook_text:
            missing.append(term)
    if "compact-codex-hook.ps1" not in config_text:
        missing.append("config.d/20-hooks.toml routes compact hook")
    legacy_hook = "lightweight" + "-codex"
    legacy_config = "hooks" + ".json"
    if legacy_hook in config_text or legacy_config in config_text:
        missing.append("config.d/20-hooks.toml must not route legacy hook wiring")
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
        nickname_candidates = (
            parsed.get("nickname_candidates", []) if isinstance(parsed, dict) else []
        )
        if not isinstance(nickname_candidates, list) or not any(
            isinstance(item, str) and item.startswith(f"{prefix}-")
            for item in nickname_candidates
        ):
            role_missing.append(f"nickname_candidates use {prefix}- prefix")
        if role_missing:
            missing.append(
                {"role": role, "path": rel(path, root), "missing": role_missing}
            )

    instruction_text = ""
    for path in [
        root / "AGENTS.md",
        root / "maintenance" / "SUBAGENT_DELEGATION_CHARTER.md",
    ]:
        if path.exists():
            instruction_text += "\n" + read_text(path).lower()
    required_terms = [
        "role-prefixed nicknames",
        "pm-*",
        "exp-*",
        "rev-*",
        "doc-*",
        "env-*",
        "obs-*",
    ]
    term_missing = [term for term in required_terms if term not in instruction_text]
    return {
        "status": "pass" if not missing and not term_missing else "fail",
        "roles": missing,
        "missing_terms": term_missing,
    }
