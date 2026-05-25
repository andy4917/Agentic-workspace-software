from __future__ import annotations
import json
import hashlib
import os
import subprocess
import tomllib
from pathlib import Path
from typing import Any
from codex_agent_harness_base import *
from codex_agent_harness_naming import normalize_hook_event_name
def check_orchestration_governance_smoke(root: Path) -> dict[str, Any]:
    checks: list[dict[str, Any]] = []

    def add_check(name: str, passed: bool, detail: str) -> None:
        checks.append({"name": name, "status": "pass" if passed else "fail", "detail": detail})

    agents_text = read_text(root / "AGENTS.md")
    charter_text = read_text(root / "maintenance" / "SUBAGENT_DELEGATION_CHARTER.md")
    audit_text = read_text(root / "codex-goals" / "_template" / "FINAL_GOAL_AUDIT.md")
    hook_files = [root / "hooks" / "compact-codex-hook.ps1"]
    hook_files.extend(sorted((root / "hooks" / "lib").glob("*.ps1")))
    hook_text = "\n".join(read_text(path) for path in hook_files if path.exists())

    add_check(
        "agents_goal_governance",
        all(term in agents_text for term in ["## Goals", "tracking marker", "final goal audit", "maintenance/GOAL_INTEGRITY_GATE.md"]),
        "AGENTS.md should keep compact parent-goal ownership and point to the detailed gate runbook.",
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
        "stop_hook_next_turn_handoff",
        all(term in hook_text for term in ["function Compute-Handoff", "NEXT_TURN_WORK_ITEMS", "Continue-Ok", "Get-SessionPendingPath"]),
        "Stop hook should record next-turn handoff instead of forcing a final-answer correction pass.",
    )
    main_hook_text = read_text(root / "hooks" / "compact-codex-hook.ps1")
    add_check(
        "compact_hook_single_file",
        "PermissionRequest" not in read_text(root / "hooks.json")
        and "decision:block" in main_hook_text
        and "permissionDecision" in main_hook_text,
        "Compact v3 should be a single active hook file and exclude PermissionRequest from hooks.json.",
    )

    status = "pass" if all(item["status"] == "pass" for item in checks) else "fail"
    report = {"generated_at": utc_now(), "status": status, "checks": checks}
    write_json(root / "reports" / "orchestration-governance-smoke.latest.json", report)
    return report


def run_lightweight_hook_sample(root: Path, payload: dict[str, Any]) -> dict[str, Any]:
    env = os.environ.copy()
    env["CODEX_HOOK_SMOKE"] = "1"
    try:
        completed = subprocess.run(
            ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "hooks/compact-codex-hook.ps1"],
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
    return run_lightweight_hook_sample(
        root,
        {"hook_event_name": "PreToolUse", "tool_name": "functions.shell_command", "tool_input": {"command": command}},
    )


def run_prompt_hook_sample(root: Path, prompt: str) -> dict[str, Any]:
    return run_lightweight_hook_sample(
        root,
        {"hook_event_name": "UserPromptSubmit", "prompt": prompt, "cwd": str(root), "permission_mode": "default"},
    )


def run_post_tool_hook_sample(root: Path, tool_name: str, command: str) -> dict[str, Any]:
    return run_lightweight_hook_sample(
        root,
        {"hook_event_name": "PostToolUse", "tool_name": tool_name, "tool_input": {"command": command}},
    )


def run_subagent_session_start_sample(root: Path) -> dict[str, Any]:
    return run_lightweight_hook_sample(
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
    return run_lightweight_hook_sample(
        root,
        {"hook_event_name": "Stop", "last_assistant_message": message, "stop_hook_active": False},
    )


def check_hook_policy_smoke(root: Path) -> dict[str, Any]:
    checks: list[dict[str, Any]] = []

    def add_check(name: str, passed: bool, detail: str) -> None:
        checks.append({"name": name, "status": "pass" if passed else "fail", "detail": detail})

    session_id = "harness-v3-" + os.urandom(8).hex()
    cwd = str(root / f".hook-smoke-{session_id}")
    turn = "t1"
    temp_dir = Path(os.environ.get("TEMP", str(root))) / "codex-compact-hooks-v3"
    cwd_hash = hashlib.sha256(cwd.encode("utf-8")).hexdigest()[:12]

    def sample(event: str, **fields: Any) -> dict[str, Any]:
        payload: dict[str, Any] = {
            "hook_event_name": event,
            "session_id": session_id,
            "turn_id": fields.pop("turn_id", turn),
            "cwd": cwd,
        }
        payload.update(fields)
        return run_lightweight_hook_sample(root, payload)

    def stdout(probe: dict[str, Any]) -> str:
        return str(probe.get("stdout_preview", ""))

    def stderr(probe: dict[str, Any]) -> str:
        return str(probe.get("stderr_preview", ""))

    def read_pending_json(path: Path) -> dict[str, Any]:
        try:
            return json.loads(read_text(path).lstrip("\ufeff"))
        except (OSError, json.JSONDecodeError):
            return {}

    try:
        config = tomllib.loads(read_text(root / "config.toml"))
        hook_state = config.get("hooks", {}).get("state", {})
        event_enabled: dict[str, bool] = {}
        for key, value in hook_state.items():
            if not isinstance(value, dict):
                continue
            parts = str(key).split(":")
            if len(parts) >= 3:
                event_enabled[normalize_hook_event_name(parts[-3])] = bool(value.get("enabled", True))
        for event in ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop"]:
            event_enabled.setdefault(event, True)
        event_enabled.setdefault("PermissionRequest", False)
    except (OSError, tomllib.TOMLDecodeError):
        event_enabled = {}

    try:
        add_check(
            "compact_v3_runtime_active_state",
            event_enabled.get("SessionStart") is True
            and event_enabled.get("UserPromptSubmit") is True
            and event_enabled.get("PreToolUse") is True
            and event_enabled.get("PostToolUse") is True
            and event_enabled.get("Stop") is True
            and event_enabled.get("PermissionRequest") is False,
            "Runtime hook state should enable compact v3 events and keep PermissionRequest excluded.",
        )

        prompt_probe = sample("UserPromptSubmit", prompt="Apply a hook config update and verify it.")
        add_check(
            "user_prompt_submit_emits_compact_frame",
            prompt_probe.get("status") == "pass"
            and "TASK_PURPOSE" in stdout(prompt_probe)
            and "HOOK_WORKFRAME" in stdout(prompt_probe)
            and not stderr(prompt_probe),
            "UserPromptSubmit should emit the compact task frame without PowerShell errors.",
        )

        secret_probe = sample(
            "PreToolUse",
            tool_name="functions.shell_command",
            tool_input={"command": "Get-Content .env"},
        )
        add_check(
            "pre_tool_use_denies_secret_read",
            '"permissionDecision":"deny"' in stdout(secret_probe)
            and "secret/credential" in stdout(secret_probe)
            and not stderr(secret_probe),
            "PreToolUse should deny secret-like file reads.",
        )

        destructive_probe = sample(
            "PreToolUse",
            tool_name="functions.shell_command",
            tool_input={"command": "git reset --hard"},
        )
        add_check(
            "pre_tool_use_denies_destructive_command",
            '"permissionDecision":"deny"' in stdout(destructive_probe)
            and "destructive" in stdout(destructive_probe)
            and not stderr(destructive_probe),
            "PreToolUse should deny destructive commands.",
        )

        mutation_before_sync = sample(
            "PreToolUse",
            tool_name="functions.apply_patch",
            tool_input={"patch": "*** Update File: C:\\Users\\anise\\.codex\\hooks.json"},
        )
        add_check(
            "pre_tool_use_denies_mutation_before_context_sync",
            '"permissionDecision":"deny"' in stdout(mutation_before_sync)
            and "context sync required" in stdout(mutation_before_sync).lower()
            and not stderr(mutation_before_sync),
            "PreToolUse should deny first mutation on non-trivial work before context sync.",
        )

        mixed_context_mutation_before_sync = sample(
            "PreToolUse",
            tool_name="functions.shell_command",
            tool_input={"command": "git status --short; Set-Content hooks.json '{}'"},
        )
        add_check(
            "pre_tool_use_denies_mixed_context_and_mutation_before_sync",
            '"permissionDecision":"deny"' in stdout(mixed_context_mutation_before_sync)
            and "context sync required" in stdout(mixed_context_mutation_before_sync).lower()
            and not stderr(mixed_context_mutation_before_sync),
            "PreToolUse should deny a mixed read/mutation command before context sync.",
        )

        context_probe = sample(
            "PostToolUse",
            tool_name="functions.shell_command",
            tool_input={"command": "git status --short"},
            tool_response={"exit_code": 0, "stdout": ""},
        )
        add_check(
            "post_tool_use_records_context_sync",
            context_probe.get("status") == "pass" and stdout(context_probe).strip() == "" and not stderr(context_probe),
            "PostToolUse should record context sync without emitting raw output.",
        )

        mutation_before_workframe = sample(
            "PreToolUse",
            tool_name="functions.apply_patch",
            tool_input={"patch": "*** Update File: C:\\Users\\anise\\.codex\\hooks.json"},
        )
        add_check(
            "pre_tool_use_denies_control_plane_mutation_before_workframe",
            '"permissionDecision":"deny"' in stdout(mutation_before_workframe)
            and "impact frame required" in stdout(mutation_before_workframe).lower()
            and not stderr(mutation_before_workframe),
            "PreToolUse should deny control-plane mutation before HOOK_WORKFRAME.",
        )

        mixed_workframe_mutation_before_workframe = sample(
            "PreToolUse",
            tool_name="functions.shell_command",
            tool_input={
                "command": 'Write-Output "HOOK_WORKFRAME purpose=test; surface=hooks; impact=hooks; checks=smoke; rollback=restore"; Set-Content hooks.json "{}"'
            },
        )
        add_check(
            "pre_tool_use_denies_mixed_workframe_and_mutation_before_workframe",
            '"permissionDecision":"deny"' in stdout(mixed_workframe_mutation_before_workframe)
            and "impact frame required" in stdout(mixed_workframe_mutation_before_workframe).lower()
            and not stderr(mixed_workframe_mutation_before_workframe),
            "PreToolUse should not treat a mixed workframe/mutation command as a prior impact frame.",
        )

        workframe_probe = sample(
            "PostToolUse",
            tool_name="functions.shell_command",
            tool_input={
                "command": 'Write-Output "HOOK_WORKFRAME purpose=test; surface=hooks; impact=hooks; checks=smoke; rollback=restore"'
            },
            tool_response={
                "exit_code": 0,
                "stdout": "HOOK_WORKFRAME purpose=test; surface=hooks; impact=hooks; checks=smoke; rollback=restore",
            },
        )
        add_check(
            "post_tool_use_records_workframe",
            workframe_probe.get("status") == "pass" and stdout(workframe_probe).strip() == "" and not stderr(workframe_probe),
            "PostToolUse should record a compact workframe marker.",
        )

        mutation_after_workframe = sample(
            "PreToolUse",
            tool_name="functions.apply_patch",
            tool_input={"patch": "*** Update File: C:\\Users\\anise\\.codex\\hooks.json"},
        )
        add_check(
            "pre_tool_use_allows_mutation_after_sync_and_workframe",
            mutation_after_workframe.get("status") == "pass"
            and stdout(mutation_after_workframe).strip() == ""
            and not stderr(mutation_after_workframe),
            "PreToolUse should allow mutation after context sync and HOOK_WORKFRAME.",
        )

        changed_probe = sample(
            "PostToolUse",
            tool_name="functions.apply_patch",
            tool_input={"patch": "*** Update File: C:\\Users\\anise\\.codex\\hooks.json"},
            tool_response={"exit_code": 0, "stdout": "Success"},
        )
        add_check(
            "post_tool_use_records_changed_state",
            changed_probe.get("status") == "pass" and stdout(changed_probe).strip() == "" and not stderr(changed_probe),
            "PostToolUse should record changed state without storing raw tool output.",
        )

        stop_probe = sample(
            "Stop",
            last_assistant_message="Changed compact hooks. SUBAGENT_CALL not_used reason=smoke substitute=direct hook samples residual risk=low.",
        )
        add_check(
            "stop_returns_continue_true_without_block",
            stop_probe.get("status") == "pass"
            and '"continue":true' in stdout(stop_probe)
            and '"decision":"block"' not in stdout(stop_probe).lower()
            and not stderr(stop_probe),
            "Stop should write pending handoff if needed and return continue:true, never decision:block.",
        )

        pending_path = temp_dir / f"{session_id}.pending.json"
        pending = read_pending_json(pending_path)
        pending_text = json.dumps(pending, sort_keys=True)
        add_check(
            "stop_writes_sanitized_pending_handoff",
            pending.get("kind") == "next_turn_handoff"
            and "SECRET_READ_BLOCKED" in pending_text
            and "DESTRUCTIVE_ACTION_BLOCKED" in pending_text
            and "Success" not in pending_text
            and "git status --short" not in pending_text,
            "Pending handoff should contain compact work items, not raw tool output or full commands.",
        )

        next_prompt_probe = sample("UserPromptSubmit", turn_id="t2", prompt="Continue.")
        add_check(
            "next_prompt_injects_pending_once",
            next_prompt_probe.get("status") == "pass"
            and "NEXT_TURN_WORK_ITEMS" in stdout(next_prompt_probe)
            and not stderr(next_prompt_probe),
            "The next UserPromptSubmit should inject pending handoff work items once.",
        )

        delivered = read_pending_json(pending_path)
        repeat_prompt_probe = sample("UserPromptSubmit", turn_id="t3", prompt="Continue again.")
        add_check(
            "pending_handoff_marked_delivered",
            delivered.get("delivered") is True
            and "NEXT_TURN_WORK_ITEMS" not in stdout(repeat_prompt_probe)
            and not stderr(repeat_prompt_probe),
            "Delivered pending handoff should not be injected repeatedly.",
        )
    finally:
        for path in temp_dir.glob(f"{session_id}*.json"):
            try:
                path.unlink()
            except FileNotFoundError:
                pass
        try:
            (temp_dir / f"cwd-{cwd_hash}.pending.json").unlink()
        except FileNotFoundError:
            pass

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
        ["midpoint and pre-ship", "maintenance/GOAL_INTEGRITY_GATE.md", "maintenance/WORKER_WATCHER_NORMALIZED_HANDOFF.md", "WATCHER_NOT_USED"],
    )
    return write_smoke_report(root, "goal-integrity-gate-smoke", checks)
