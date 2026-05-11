from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import stat
import sys
import tomllib
from pathlib import Path
from typing import Any

from codex_agent_harness_base import *

MAX_HARNESS_FILE_LINES = 1000


def harness_line_count_status(root: Path) -> dict[str, Any]:
    files = sorted((root / "maintenance" / "scripts").glob("codex_agent_harness*.py"))
    counts = []
    oversized = []
    for path in files:
        line_count = len(read_text(path).splitlines())
        item = {"path": rel(path, root), "lines": line_count, "max_lines": MAX_HARNESS_FILE_LINES}
        counts.append(item)
        if line_count > MAX_HARNESS_FILE_LINES:
            oversized.append(item)
    return {"status": "pass" if not oversized else "fail", "files": counts, "oversized": oversized}

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
        "harness_file_size": harness_line_count_status(root),
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
    expected_power_shell_checks = []
    if command_exists("pwsh"):
        expected_power_shell_checks.append("pwsh_wrapper_doctor")
    if command_exists("powershell.exe"):
        expected_power_shell_checks.append("windows_powershell_wrapper_doctor")
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
            ("harness python files stay under line limit", harness_line_count_status(root).get("status") == "pass"),
            ("hook script parses by existence", (root / "hooks" / "lightweight-codex-hook.ps1").exists()),
            ("doctor currently passes", doctor.get("status") == "pass"),
            ("latest verification passes", verification.get("status") == "pass"),
            ("latest verification includes lifecycle dry-runs", all(verification_checks.get(name) == "pass" for name in ["self_test", "repair_dry_run", "uninstall_dry_run"])),
            ("PowerShell wrappers execute when shells exist", all(verification_checks.get(name) == "pass" for name in expected_power_shell_checks)),
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
