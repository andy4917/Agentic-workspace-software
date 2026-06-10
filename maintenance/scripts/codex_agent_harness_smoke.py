from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path
from typing import Any

from codex_agent_harness_base import *


def check_orchestration_governance_smoke(root: Path) -> dict[str, Any]:
    checks: list[dict[str, Any]] = []

    def add_check(name: str, passed: bool, detail: str) -> None:
        checks.append({"name": name, "status": "pass" if passed else "fail", "detail": detail})

    agents_text = read_text(root / "AGENTS.md")
    charter_text = read_text(root / "maintenance" / "SUBAGENT_DELEGATION_CHARTER.md")
    audit_text = read_text(root / "codex-goals" / "_template" / "FINAL_GOAL_AUDIT.md")
    hook_files = [root / "hooks" / "compact-codex-hook.ps1", root / "config.d" / "20-hooks.toml"]
    hook_text = "\n".join(read_text(path) for path in hook_files if path.exists())

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
        all(term in hook_text for term in ["compact-codex-hook", "hook-ledger.jsonl", "UserPromptSubmit", "PreToolUse"]),
        "Compact hook should record evidence and emit minimal prompt/tool context.",
    )

    status = "pass" if all(item["status"] == "pass" for item in checks) else "fail"
    report = {"generated_at": utc_now(), "status": status, "checks": checks}
    write_json(root / "reports" / "orchestration-governance-smoke.latest.json", report)
    return report


def run_compact_hook_sample(root: Path, payload: dict[str, Any]) -> dict[str, Any]:
    env = os.environ.copy()
    env["CODEX_HOOK_SMOKE"] = "1"
    pwsh = Path(os.environ.get("USERPROFILE", "")) / ".codex" / "toolchains" / "shims" / "pwsh.cmd"
    executable = str(pwsh) if pwsh.exists() else "pwsh"
    try:
        completed = subprocess.run(
            [executable, "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "hooks/compact-codex-hook.ps1"],
            cwd=root,
            env=env,
            input=json.dumps(payload),
            text=True,
            capture_output=True,
            timeout=30,
        )
        return {
            "status": "pass" if completed.returncode == 0 else "fail",
            "exit_code": completed.returncode,
            "stdout_preview": redact_obvious_secrets(completed.stdout[-COMMAND_PREVIEW_CHARS:]),
            "stderr_preview": redact_obvious_secrets(completed.stderr[-COMMAND_PREVIEW_CHARS:]),
        }
    except subprocess.TimeoutExpired as exc:
        return {"status": "fail", "exit_code": 124, "stdout_preview": "", "stderr_preview": str(exc)}


def run_hook_sample(root: Path, command: str) -> dict[str, Any]:
    return run_compact_hook_sample(
        root,
        {"hook_event_name": "PreToolUse", "tool_name": "functions.shell_command", "tool_input": {"command": command}},
    )


def run_prompt_hook_sample(root: Path, prompt: str) -> dict[str, Any]:
    return run_compact_hook_sample(
        root,
        {"hook_event_name": "UserPromptSubmit", "prompt": prompt, "cwd": str(root), "permission_mode": "default"},
    )


def run_post_tool_hook_sample(root: Path, tool_name: str, command: str) -> dict[str, Any]:
    return run_compact_hook_sample(
        root,
        {"hook_event_name": "PostToolUse", "tool_name": tool_name, "tool_input": {"command": command}},
    )


def run_subagent_session_start_sample(root: Path) -> dict[str, Any]:
    return run_compact_hook_sample(
        root,
        {
            "hook_event_name": "SessionStart",
            "agent_type": "reviewer",
            "parent_agent": "PM-main",
            "fork_context": True,
            "spawn_agent": {"agent_type": "reviewer"},
        },
    )


def run_stop_hook_sample(root: Path, message: str) -> dict[str, Any]:
    return run_compact_hook_sample(
        root,
        {"hook_event_name": "Stop", "last_assistant_message": message, "stop_hook_active": False},
    )


def check_hook_policy_smoke(root: Path) -> dict[str, Any]:
    checks: list[dict[str, Any]] = []
    ledger_path = root / "state" / "hook-ledger.jsonl"
    original_ledger_exists = ledger_path.exists()
    original_ledger_bytes = ledger_path.read_bytes() if original_ledger_exists else None

    def add_check(name: str, passed: bool, detail: str) -> None:
        checks.append({"name": name, "status": "pass" if passed else "fail", "detail": detail})

    try:
        config_text = read_text(root / "config.d" / "20-hooks.toml")
        hook_text = read_text(root / "hooks" / "compact-codex-hook.ps1")
        add_check(
            "hook_config_routes_compact_runner",
            "compact-codex-hook.ps1" in config_text
            and ("lightweight" + "-codex") not in config_text
            and ("hooks" + ".json") not in config_text,
            "Active hook fragment should route only to compact-codex-hook.ps1.",
        )
        add_check(
            "compact_hook_contains_current_contract",
            all(term in hook_text for term in ["runner = \"compact-codex-hook\"", "hook-ledger.jsonl", "UserPromptSubmit", "PreToolUse"]),
            "Compact hook should expose the current event contract and ledger.",
        )
        prompt_probe = run_prompt_hook_sample(root, "Compact hook smoke.")
        prompt_stdout = prompt_probe.get("stdout_preview", "").lower()
        add_check(
            "user_prompt_submit_emits_compact_context",
            prompt_probe.get("status") == "pass"
            and "compact hook active" in prompt_stdout
            and "treat claims as candidate" in prompt_stdout,
            "UserPromptSubmit should emit only the compact current-evidence reminder.",
        )
        session_probe = run_subagent_session_start_sample(root)
        session_stdout = session_probe.get("stdout_preview", "").lower()
        add_check(
            "session_start_emits_minimal_scaffold_context",
            session_probe.get("status") == "pass"
            and "minimal scaffold active" in session_stdout
            and "runtime cleanup watcher" in session_stdout,
            "SessionStart should emit the minimal scaffold reminder and keep cleanup watcher setup reachable.",
        )
        pre_probe = run_hook_sample(root, "Write-Output compact-hook-smoke")
        add_check(
            "pretooluse_allows_and_records",
            pre_probe.get("status") == "pass"
            and "permissiondecision" in pre_probe.get("stdout_preview", "").lower()
            and "allow" in pre_probe.get("stdout_preview", "").lower(),
            "PreToolUse should allow and record evidence only.",
        )
        post_probe = run_post_tool_hook_sample(root, "functions.shell_command", "Write-Output compact-hook-smoke")
        stop_probe = run_stop_hook_sample(root, "compact hook smoke final")
        add_check(
            "posttool_and_stop_are_record_only",
            post_probe.get("status") == "pass" and stop_probe.get("status") == "pass",
            "PostToolUse and Stop should not enforce old heavyweight policy gates.",
        )
    finally:
        if original_ledger_exists:
            ledger_path.parent.mkdir(parents=True, exist_ok=True)
            ledger_path.write_bytes(original_ledger_bytes or b"")
        else:
            try:
                ledger_path.unlink()
            except FileNotFoundError:
                pass

    restored_ledger_exists = ledger_path.exists()
    restored_ledger_bytes = ledger_path.read_bytes() if restored_ledger_exists else None
    add_check(
        "hook_policy_smoke_restores_live_ledger",
        restored_ledger_exists == original_ledger_exists and restored_ledger_bytes == original_ledger_bytes,
        "Synthetic compact hook samples must not leave ledger mutations behind.",
    )

    return write_smoke_report(root, "hook-policy-smoke", checks)


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


def check_adversarial_review_integration_smoke(root: Path) -> dict[str, Any]:
    checks: list[dict[str, Any]] = []

    def add_file_check(name: str, relative_path: str, terms: list[str]) -> None:
        passed, detail = check_terms_file(root, relative_path, terms)
        checks.append({"name": name, "status": "pass" if passed else "fail", "detail": detail})

    add_file_check(
        "skill_semantics",
        "skills/clean-all-slop/SKILL.md",
        ["audit mode", "read-only", "legacy residue", "unsupported success", "clean"],
    )
    add_file_check(
        "goal_gate_mapping",
        "maintenance/GOAL_INTEGRITY_GATE.md",
        ["clean", "c0", "p3", "c1", "p2", "c2", "p1", "c3", "p0", "c4", "clean is not completion authority", "immediately previous"],
    )
    add_file_check(
        "watcher_template_lens",
        "maintenance/templates/WATCHER_REPORT.md",
        ["adversarial review verdict", "fix required", "clean", "defect classes checked", "pm merge recommendation"],
    )
    add_file_check(
        "pre_ship_template_lens",
        "maintenance/templates/PRE_SHIP_AUDIT_CONTEXT.md",
        ["immediately previous turn to review", "required review lens", "clean-all-slop"],
    )
    return write_smoke_report(root, "adversarial-review-integration-smoke", checks)


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
        "normalizer_template",
        "maintenance/templates/NORMALIZED_WORKER_PACKET.md",
        ["claims rejected or unsupported", "commands not run", "completion authority"],
    )
    add_file_check(
        "observer_role",
        "agents/observer.toml",
        ["clean-all-slop", "read-only", "do not repair", "watcher_report", "pm merge recommendation"],
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
        ["immediately previous turn to review", "required review lens", "clean-all-slop", "reset to define"],
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
