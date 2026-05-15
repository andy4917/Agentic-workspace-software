from __future__ import annotations

import json
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
    hook_files = [
        root / "hooks" / "lightweight-codex-hook.ps1",
        root / "hooks" / "lib" / "lightweight-codex-core.ps1",
        root / "hooks" / "lib" / "lightweight-codex-workflow.ps1",
        root / "hooks" / "lib" / "lightweight-codex-guards.ps1",
    ]
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
        all(term in hook_text for term in ["function Test-FinalAuditReady", "function Get-ToolEvidenceSummary", "Final preflight", "checked items", "PM independent verification"]),
        "Stop hook should ask for an audit and keep hook evidence summaries compact.",
    )

    status = "pass" if all(item["status"] == "pass" for item in checks) else "fail"
    report = {"generated_at": utc_now(), "status": status, "checks": checks}
    write_json(root / "reports" / "orchestration-governance-smoke.latest.json", report)
    return report


def run_lightweight_hook_sample(root: Path, payload: dict[str, Any]) -> dict[str, Any]:
    try:
        completed = subprocess.run(
            ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", "hooks/lightweight-codex-hook.ps1"],
            cwd=root,
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
    state_path = root / "hooks" / "state" / "lightweight-status.json"
    original_state_exists = state_path.exists()
    original_state_bytes = state_path.read_bytes() if original_state_exists else None

    def add_check(name: str, passed: bool, detail: str) -> None:
        checks.append({"name": name, "status": "pass" if passed else "fail", "detail": detail})

    try:
        fake_marker = "sk-" + "test-not-real-" + ("0" * 20)
        prompt_probe = run_prompt_hook_sample(root, f"Please use {fake_marker} for this run.")
        add_check(
            "prompt_secret_like_value_blocked",
            '"decision":"block"' in prompt_probe.get("stdout_preview", ""),
            "UserPromptSubmit should block secret-like values before they reach the model.",
        )

        korean_failure = "".join(chr(codepoint) for codepoint in [0xC2E4, 0xD328])
        korean_hook = "".join(chr(codepoint) for codepoint in [0xD6C5])
        workflow_prompt = (
            f"{korean_failure} {korean_hook} P0 root cause: user authorized subagent and watcher work. "
            "Classify L1/L2/L3/L4, compile English intent, set goal, and continue workflow."
        )
        workflow_probe = run_prompt_hook_sample(root, workflow_prompt)
        workflow_stdout = workflow_probe.get("stdout_preview", "").lower()
        add_check(
            "workflow_prompt_emits_l4_contract",
            all(
                term in workflow_stdout
                for term in [
                    "task_class=l4",
                    "output rule",
                    "reasoning and internal frames private",
                    "goal action required",
                    "watcher action required",
                    "delegation authorized",
                    "subagent call declaration required",
                    "calibration action required",
                ]
            ),
            "UserPromptSubmit should emit an actionable concise L4 PM contract without exposing the full reasoning frame.",
        )
        add_check(
            "workflow_prompt_hides_internal_reasoning_labels",
            "meta-decompose" not in workflow_stdout
            and "internal english intent frame" not in workflow_stdout
            and "required pm startup packet" not in workflow_stdout,
            "UserPromptSubmit should keep decomposition and English intent framing as internal PM state, not user-visible prose.",
        )
        session_start_probe = run_subagent_session_start_sample(root)
        session_start_stdout = session_start_probe.get("stdout_preview", "").lower()
        add_check(
            "subagent_session_start_vowline_fixture",
            session_start_probe.get("status") == "pass"
            and all(
                term in session_start_stdout
                for term in [
                    "subagent startup requirement",
                    "vowline",
                    "agents.md",
                    "agent_tool_requirements.md",
                    "support-only memory",
                ]
            ),
            "SessionStart should inject the current workspace Vowline fixture for subagent sessions.",
        )

        try:
            hook_state = json.loads(read_text(state_path))
        except (OSError, json.JSONDecodeError) as exc:
            hook_state = {"_error": str(exc)}
        add_check(
            "workflow_prompt_persists_structured_state",
            hook_state.get("taskClass") == "L4"
            and hook_state.get("delegationAuthorized") is True
            and hook_state.get("goalRequired") is True
            and hook_state.get("watcherExpected") is True
            and hook_state.get("anomalyPauseExpected") is True
            and hook_state.get("subagentDecisionRequired") is True
            and "delegation_authorized" in hook_state.get("userAuthorizations", [])
            and isinstance(hook_state.get("intentFrame"), dict)
            and bool(hook_state.get("intentFrame", {}).get("english_normalized_goal"))
            and bool(hook_state.get("intentFrame", {}).get("subagent_call_declaration"))
            and bool(hook_state.get("intentFrame", {}).get("calibration_action")),
            "Hook state should retain task class, delegation authorization, goal requirement, watcher expectation, subagent call decision, anomaly calibration, and English intent frame.",
        )

        selector = "Select-" + "String"
        search_terms = "|".join(["pass" + "word", "api[_-]?key", "sec" + "ret", "to" + "ken", "credential", "private key"])
        staged_scan_command = (
            "$diff = git -C 'C:\\Work\\repo' diff --cached; "
            f"$matches = $diff | {selector} -Pattern '{search_terms}' -CaseSensitive:$false"
        )
        staged_scan = run_hook_sample(root, staged_scan_command)
        add_check(
            "staged_diff_sensitive_scan_allowed",
            staged_scan.get("status") == "pass" and "permissionDecision" not in staged_scan.get("stdout_preview", ""),
            "Staged git diff validation should not be confused with direct credential file reads.",
        )

        direct_read_command = "Get-" + "Content C:\\Users\\example\\.codex\\auth.json"
        direct_read = run_hook_sample(root, direct_read_command)
        add_check(
            "direct_auth_file_read_blocked",
            "permissionDecision" in direct_read.get("stdout_preview", "") and "deny" in direct_read.get("stdout_preview", "").lower(),
            "Direct auth file reads must remain blocked.",
        )

        mixed_read_command = (
            ("Get-" + "Content C:\\Users\\example\\.codex\\secret.txt; ")
            + staged_scan_command
        )
        mixed_read = run_hook_sample(root, mixed_read_command)
        add_check(
            "mixed_direct_read_staged_scan_blocked",
            "permissionDecision" in mixed_read.get("stdout_preview", "") and "deny" in mixed_read.get("stdout_preview", "").lower(),
            "Staged diff validation must not allow a mixed direct protected-file read.",
        )

        scanner_script = run_hook_sample(root, "powershell.exe -NoProfile -ExecutionPolicy Bypass -File maintenance/scripts/check-staged-sensitive-diff.ps1")
        add_check(
            "redacted_staged_scanner_allowed",
            scanner_script.get("status") == "pass" and "permissionDecision" not in scanner_script.get("stdout_preview", ""),
            "The redacted staged-diff scanner should be allowed as the preferred validation path.",
        )

        run_post_tool_hook_sample(root, "apply_patch", "apply_patch changed file test")
        delegated_final_without_marker = (
            "FINAL_GOAL_AUDIT pause trigger: anomaly pause from delegated hook state. first mismatch/root cause traced. "
            "checked verification. checks not run none. residual risk low. status complete. PM independent verification complete. "
            "accepted/rejected subagent evidence none. WATCHER_NOT_USED reason direct smoke substitute check."
        )
        delegated_final_with_marker = (
            "FINAL_GOAL_AUDIT pause trigger: anomaly pause from delegated hook state. first mismatch/root cause traced. "
            "checked verification. checks not run none. residual risk low. status complete. PM independent verification complete. "
            "accepted/rejected subagent evidence none. WATCHER_NOT_USED reason direct smoke substitute check. "
            "SUBAGENT_CALL not_used reason PM kept work local evidence direct hook sample."
        )
        stop_missing_subagent = run_stop_hook_sample(root, delegated_final_without_marker)
        stop_with_subagent = run_stop_hook_sample(root, delegated_final_with_marker)
        add_check(
            "stop_requires_explicit_subagent_call_marker",
            "subagent use was explicitly authorized or a subagent tool event was observed" in stop_missing_subagent.get("stdout_preview", "").lower()
            and '"continue":true' in stop_with_subagent.get("stdout_preview", "").lower(),
            "Stop should reject delegated finals without SUBAGENT_CALL used/not_used and allow the explicit marker with reason/evidence.",
        )

        pm_led_probe = run_prompt_hook_sample(root, "Review PM-led team preset workflow routing and level escalation criteria.")
        try:
            pm_led_state = json.loads(read_text(state_path))
        except (OSError, json.JSONDecodeError):
            pm_led_state = {}
        add_check(
            "pm_led_team_preset_not_subagent_authorization",
            pm_led_probe.get("status") == "pass"
            and pm_led_state.get("delegationAuthorized") is False
            and pm_led_state.get("subagentDecisionRequired") is False,
            "PM-led/team preset wording alone should not require SUBAGENT_CALL evidence.",
        )

        run_prompt_hook_sample(root, "Tiny local note.")
        pre_level_probe = run_hook_sample(root, "python skills/ui-ux-pro-max/scripts/design_system.py --help")
        try:
            pre_level_state = json.loads(read_text(state_path))
        except (OSError, json.JSONDecodeError):
            pre_level_state = {}
        add_check(
            "pretooluse_can_raise_level_for_skill_script_surface",
            pre_level_probe.get("status") == "pass"
            and pre_level_state.get("taskClass") == "L3"
            and any("Compatibility review required" in str(item) for item in pre_level_state.get("requiredReminders", [])),
            "PreToolUse should raise task class and require compatibility review for skill script surfaces.",
        )

        run_post_tool_hook_sample(
            root,
            "apply_patch",
            "*** Update File: hooks/lightweight-codex-hook.ps1\n+root cause workflow harness adjustment\n",
        )
        try:
            post_level_state = json.loads(read_text(state_path))
        except (OSError, json.JSONDecodeError):
            post_level_state = {}
        add_check(
            "posttooluse_can_raise_l4_for_incident_governance_surface",
            post_level_state.get("taskClass") == "L4"
            and post_level_state.get("anomalyPauseExpected") is True
            and any("Compatibility review required" in str(item) for item in post_level_state.get("requiredReminders", [])),
            "PostToolUse should raise to L4 when incident language intersects workflow/harness surfaces.",
        )

        run_post_tool_hook_sample(root, "spawn_agent", '{"agent_type":"reviewer"}')
        event_final_without_marker = (
            "FINAL_GOAL_AUDIT pause trigger: posttool governance incident. first mismatch/root cause traced. "
            "checked direct subagent event state. checks not run none. "
            "residual risk low. status complete. PM independent verification complete."
        )
        event_final_with_marker = (
            event_final_without_marker
            + " SUBAGENT_CALL used reason subagent tool event observed direct evidence spawn_agent residual risk low."
        )
        event_stop_missing = run_stop_hook_sample(root, event_final_without_marker)
        event_stop_with_marker = run_stop_hook_sample(root, event_final_with_marker)
        add_check(
            "stop_requires_marker_after_actual_subagent_tool_event",
            "subagent use was explicitly authorized or a subagent tool event was observed" in event_stop_missing.get("stdout_preview", "").lower()
            and '"continue":true' in event_stop_with_marker.get("stdout_preview", "").lower(),
            "Stop should require SUBAGENT_CALL evidence when a subagent tool event exists, even without prompt authorization state.",
        )
    finally:
        if original_state_exists:
            state_path.parent.mkdir(parents=True, exist_ok=True)
            state_path.write_bytes(original_state_bytes or b"")
        else:
            try:
                state_path.unlink()
            except FileNotFoundError:
                pass

    restored_state_exists = state_path.exists()
    restored_state_bytes = state_path.read_bytes() if restored_state_exists else None
    add_check(
        "hook_policy_smoke_restores_live_state",
        restored_state_exists == original_state_exists and restored_state_bytes == original_state_bytes,
        "Synthetic UserPromptSubmit samples must not leave L4 delegated watcher state behind for the real Stop hook.",
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
