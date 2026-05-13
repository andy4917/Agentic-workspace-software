from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
import sys
from pathlib import Path
from typing import Any

from codex_agent_harness_base import *
from codex_agent_harness_lifecycle import audit_data, check_config, check_managed_files, doctor_data, load_trajectory_records, trajectory_records_valid


def load_eval_definition(root: Path, eval_id: str) -> tuple[dict[str, Any], list[str]]:
    path = root / "evals" / f"{eval_id}.json"
    errors = []
    if not path.exists():
        return {}, [f"missing eval definition: {eval_id}"]
    try:
        data = json.loads(read_text(path))
    except json.JSONDecodeError as exc:
        return {}, [f"invalid eval definition JSON: {exc}"]
    for key in ["eval_id", "grader", "success_criteria", "task", "timeout_seconds"]:
        if key not in data:
            errors.append(f"missing {key}")
    if data.get("eval_id") != eval_id:
        errors.append("eval_id mismatch")
    if not isinstance(data.get("success_criteria"), list) or not data.get("success_criteria"):
        errors.append("success_criteria must be a non-empty list")
    if not isinstance(data.get("grader"), str) or not data.get("grader"):
        errors.append("grader must be a non-empty string")
    return data, errors

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
    checks.append(
        {
            "name": "python_compile",
            **run_command(
                [
                    sys.executable,
                    "-m",
                    "py_compile",
                    "maintenance/scripts/codex_agent_harness.py",
                    "maintenance/scripts/codex_agent_harness_base.py",
                    "maintenance/scripts/codex_agent_harness_lifecycle.py",
                    "maintenance/scripts/codex_agent_harness_merge.py",
                    "maintenance/scripts/codex_agent_harness_workflows.py",
                    "maintenance/scripts/worker_watcher_templates.py",
                ],
                root,
            ),
        }
    )
    checks.append({"name": "self_test", **run_command([sys.executable, "maintenance/scripts/codex_agent_harness.py", "self-test"], root)})
    checks.append({"name": "repair_dry_run", **run_command([sys.executable, "maintenance/scripts/codex_agent_harness.py", "repair"], root)})
    checks.append({"name": "uninstall_dry_run", **run_command([sys.executable, "maintenance/scripts/codex_agent_harness.py", "uninstall"], root)})
    checks.append(
        {
            "name": "rg_resolution_smoke",
            **run_command(
                [
                    "powershell.exe",
                    "-NoProfile",
                    "-ExecutionPolicy",
                    "Bypass",
                    "-File",
                    "maintenance/scripts/check-rg-resolution.ps1",
                ],
                root,
            ),
        }
    )
    if command_exists("pwsh"):
        checks.append(
            {
                "name": "pwsh_wrapper_doctor",
                **run_command(["pwsh", "-NoProfile", "-File", "maintenance/scripts/codex-harness-doctor.ps1", "--json"], root),
            }
        )
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
    if command_exists("powershell.exe"):
        checks.append(
            {
                "name": "windows_powershell_wrapper_doctor",
                **run_command(["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "maintenance/scripts/codex-harness-doctor.ps1", "--json"], root),
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
    report.setdefault("harness_digest", harness_source_digest(root))
    report.setdefault("repository", current_git_state(root))
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
        definition, definition_errors = load_eval_definition(root, eval_id)
        if definition_errors:
            passed = False
        elif eval_id == "config-parse":
            passed = check_config(root).get("status") == "pass"
        elif eval_id == "managed-files":
            passed = check_managed_files(root).get("status") == "pass"
        elif eval_id == "audit-threshold":
            passed = audit_data(root).get("status") == "pass"
        elif eval_id == "context-inspection":
            context_ns = argparse.Namespace(root=str(root))
            report = root / "reports" / "context-inspection.latest.json"
            passed = cmd_context(context_ns) == 0 and bool(load_json(report, {}).get("selected_primary_instruction_source"))
        elif eval_id == "trajectory-search":
            records = load_trajectory_records(root)
            trajectory_ns = argparse.Namespace(root=str(root), search=None, failed=False, recent=5)
            passed = bool(records) and trajectory_records_valid(records) and cmd_trajectory(trajectory_ns) == 0
        elif eval_id == "orchestration-governance-smoke":
            passed = check_orchestration_governance_smoke(root).get("status") == "pass"
        elif eval_id == "dont-even-try-integration-smoke":
            passed = check_dont_even_try_integration_smoke(root).get("status") == "pass"
        elif eval_id == "worker-watcher-normalized-handoff-smoke":
            passed = check_worker_watcher_normalized_handoff_smoke(root).get("status") == "pass"
        elif eval_id == "goal-integrity-gate-smoke":
            passed = check_goal_integrity_gate_smoke(root).get("status") == "pass"
        elif eval_id == "rg-resolution-smoke":
            passed = (
                run_command(
                    [
                        "powershell.exe",
                        "-NoProfile",
                        "-ExecutionPolicy",
                        "Bypass",
                        "-File",
                        "maintenance/scripts/check-rg-resolution.ps1",
                    ],
                    root,
                ).get("status")
                == "pass"
            )
        else:
            passed = False
        results.append(
            {
                "eval_id": eval_id,
                "status": "pass" if passed else "fail",
                "timestamp": utc_now(),
                "definition_digest": sha256_text(json.dumps(definition, ensure_ascii=False, sort_keys=True)) if definition else None,
                "definition_errors": definition_errors,
                "success_criteria_count": len(definition.get("success_criteria", [])) if isinstance(definition, dict) else 0,
            }
        )
    ensure_dir(root / "reports")
    result_path = root / "reports" / "eval-results.jsonl"
    with result_path.open("a", encoding="utf-8", newline="\n") as f:
        for item in results:
            f.write(json.dumps(item, ensure_ascii=False, sort_keys=True) + "\n")
    print(result_path)
    return 0 if all(item["status"] == "pass" for item in results) else 1


def check_orchestration_governance_smoke(root: Path) -> dict[str, Any]:
    checks: list[dict[str, Any]] = []

    def add_check(name: str, passed: bool, detail: str) -> None:
        checks.append({"name": name, "status": "pass" if passed else "fail", "detail": detail})

    agents_text = read_text(root / "AGENTS.md")
    charter_text = read_text(root / "maintenance" / "SUBAGENT_DELEGATION_CHARTER.md")
    audit_text = read_text(root / "codex-goals" / "_template" / "FINAL_GOAL_AUDIT.md")
    hook_text = read_text(root / "hooks" / "lightweight-codex-hook.ps1")

    add_check(
        "agents_goal_governance",
        all(term in agents_text for term in ["## Goal Governance", "tracking marker", "final goal audit", "Subagents receive contractual subgoals"]),
        "AGENTS.md should define parent-goal ownership and audit requirements.",
    )
    add_check(
        "subagent_authority_boundary",
        all(term in charter_text for term in ["## Authority Boundary", "evidence only", "cannot complete"]),
        "Delegation charter should prevent subagent parent-goal completion authority.",
    )
    add_check(
        "final_audit_template",
        all(term in audit_text for term in ["# FINAL_GOAL_AUDIT", "Direct Checks Not Run", "Residual Risks", "PM Independent Verification", "Decision"]),
        "Final audit template should require checked, not-run, risks, PM verification, and status.",
    )
    add_check(
        "stop_hook_audit_prompt",
        all(term in hook_text for term in ["function Test-FinalAuditReady", "function Get-ToolEvidenceSummary", "Final preflight", "checked items", "PM independent verification"]),
        "Stop hook should ask for an audit and keep hook evidence summaries compact.",
    )

    status = "pass" if all(item["status"] == "pass" for item in checks) else "fail"
    report = {"generated_at": utc_now(), "status": status, "checks": checks}
    write_json(root / "reports" / "orchestration-governance-smoke.latest.json", report)
    return report


def check_terms_file(root: Path, relative_path: str, terms: list[str]) -> tuple[bool, str]:
    path = root / relative_path
    if not path.exists():
        return False, f"missing file: {relative_path}"
    text = read_text(path).lower()
    missing = [term for term in terms if term.lower() not in text]
    if missing:
        return False, f"{relative_path} missing terms: {', '.join(missing)}"
    return True, f"{relative_path} contains required terms"


def write_smoke_report(root: Path, name: str, checks: list[dict[str, Any]]) -> dict[str, Any]:
    status = "pass" if all(item["status"] == "pass" for item in checks) else "fail"
    report = {"generated_at": utc_now(), "status": status, "checks": checks}
    write_json(root / "reports" / f"{name}.latest.json", report)
    return report


def check_dont_even_try_integration_smoke(root: Path) -> dict[str, Any]:
    checks: list[dict[str, Any]] = []

    def add_file_check(name: str, relative_path: str, terms: list[str]) -> None:
        passed, detail = check_terms_file(root, relative_path, terms)
        checks.append({"name": name, "status": "pass" if passed else "fail", "detail": detail})

    add_file_check(
        "skill_semantics",
        "skills/dont-even-try/SKILL.md",
        ["read-only", "immediately previous", "do not repair", "fix required", "clean", "unsupported success claims"],
    )
    add_file_check(
        "goal_gate_mapping",
        "maintenance/GOAL_INTEGRITY_GATE.md",
        ["clean", "c0", "p3", "c1", "p2", "c2", "p1", "c3", "p0", "c4", "clean is not completion authority", "immediately previous"],
    )
    add_file_check(
        "watcher_template_lens",
        "maintenance/templates/WATCHER_REPORT.md",
        ["dont-even-try verdict", "fix required", "clean", "defect classes checked", "pm merge recommendation"],
    )
    add_file_check(
        "pre_ship_template_lens",
        "maintenance/templates/PRE_SHIP_AUDIT_CONTEXT.md",
        ["immediately previous turn to review", "required review lens", "dont-even-try"],
    )
    return write_smoke_report(root, "dont-even-try-integration-smoke", checks)


def check_worker_watcher_normalized_handoff_smoke(root: Path) -> dict[str, Any]:
    checks: list[dict[str, Any]] = []

    def add_file_check(name: str, relative_path: str, terms: list[str]) -> None:
        passed, detail = check_terms_file(root, relative_path, terms)
        checks.append({"name": name, "status": "pass" if passed else "fail", "detail": detail})

    add_file_check(
        "handoff_policy",
        "maintenance/WORKER_WATCHER_NORMALIZED_HANDOFF.md",
        [
            "non-trivial worker dispatch requires at least one independent watcher",
            "raw worker output is not pm-ready until normalized",
            "watcher_not_used",
            "normalized_worker_packet",
            "pm_merge_decision",
            "worker complete is not pm complete",
            "watcher clean is not pm complete",
        ],
    )
    add_file_check(
        "result_normalizer_skill",
        "skills/result-normalizer/SKILL.md",
        ["claims rejected or unsupported", "commands not run", "do not upgrade", "completion authority"],
    )
    add_file_check(
        "observer_role",
        "agents/observer.toml",
        ["dont-even-try", "read-only", "do not repair", "watcher_report", "pm merge recommendation"],
    )
    for template in [
        "maintenance/templates/NORMALIZED_WORKER_PACKET.md",
        "maintenance/templates/WATCHER_REPORT.md",
        "maintenance/templates/WATCHER_NOT_USED.md",
        "maintenance/templates/PM_MERGE_DECISION.md",
    ]:
        add_file_check(f"template:{Path(template).stem}", template, ["# " + Path(template).stem.upper()])
    add_file_check(
        "delegation_charter_extension",
        "maintenance/SUBAGENT_DELEGATION_CHARTER.md",
        ["worker-watcher normalized handoff", "normalized_worker_packet", "watcher_not_used", "pm_merge_decision"],
    )
    return write_smoke_report(root, "worker-watcher-normalized-handoff-smoke", checks)


def check_goal_integrity_gate_smoke(root: Path) -> dict[str, Any]:
    checks: list[dict[str, Any]] = []

    def add_file_check(name: str, relative_path: str, terms: list[str]) -> None:
        passed, detail = check_terms_file(root, relative_path, terms)
        checks.append({"name": name, "status": "pass" if passed else "fail", "detail": detail})

    add_file_check(
        "gate_policy",
        "maintenance/GOAL_INTEGRITY_GATE.md",
        [
            "pm-only long-running work does not bypass midpoint audit",
            "midpoint gate",
            "pre-ship gate",
            "c2",
            "reset affected build or verify slice",
            "c3",
            "quarantine current result",
            "c4",
            "stop and request user approval",
        ],
    )
    add_file_check(
        "midpoint_context_template",
        "maintenance/templates/MIDPOINT_AUDIT_CONTEXT.md",
        ["immediately previous turn to review", "required review lens", "dont-even-try", "reset to define"],
    )
    add_file_check(
        "midpoint_decision_template",
        "maintenance/templates/MIDPOINT_GATE_DECISION.md",
        ["contamination score", "c0", "c1", "c2", "c3", "c4", "required reset stage"],
    )
    add_file_check(
        "pre_ship_decision_template",
        "maintenance/templates/PRE_SHIP_GATE_DECISION.md",
        ["completion eligible", "contamination score", "c0", "c1", "c2", "c3", "c4"],
    )
    add_file_check(
        "agents_policy",
        "AGENTS.md",
        ["midpoint and pre-ship", "c0-c4", "normalized worker packets", "watcher_not_used"],
    )
    return write_smoke_report(root, "goal-integrity-gate-smoke", checks)


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
    ordered_eval_ids = [eval_id for eval_id in eval_ids if eval_id != "audit-threshold"]
    if "audit-threshold" in eval_ids:
        ordered_eval_ids.append("audit-threshold")
    for eval_id in ordered_eval_ids:
        if eval_id == "audit-threshold" and checks:
            provisional_status = "pass" if all(item["status"] == "pass" for item in checks) else "fail"
            append_jsonl(
                root / "reports" / "benchmark-results.jsonl",
                {
                    "timestamp": utc_now(),
                    "benchmark_id": f"{args.eval_id or 'all'}:pre-audit",
                    "status": provisional_status,
                    "harness_digest": harness_source_digest(root),
                    "success_rate": round(sum(1 for item in checks if item["status"] == "pass") / len(checks), 4),
                    "pass_at_1": provisional_status == "pass",
                    "duration_seconds": (dt.datetime.now() - started).total_seconds(),
                    "tool_calls": len(checks),
                    "terminal_commands": len(checks),
                    "error_count": sum(1 for item in checks if item["status"] != "pass"),
                    "checks": checks,
                    "provisional_for": "audit-threshold",
                },
            )
        checks.append({"name": f"eval:{eval_id}", **run_command([sys.executable, "maintenance/scripts/codex_agent_harness.py", "eval", "--eval-id", eval_id], root, timeout=120)})
    status = "pass" if all(item["status"] == "pass" for item in checks) else "fail"
    record = {
        "timestamp": utc_now(),
        "benchmark_id": args.eval_id or "all",
        "status": status,
        "harness_digest": harness_source_digest(root),
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
        re.escape(str(user_home / "Documents" / "Codex" / "2026-05-09" / "Codex")).lower(),
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

    scan_errors = [match for match in matches if match["path"] in {"<scan-error>", "<not-run>"}]
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
        "harness_digest": harness_source_digest(root),
        "patterns": patterns,
        "match_count": len(matches),
        "active_hit_count": len(active_hits),
        "scan_error_count": len(scan_errors),
        "status": "pass" if not active_hits and not scan_errors else "fail",
        "active_hits": active_hits,
        "scan_errors": scan_errors,
        "matches_preview": matches[:200],
    }
    write_json(root / "reports" / "global-scan.latest.json", report)
    lines = [
        "# Global Development Environment Scan",
        "",
        f"- status: {report['status']}",
        f"- match_count: {report['match_count']}",
        f"- active_hit_count: {report['active_hit_count']}",
        f"- scan_error_count: {report['scan_error_count']}",
        f"- desktop_excluded: {report['desktop_excluded']}",
        "",
        "## Scan Roots",
    ]
    lines.extend(f"- {path}" for path in report["scan_roots"])
    lines.extend(["", "## Active Hits"])
    lines.extend(f"- {hit['path']}:{hit['line']} pattern={hit['pattern']}" for hit in active_hits or [])
    if not active_hits:
        lines.append("- None")
    lines.extend(["", "## Scan Errors"])
    lines.extend(f"- {hit['pattern']}: {hit.get('error', '')}" for hit in scan_errors or [])
    if not scan_errors:
        lines.append("- None")
    write_text(root / "reports" / "global-scan.latest.md", "\n".join(lines) + "\n")
    print(root / "reports" / "global-scan.latest.md")
    return 0 if report["status"] == "pass" else 1
