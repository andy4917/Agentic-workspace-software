from __future__ import annotations

import json
import tomllib
from pathlib import Path
from typing import Any

from codex_agent_harness_base import load_json, read_text, run_command


HOOK_EVENT_ALIASES = {
    "sessionstart": "SessionStart",
    "session_start": "SessionStart",
    "userpromptsubmit": "UserPromptSubmit",
    "user_prompt_submit": "UserPromptSubmit",
    "pretooluse": "PreToolUse",
    "pre_tool_use": "PreToolUse",
    "permissionrequest": "PermissionRequest",
    "permission_request": "PermissionRequest",
    "posttooluse": "PostToolUse",
    "post_tool_use": "PostToolUse",
    "stop": "Stop",
}


def normalize_hook_event_name(name: str) -> str:
    normalized = name.strip().replace("-", "_").lower()
    return HOOK_EVENT_ALIASES.get(normalized, HOOK_EVENT_ALIASES.get(normalized.replace("_", ""), name))


def hook_runtime_state_status(root: Path) -> dict[str, Any]:
    config_path = root / "config.toml"
    policy_path = root / "hooks" / "policy.compact.json"
    hooks_path = root / "hooks.json"
    if not config_path.exists():
        return {"status": "fail", "error": "config.toml missing"}
    try:
        config = tomllib.loads(read_text(config_path))
    except tomllib.TOMLDecodeError as exc:
        return {"status": "fail", "error": str(exc)}
    state_doc = load_json(root / "maintenance" / "CODEX_HOME_STRUCTURE_STATE.json", {})
    expected = state_doc.get("hook_runtime_state", {}) if isinstance(state_doc, dict) else {}
    policy = load_json(policy_path, {})
    if not expected and isinstance(policy, dict):
        expected = {
            "active_events": policy.get("hook_events_used", []),
            "inactive_events": policy.get("hook_events_excluded", []),
        }
    active_events = set(expected.get("active_events", ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop"]))
    inactive_events = set(expected.get("inactive_events", ["PermissionRequest"]))
    hooks_doc = load_json(hooks_path, {})
    configured_events = set((hooks_doc.get("hooks", {}) if isinstance(hooks_doc, dict) else {}).keys())
    state = config.get("hooks", {}).get("state", {}) if isinstance(config.get("hooks"), dict) else {}
    observed: dict[str, bool] = {}
    for key, value in state.items():
        if not isinstance(value, dict):
            continue
        parts = str(key).split(":")
        if len(parts) < 3:
            continue
        observed[normalize_hook_event_name(parts[-3])] = bool(value.get("enabled", True))
    for event in active_events | inactive_events:
        observed.setdefault(event, event in configured_events)
    mismatches = []
    for event in sorted(active_events):
        if observed.get(event) is not True:
            mismatches.append(f"{event} expected active")
    for event in sorted(inactive_events):
        if observed.get(event) is not False:
            mismatches.append(f"{event} expected inactive")
    return {
        "status": "pass" if not mismatches else "fail",
        "observed": observed,
        "expected_active": sorted(active_events),
        "expected_inactive": sorted(inactive_events),
        "mismatches": mismatches,
    }


def naming_convention_status(root: Path) -> dict[str, Any]:
    script = root / "maintenance" / "scripts" / "check-naming-conventions.ps1"
    if not script.exists():
        return {"status": "fail", "error": "check-naming-conventions.ps1 missing"}
    result = run_command(
        ["powershell.exe", "-NoProfile", "-ExecutionPolicy", "Bypass", "-File", str(script), "-Json"],
        root,
        timeout=120,
    )
    data: dict[str, Any] = {}
    try:
        data = json.loads(result.get("stdout_preview", "") or "{}")
    except json.JSONDecodeError:
        data = {}
    return {
        "status": "pass" if result.get("exit_code") == 0 and data.get("status") == "pass" else "fail",
        "exit_code": result.get("exit_code"),
        "finding_count": data.get("finding_count"),
        "blocking_count": data.get("blocking_count"),
        "findings": data.get("findings", []),
        "stderr_preview": result.get("stderr_preview", ""),
    }
