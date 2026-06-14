from __future__ import annotations
import base64
import json
import os
import shlex
import subprocess
import tomllib
from pathlib import Path
from typing import Any
from codex_agent_harness_base import (
    COMMAND_PREVIEW_CHARS,
    hook_route_uses_hidden_compact_runner,
    no_window_creationflags,
    read_text,
    redact_obvious_secrets,
    utc_now,
    write_json,
)


def check_orchestration_governance_smoke(root: Path) -> dict[str, Any]:
    checks: list[dict[str, Any]] = []
    ledger_path = root / "state" / "hook-ledger.jsonl"
    original_state_dir_exists = ledger_path.parent.exists()
    original_ledger_exists = ledger_path.exists()
    original_ledger_bytes = ledger_path.read_bytes() if original_ledger_exists else None

    def add_check(name: str, passed: bool, detail: str) -> None:
        checks.append(
            {"name": name, "status": "pass" if passed else "fail", "detail": detail}
        )

    agents_text = read_text(root / "AGENTS.md")
    charter_text = read_text(root / "maintenance" / "SUBAGENT_DELEGATION_CHARTER.md")
    audit_template = root / "codex-goals" / "_template" / "FINAL_GOAL_AUDIT.md"
    audit_text = read_text(audit_template) if audit_template.exists() else ""
    full_agents_goal_governance = all(
        term in agents_text
        for term in [
            "## Goal Governance",
            "tracking marker",
            "final goal audit",
            "Subagents receive contractual subgoals",
        ]
    )
    compact_agents_goal_governance = all(
        term in agents_text
        for term in [
            "compact live bootstrap",
            "reviewed repo `AGENTS.md`",
            "outputs evidence-only",
            "completion authority",
        ]
    )
    add_check(
        "agents_goal_governance",
        full_agents_goal_governance or compact_agents_goal_governance,
        "AGENTS.md should define parent-goal ownership directly or delegate compact live bootstrap governance to the reviewed managed source.",
    )
    add_check(
        "subagent_authority_boundary",
        all(
            term in charter_text
            for term in ["## Authority Boundary", "evidence only", "cannot complete"]
        ),
        "Delegation charter should prevent subagent parent-goal completion authority.",
    )
    add_check(
        "final_audit_template",
        all(
            term in audit_text
            for term in [
                "# FINAL_GOAL_AUDIT",
                "Direct Checks Not Run",
                "Residual Risks",
                "PM Independent Verification",
                "Decision",
            ]
        ),
        "Final audit template should require checked, not-run, risks, PM verification, and status.",
    )
    try:
        stop_probe = run_stop_hook_sample(
            root, "final answer without a synthetic goal audit"
        )
        stop_stdout = stop_probe.get("stdout_preview", "").lower()
        add_check(
            "stop_hook_record_only_runtime",
            stop_probe.get("status") == "pass"
            and "permissiondecision" not in stop_stdout
            and "deny" not in stop_stdout
            and '"decision":"block"' not in stop_stdout
            and '"continue":false' not in stop_stdout,
            "Compact Stop hook should record evidence without claiming audit-blocking completion authority.",
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
            if not original_state_dir_exists:
                try:
                    ledger_path.parent.rmdir()
                except OSError:
                    pass
    restored_ledger_exists = ledger_path.exists()
    restored_ledger_bytes = ledger_path.read_bytes() if restored_ledger_exists else None
    add_check(
        "orchestration_smoke_restores_live_ledger",
        restored_ledger_exists == original_ledger_exists
        and restored_ledger_bytes == original_ledger_bytes,
        "Synthetic orchestration Stop samples must not leave hook ledger mutations behind.",
    )
    status = "pass" if all(item["status"] == "pass" for item in checks) else "fail"
    report = {"generated_at": utc_now(), "status": status, "checks": checks}
    write_json(root / "reports" / "orchestration-governance-smoke.latest.json", report)
    return report


def configured_hook_command(root: Path, event_name: str) -> str:
    config_path = root / "config.d" / "20-hooks.toml"
    try:
        hook_config = tomllib.loads(read_text(config_path))
    except (FileNotFoundError, tomllib.TOMLDecodeError) as exc:
        raise RuntimeError(f"cannot read configured hook route: {exc}") from exc
    hook_section = hook_config.get("hooks", {}) if isinstance(hook_config, dict) else {}
    event_entries = hook_section.get(event_name, [])
    if not isinstance(event_entries, list):
        event_entries = []
    command_key = "commandWindows" if os.name == "nt" else "command"
    for event_entry in event_entries:
        hook_entries = (
            event_entry.get("hooks", []) if isinstance(event_entry, dict) else []
        )
        if not isinstance(hook_entries, list):
            continue
        for hook_entry in hook_entries:
            if not isinstance(hook_entry, dict):
                continue
            command = str(
                hook_entry.get(command_key) or hook_entry.get("command") or ""
            ).strip()
            if command:
                return command
    raise RuntimeError(f"missing configured hook route for {event_name}")


def configured_hook_argv_for_smoke(root: Path, event_name: str) -> list[str]:
    command = configured_hook_command(root, event_name)
    argv = shlex.split(command, posix=(os.name != "nt"))
    if os.name == "nt":
        argv = [
            arg[1:-1] if len(arg) >= 2 and arg[0] == '"' and arg[-1] == '"' else arg
            for arg in argv
        ]
    candidate_hook = str(root / "hooks" / "compact-codex-hook.ps1")
    candidate_pwsh_shim = str(root / "toolchains" / "shims" / "pwsh.ps1")
    allowed_root = root.resolve()

    def assert_configured_target(
        value: str, expected_leaf: str, expected_suffix: tuple[str, ...]
    ) -> None:
        expanded = Path(os.path.expandvars(value))
        if expanded.name.lower() != expected_leaf.lower():
            raise RuntimeError(f"configured hook target {value} is not {expected_leaf}")
        resolved = expanded.resolve(strict=False)
        if resolved != allowed_root and allowed_root not in resolved.parents:
            parts = tuple(part.lower() for part in resolved.parts)
            suffix = tuple(part.lower() for part in expected_suffix)
            if ".codex" not in parts or parts[-len(suffix) :] != suffix:
                raise RuntimeError(
                    f"configured hook target is outside smoke Codex root: {resolved}"
                )

    rewrote_file = False
    rewrote_pwsh_shim = False
    for index, arg in enumerate(argv[:-1]):
        if Path(arg).name.lower() == "pwsh.ps1":
            assert_configured_target(
                arg, "pwsh.ps1", ("toolchains", "shims", "pwsh.ps1")
            )
            argv[index] = candidate_pwsh_shim
            rewrote_pwsh_shim = True
        if (
            arg.lower() == "-file"
            and Path(argv[index + 1]).name.lower() == "compact-codex-hook.ps1"
        ):
            assert_configured_target(
                argv[index + 1],
                "compact-codex-hook.ps1",
                ("hooks", "compact-codex-hook.ps1"),
            )
            argv[index + 1] = candidate_hook
            rewrote_file = True
    if not rewrote_file:
        raise RuntimeError(
            "configured hook route does not expose a compact-codex-hook.ps1 -File target"
        )
    if os.name == "nt" and not rewrote_pwsh_shim:
        raise RuntimeError(
            "configured hook route does not expose a pwsh.ps1 shim target"
        )
    return argv


def run_compact_hook_sample(root: Path, payload: dict[str, Any]) -> dict[str, Any]:
    env = os.environ.copy()
    env["CODEX_HOOK_SMOKE"] = "1"
    env["CODEX_HOME"] = str(root)
    event_name = str(
        payload.get("hook_event_name") or payload.get("hookEventName") or ""
    )
    try:
        argv = configured_hook_argv_for_smoke(root, event_name)
        completed = subprocess.run(
            argv,
            cwd=root,
            env=env,
            input=json.dumps(payload),
            text=True,
            capture_output=True,
            timeout=30,
            creationflags=no_window_creationflags(),
        )
        return {
            "status": "pass" if completed.returncode == 0 else "fail",
            "exit_code": completed.returncode,
            "stdout_preview": redact_obvious_secrets(
                completed.stdout[-COMMAND_PREVIEW_CHARS:]
            ),
            "stderr_preview": redact_obvious_secrets(
                completed.stderr[-COMMAND_PREVIEW_CHARS:]
            ),
        }
    except (RuntimeError, OSError, ValueError) as exc:
        return {
            "status": "fail",
            "exit_code": 2,
            "stdout_preview": "",
            "stderr_preview": str(exc),
        }
    except subprocess.TimeoutExpired as exc:
        return {
            "status": "fail",
            "exit_code": 124,
            "stdout_preview": "",
            "stderr_preview": str(exc),
        }


def run_hook_sample(root: Path, command: str) -> dict[str, Any]:
    return run_compact_hook_sample(
        root,
        {
            "hook_event_name": "PreToolUse",
            "tool_name": "functions.shell_command",
            "tool_input": {"command": command},
        },
    )


def run_camel_hook_sample(root: Path, command: str) -> dict[str, Any]:
    return run_compact_hook_sample(
        root,
        {
            "hookEventName": "PreToolUse",
            "toolName": "functions.shell_command",
            "toolInput": {"command": command},
        },
    )


def run_apply_patch_sample(root: Path, patch: str) -> dict[str, Any]:
    return run_compact_hook_sample(
        root,
        {
            "hook_event_name": "PreToolUse",
            "tool_name": "functions.apply_patch",
            "tool_input": {"patch": patch},
        },
    )


def run_nested_apply_patch_sample(root: Path, patch: str) -> dict[str, Any]:
    return run_compact_hook_sample(
        root,
        {
            "hook_event_name": "PreToolUse",
            "tool_name": "multi_tool_use.parallel",
            "tool_input": {
                "tool_uses": [
                    {
                        "recipient_name": "functions.apply_patch",
                        "parameters": {"patch": patch},
                    },
                ],
            },
        },
    )


def run_prompt_hook_sample(root: Path, prompt: str) -> dict[str, Any]:
    return run_compact_hook_sample(
        root,
        {
            "hook_event_name": "UserPromptSubmit",
            "prompt": prompt,
            "cwd": str(root),
            "permission_mode": "default",
        },
    )


def run_post_tool_hook_sample(
    root: Path, tool_name: str, command: str
) -> dict[str, Any]:
    return run_compact_hook_sample(
        root,
        {
            "hook_event_name": "PostToolUse",
            "tool_name": tool_name,
            "tool_input": {"command": command},
        },
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
        {
            "hook_event_name": "Stop",
            "last_assistant_message": message,
            "stop_hook_active": False,
        },
    )


def check_hook_policy_smoke(root: Path) -> dict[str, Any]:
    checks: list[dict[str, Any]] = []
    ledger_path = root / "state" / "hook-ledger.jsonl"
    original_state_dir_exists = ledger_path.parent.exists()
    original_ledger_exists = ledger_path.exists()
    original_ledger_bytes = ledger_path.read_bytes() if original_ledger_exists else None

    def add_check(name: str, passed: bool, detail: str) -> None:
        checks.append(
            {"name": name, "status": "pass" if passed else "fail", "detail": detail}
        )

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
        required_matcher_terms = [
            "functions\\\\..*",
            "multi_tool_use\\\\..*",
            "multi_agent.*",
            "tool_search\\\\..*",
            "web\\\\..*",
            "image_gen\\\\..*",
            "codex_app\\\\..*",
            "mcp__.*",
        ]
        hook_matchers: dict[str, str] = {}
        current_hook_event = ""
        for raw_line in config_text.splitlines():
            line = raw_line.strip()
            if line == "[[hooks.PreToolUse]]":
                current_hook_event = "PreToolUse"
            elif line == "[[hooks.PostToolUse]]":
                current_hook_event = "PostToolUse"
            elif line.startswith("[[hooks."):
                current_hook_event = ""
            elif current_hook_event and line.startswith("matcher"):
                hook_matchers[current_hook_event] = line
        add_check(
            "hook_config_covers_desktop_tool_namespaces",
            all(
                all(
                    term in hook_matchers.get(event, "")
                    for term in required_matcher_terms
                )
                for event in ["PreToolUse", "PostToolUse"]
            ),
            "Active PreToolUse and PostToolUse matchers should each cover Desktop tool namespaces that can carry shell, MCP, or automation payloads.",
        )
        add_check(
            "hook_config_runs_hidden_on_windows",
            "WindowStyle Hidden" in config_text
            and config_text.count("ExecutionPolicy Bypass") >= 20
            and "cmd /c" not in config_text
            and "\\appdata\\local\\microsoft\\windowsapps\\pwsh.exe"
            not in config_text.lower()
            and "\\program files\\windowsapps\\microsoft.powershell_"
            not in config_text.lower()
            and config_text.count("commandWindows") >= 5,
            "Active hook fragment should define hidden commandWindows overrides for every hook through the stable pwsh.ps1 route while preserving stdout.",
        )
        route_errors: list[str] = []
        route_hits: list[str] = []
        try:
            hook_config = tomllib.loads(config_text)
        except tomllib.TOMLDecodeError as exc:
            hook_config = {}
            route_errors.append(f"invalid hook TOML: {exc}")
        hook_section = (
            hook_config.get("hooks", {}) if isinstance(hook_config, dict) else {}
        )
        for event in [
            "SessionStart",
            "UserPromptSubmit",
            "PreToolUse",
            "PostToolUse",
            "Stop",
        ]:
            event_entries = hook_section.get(event, [])
            if not isinstance(event_entries, list) or not event_entries:
                route_errors.append(f"{event}: missing event")
                continue
            event_ok = False
            for event_entry in event_entries:
                hook_entries = (
                    event_entry.get("hooks", [])
                    if isinstance(event_entry, dict)
                    else []
                )
                for hook_entry in (
                    hook_entries if isinstance(hook_entries, list) else []
                ):
                    if not isinstance(hook_entry, dict):
                        continue
                    command = str(hook_entry.get("command", ""))
                    command_windows = str(hook_entry.get("commandWindows", ""))
                    if hook_route_uses_hidden_compact_runner(
                        command, command_windows, require_execution_policy_bypass=True
                    ):
                        event_ok = True
                        route_hits.append(event)
            if not event_ok:
                route_errors.append(f"{event}: missing configured hidden wrapper route")
        add_check(
            "hook_config_uses_configured_hidden_wrapper_routes",
            not route_errors and len(set(route_hits)) == 5,
            "; ".join(route_errors[:5])
            if route_errors
            else "All hook events route through command and commandWindows hidden compact runner definitions with parent and child execution-policy bypass, without cmd shim nesting, WindowsApps alias stubs, or version-pinned WindowsApps pwsh paths.",
        )
        add_check(
            "compact_hook_contains_current_contract",
            all(
                term in hook_text
                for term in [
                    'runner = "compact-codex-hook"',
                    "hook-ledger.jsonl",
                    "UserPromptSubmit",
                    "PreToolUse",
                ]
            ),
            "Compact hook should expose the current event contract and ledger.",
        )
        prompt_probe = run_prompt_hook_sample(root, "Compact hook smoke.")
        prompt_stdout = prompt_probe.get("stdout_preview", "").lower()
        add_check(
            "user_prompt_submit_emits_compact_context",
            prompt_probe.get("status") == "pass"
            and "compact hook active" in prompt_stdout
            and "treat claims as candidate" in prompt_stdout,
            "UserPromptSubmit should emit the compact current-evidence reminder for ordinary prompts.",
        )
        secret_prompt_probe = run_prompt_hook_sample(
            root,
            "Here is a fake token for smoke testing: sk-proj_FAKEFAKEFAKEFAKEFAKEFAKEFAKE",
        )
        secret_prompt_stdout = secret_prompt_probe.get("stdout_preview", "").lower()
        structured_prompt_probe = run_compact_hook_sample(
            root,
            {
                "hook_event_name": "UserPromptSubmit",
                "prompt": [
                    {
                        "type": "text",
                        "text": "fake smoke token sk-proj_FAKEFAKEFAKEFAKEFAKEFAKEFAKE",
                    }
                ],
                "cwd": str(root),
                "permission_mode": "default",
            },
        )
        structured_prompt_stdout = structured_prompt_probe.get(
            "stdout_preview", ""
        ).lower()
        add_check(
            "user_prompt_submit_blocks_secret_like_values",
            secret_prompt_probe.get("status") == "pass"
            and '"decision":"block"' in secret_prompt_stdout
            and structured_prompt_probe.get("status") == "pass"
            and '"decision":"block"' in structured_prompt_stdout
            and "secret-like value" in secret_prompt_stdout,
            "UserPromptSubmit should block high-confidence secret-like prompt values without storing the raw prompt.",
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
            "PreToolUse should allow ordinary inspected tool use and record evidence.",
        )
        encoded_payload = base64.b64encode(
            "Write-Output encoded-smoke".encode("utf-16le")
        ).decode("ascii")
        encoded_probe = run_hook_sample(
            root, f"powershell -EncodedCommand {encoded_payload}"
        )
        encoded_stdout = encoded_probe.get("stdout_preview", "").lower()
        nested_encoded_probe = run_hook_sample(
            root, f"cmd /c pwsh -enc {encoded_payload}"
        )
        nested_encoded_stdout = nested_encoded_probe.get("stdout_preview", "").lower()
        path_encoded_probe = run_hook_sample(
            root,
            f"C:\\Windows\\System32\\WindowsPowerShell\\v1.0\\powershell.exe -EncodedCommand {encoded_payload}",
        )
        path_encoded_stdout = path_encoded_probe.get("stdout_preview", "").lower()
        ec_encoded_probe = run_hook_sample(root, f"powershell -ec {encoded_payload}")
        ec_encoded_stdout = ec_encoded_probe.get("stdout_preview", "").lower()
        call_operator_encoded_probe = run_hook_sample(
            root, f"& 'powershell' -EncodedCommand {encoded_payload}"
        )
        call_operator_encoded_stdout = call_operator_encoded_probe.get(
            "stdout_preview", ""
        ).lower()
        start_process_encoded_probe = run_hook_sample(
            root,
            f"Start-Process pwsh -ArgumentList '-EncodedCommand', '{encoded_payload}'",
        )
        start_process_encoded_stdout = start_process_encoded_probe.get(
            "stdout_preview", ""
        ).lower()
        pwsh_ps1_encoded_probe = run_hook_sample(
            root, f"pwsh.ps1 -EncodedCommand {encoded_payload}"
        )
        pwsh_ps1_encoded_stdout = pwsh_ps1_encoded_probe.get(
            "stdout_preview", ""
        ).lower()
        start_process_pwsh_ps1_encoded_probe = run_hook_sample(
            root,
            f"Start-Process pwsh.ps1 -ArgumentList '-EncodedCommand', '{encoded_payload}'",
        )
        start_process_pwsh_ps1_encoded_stdout = (
            start_process_pwsh_ps1_encoded_probe.get("stdout_preview", "").lower()
        )
        pwsh_cmd_encoded_probe = run_hook_sample(
            root, f"pwsh.cmd -Encoded {encoded_payload}"
        )
        pwsh_cmd_encoded_stdout = pwsh_cmd_encoded_probe.get(
            "stdout_preview", ""
        ).lower()
        cmd_pwsh_cmd_encoded_probe = run_hook_sample(
            root, f"cmd /c pwsh.cmd -Enco {encoded_payload}"
        )
        cmd_pwsh_cmd_encoded_stdout = cmd_pwsh_cmd_encoded_probe.get(
            "stdout_preview", ""
        ).lower()
        saps_encoded_probe = run_hook_sample(
            root, f"saps pwsh -ArgumentList '-enc', '{encoded_payload}'"
        )
        saps_encoded_stdout = saps_encoded_probe.get("stdout_preview", "").lower()
        programmatic_exec_encoded_probe = run_compact_hook_sample(
            root,
            {
                "hook_event_name": "PreToolUse",
                "tool_name": "functions.exec",
                "tool_input": f"await tools.shell_command({{command: 'powershell -EncodedCommand {encoded_payload}'}})",
            },
        )
        programmatic_exec_encoded_stdout = programmatic_exec_encoded_probe.get(
            "stdout_preview", ""
        ).lower()
        add_check(
            "pretooluse_blocks_encoded_powershell",
            encoded_probe.get("status") == "pass"
            and "permissiondecision" in encoded_stdout
            and "deny" in encoded_stdout
            and nested_encoded_probe.get("status") == "pass"
            and "deny" in nested_encoded_stdout
            and path_encoded_probe.get("status") == "pass"
            and "deny" in path_encoded_stdout
            and ec_encoded_probe.get("status") == "pass"
            and "deny" in ec_encoded_stdout
            and call_operator_encoded_probe.get("status") == "pass"
            and "deny" in call_operator_encoded_stdout
            and start_process_encoded_probe.get("status") == "pass"
            and "deny" in start_process_encoded_stdout
            and pwsh_ps1_encoded_probe.get("status") == "pass"
            and "deny" in pwsh_ps1_encoded_stdout
            and start_process_pwsh_ps1_encoded_probe.get("status") == "pass"
            and "deny" in start_process_pwsh_ps1_encoded_stdout
            and pwsh_cmd_encoded_probe.get("status") == "pass"
            and "deny" in pwsh_cmd_encoded_stdout
            and cmd_pwsh_cmd_encoded_probe.get("status") == "pass"
            and "deny" in cmd_pwsh_cmd_encoded_stdout
            and saps_encoded_probe.get("status") == "pass"
            and "deny" in saps_encoded_stdout
            and programmatic_exec_encoded_probe.get("status") == "pass"
            and "deny" in programmatic_exec_encoded_stdout,
            "PreToolUse should deny encoded PowerShell payloads, including Start-Process and functions.exec wrappers, instead of trusting plaintext path inspection.",
        )
        readonly_destructive_search_probe = run_hook_sample(
            root, 'rg -n "Remove-Item|rm -rf" hooks\\*.ps1 maintenance\\*.py'
        )
        readonly_destructive_search_stdout = readonly_destructive_search_probe.get(
            "stdout_preview", ""
        ).lower()
        select_destructive_search_probe = run_hook_sample(
            root, 'Select-String -Pattern "Remove-Item -Recurse *" -Path hooks\\*.ps1'
        )
        select_destructive_search_stdout = select_destructive_search_probe.get(
            "stdout_preview", ""
        ).lower()
        readonly_git_clean_name_probe = run_hook_sample(
            root, "git ls-files -- .codex/skills/clean-all-slop/SKILL.md"
        )
        readonly_git_clean_name_stdout = readonly_git_clean_name_probe.get(
            "stdout_preview", ""
        ).lower()
        git_clean_long_force_probe = run_hook_sample(root, "git clean --force -d")
        git_clean_long_force_stdout = git_clean_long_force_probe.get(
            "stdout_preview", ""
        ).lower()
        git_ps1_clean_force_probe = run_hook_sample(root, "git.ps1 clean -fd")
        git_ps1_clean_force_stdout = git_ps1_clean_force_probe.get(
            "stdout_preview", ""
        ).lower()
        git_scoped_clean_long_force_probe = run_hook_sample(
            root, "git -C . clean --force -d"
        )
        git_scoped_clean_long_force_stdout = git_scoped_clean_long_force_probe.get(
            "stdout_preview", ""
        ).lower()
        git_clean_interactive_probe = run_hook_sample(root, "git clean -i")
        git_clean_interactive_stdout = git_clean_interactive_probe.get(
            "stdout_preview", ""
        ).lower()
        git_clean_long_interactive_probe = run_hook_sample(
            root, "git clean --interactive"
        )
        git_clean_long_interactive_stdout = git_clean_long_interactive_probe.get(
            "stdout_preview", ""
        ).lower()
        git_clean_dry_run_probe = run_hook_sample(root, "git clean -nfd")
        git_clean_dry_run_stdout = git_clean_dry_run_probe.get(
            "stdout_preview", ""
        ).lower()
        git_clean_long_dry_run_probe = run_hook_sample(root, "git clean --dry-run -fd")
        git_clean_long_dry_run_stdout = git_clean_long_dry_run_probe.get(
            "stdout_preview", ""
        ).lower()
        git_force_push_probe = run_hook_sample(root, "git push origin HEAD --force")
        git_force_push_stdout = git_force_push_probe.get("stdout_preview", "").lower()
        git_ps1_force_push_probe = run_hook_sample(
            root, "git.ps1 push origin HEAD --force"
        )
        git_ps1_force_push_stdout = git_ps1_force_push_probe.get(
            "stdout_preview", ""
        ).lower()
        git_inline_option_force_push_probe = run_hook_sample(
            root, "git --git-dir=C:\\repo\\.git push origin HEAD --force"
        )
        git_inline_option_force_push_stdout = git_inline_option_force_push_probe.get(
            "stdout_preview", ""
        ).lower()
        git_inline_option_clean_probe = run_hook_sample(
            root, "git --git-dir=.git clean -fd"
        )
        git_inline_option_clean_stdout = git_inline_option_clean_probe.get(
            "stdout_preview", ""
        ).lower()
        bash_nested_rm_probe = run_hook_sample(root, "bash -lc 'rm -rf /'")
        bash_nested_rm_stdout = bash_nested_rm_probe.get("stdout_preview", "").lower()
        git_force_with_lease_push_probe = run_hook_sample(
            root, "git push --force-with-lease origin HEAD"
        )
        git_force_with_lease_push_stdout = git_force_with_lease_push_probe.get(
            "stdout_preview", ""
        ).lower()
        git_plus_refspec_push_probe = run_hook_sample(
            root, "git push origin +HEAD:main"
        )
        git_plus_refspec_push_stdout = git_plus_refspec_push_probe.get(
            "stdout_preview", ""
        ).lower()
        git_scoped_plus_refspec_push_probe = run_hook_sample(
            root, "git -C . push origin +HEAD:main"
        )
        git_scoped_plus_refspec_push_stdout = git_scoped_plus_refspec_push_probe.get(
            "stdout_preview", ""
        ).lower()
        git_push_delete_probe = run_hook_sample(
            root, "git push origin --delete old-branch"
        )
        git_push_delete_stdout = git_push_delete_probe.get("stdout_preview", "").lower()
        git_push_colon_delete_probe = run_hook_sample(
            root, "git push origin :old-branch"
        )
        git_push_colon_delete_stdout = git_push_colon_delete_probe.get(
            "stdout_preview", ""
        ).lower()
        git_push_mirror_probe = run_hook_sample(root, "git push --mirror origin")
        git_push_mirror_stdout = git_push_mirror_probe.get("stdout_preview", "").lower()
        git_push_prune_probe = run_hook_sample(root, "git push --prune origin")
        git_push_prune_stdout = git_push_prune_probe.get("stdout_preview", "").lower()
        git_array_force_probe = run_hook_sample(
            root, "git @('push','origin','--force')"
        )
        git_array_force_stdout = git_array_force_probe.get("stdout_preview", "").lower()
        start_process_git_force_probe = run_hook_sample(
            root, "Start-Process git -ArgumentList 'push','origin','--force'"
        )
        start_process_git_force_stdout = start_process_git_force_probe.get(
            "stdout_preview", ""
        ).lower()
        start_process_git_colon_force_probe = run_hook_sample(
            root, "Start-Process -FilePath:git -ArgumentList:'push','origin','--force'"
        )
        start_process_git_colon_force_stdout = start_process_git_colon_force_probe.get(
            "stdout_preview", ""
        ).lower()
        start_process_git_ps1_force_probe = run_hook_sample(
            root, "Start-Process git.ps1 -ArgumentList 'push','origin','--force'"
        )
        start_process_git_ps1_force_stdout = start_process_git_ps1_force_probe.get(
            "stdout_preview", ""
        ).lower()
        start_process_git_arg_force_probe = run_hook_sample(
            root, "Start-Process git -Arg 'push','origin','--force'"
        )
        start_process_git_arg_force_stdout = start_process_git_arg_force_probe.get(
            "stdout_preview", ""
        ).lower()
        start_process_git_a_force_probe = run_hook_sample(
            root, "Start-Process git -A 'push','origin','--force'"
        )
        start_process_git_a_force_stdout = start_process_git_a_force_probe.get(
            "stdout_preview", ""
        ).lower()
        start_process_git_positional_force_probe = run_hook_sample(
            root, "Start-Process git 'push origin --force'"
        )
        start_process_git_positional_force_stdout = (
            start_process_git_positional_force_probe.get("stdout_preview", "").lower()
        )
        start_process_git_windowstyle_force_probe = run_hook_sample(
            root, "Start-Process git -WindowStyle Hidden 'push origin --force'"
        )
        start_process_git_windowstyle_force_stdout = (
            start_process_git_windowstyle_force_probe.get("stdout_preview", "").lower()
        )
        start_process_git_wi_force_probe = run_hook_sample(
            root, "Start-Process git -Wi Hidden 'push origin --force'"
        )
        start_process_git_wi_force_stdout = start_process_git_wi_force_probe.get(
            "stdout_preview", ""
        ).lower()
        call_operator_git_force_probe = run_hook_sample(
            root, "& 'git' push origin --force"
        )
        call_operator_git_force_stdout = call_operator_git_force_probe.get(
            "stdout_preview", ""
        ).lower()
        invoke_expression_git_force_probe = run_hook_sample(
            root, "Invoke-Expression 'git push origin --force'"
        )
        invoke_expression_git_force_stdout = invoke_expression_git_force_probe.get(
            "stdout_preview", ""
        ).lower()
        invoke_expression_benign_probe = run_hook_sample(
            root, "Invoke-Expression 'Write-Output ok'"
        )
        invoke_expression_benign_stdout = invoke_expression_benign_probe.get(
            "stdout_preview", ""
        ).lower()
        iex_benign_probe = run_hook_sample(root, "iex 'Write-Output ok'")
        iex_benign_stdout = iex_benign_probe.get("stdout_preview", "").lower()
        invoke_expression_variable_git_force_probe = run_hook_sample(
            root, "$x='git push origin --force'; Invoke-Expression $x"
        )
        invoke_expression_variable_git_force_stdout = (
            invoke_expression_variable_git_force_probe.get("stdout_preview", "").lower()
        )
        invoke_expression_call_operator_git_force_probe = run_hook_sample(
            root, "& 'Invoke-Expression' 'git push origin --force'"
        )
        invoke_expression_call_operator_git_force_stdout = (
            invoke_expression_call_operator_git_force_probe.get(
                "stdout_preview", ""
            ).lower()
        )
        pwsh_colon_command_force_probe = run_hook_sample(
            root, "pwsh -Command:'git push origin --force'"
        )
        pwsh_colon_command_force_stdout = pwsh_colon_command_force_probe.get(
            "stdout_preview", ""
        ).lower()
        start_process_destructive_probe = run_hook_sample(
            root,
            "Start-Process pwsh -ArgumentList '-Command','Remove-Item $env:USERPROFILE\\.codex\\tmp -Recurse -Force'",
        )
        start_process_destructive_stdout = start_process_destructive_probe.get(
            "stdout_preview", ""
        ).lower()
        programmatic_exec_destructive_probe = run_compact_hook_sample(
            root,
            {
                "hook_event_name": "PreToolUse",
                "tool_name": "functions.exec",
                "tool_input": "await tools.shell_command({command: 'Remove-Item $env:USERPROFILE\\\\.codex\\\\tmp -Recurse -Force'})",
            },
        )
        programmatic_exec_destructive_stdout = programmatic_exec_destructive_probe.get(
            "stdout_preview", ""
        ).lower()
        exec_command_protected_read_probe = run_compact_hook_sample(
            root,
            {
                "hook_event_name": "PreToolUse",
                "tool_name": "functions.exec_command",
                "tool_input": {
                    "command": "Get-Content $env:USERPROFILE\\.codex\\auth.json"
                },
            },
        )
        exec_command_protected_read_stdout = exec_command_protected_read_probe.get(
            "stdout_preview", ""
        ).lower()
        exec_command_destructive_probe = run_compact_hook_sample(
            root,
            {
                "hook_event_name": "PreToolUse",
                "tool_name": "functions.exec_command",
                "tool_input": {
                    "command": "Remove-Item $env:USERPROFILE\\.codex\\tmp -Recurse -Force"
                },
            },
        )
        exec_command_destructive_stdout = exec_command_destructive_probe.get(
            "stdout_preview", ""
        ).lower()
        exec_command_regular_probe = run_compact_hook_sample(
            root,
            {
                "hook_event_name": "PreToolUse",
                "tool_name": "functions.exec_command",
                "tool_input": {"command": "git status -sb"},
            },
        )
        exec_command_regular_stdout = exec_command_regular_probe.get(
            "stdout_preview", ""
        ).lower()
        git_regular_push_probe = run_hook_sample(root, "git push origin HEAD")
        git_regular_push_stdout = git_regular_push_probe.get(
            "stdout_preview", ""
        ).lower()
        add_check(
            "pretooluse_allows_readonly_destructive_reference_search",
            readonly_destructive_search_probe.get("status") == "pass"
            and "allow" in readonly_destructive_search_stdout
            and select_destructive_search_probe.get("status") == "pass"
            and "allow" in select_destructive_search_stdout
            and readonly_git_clean_name_probe.get("status") == "pass"
            and "allow" in readonly_git_clean_name_stdout,
            "PreToolUse should not deny read-only search or Git listing commands merely because arguments mention destructive command names.",
        )
        add_check(
            "pretooluse_blocks_git_clean_long_force",
            git_clean_long_force_probe.get("status") == "pass"
            and "deny" in git_clean_long_force_stdout
            and git_ps1_clean_force_probe.get("status") == "pass"
            and "deny" in git_ps1_clean_force_stdout
            and git_scoped_clean_long_force_probe.get("status") == "pass"
            and "deny" in git_scoped_clean_long_force_stdout,
            "PreToolUse should deny git clean --force forms, including when git -C is used before the clean subcommand.",
        )
        add_check(
            "pretooluse_blocks_git_clean_interactive",
            git_clean_interactive_probe.get("status") == "pass"
            and "deny" in git_clean_interactive_stdout
            and git_clean_long_interactive_probe.get("status") == "pass"
            and "deny" in git_clean_long_interactive_stdout,
            "PreToolUse should deny non-dry-run git clean interactive forms because they can still delete files.",
        )
        add_check(
            "pretooluse_allows_git_clean_dry_run",
            git_clean_dry_run_probe.get("status") == "pass"
            and "permissiondecision" in git_clean_dry_run_stdout
            and "allow" in git_clean_dry_run_stdout
            and git_clean_long_dry_run_probe.get("status") == "pass"
            and "allow" in git_clean_long_dry_run_stdout,
            "PreToolUse should allow git clean dry-run forms because they inspect rather than delete.",
        )
        add_check(
            "pretooluse_allows_benign_literal_invoke_expression",
            invoke_expression_benign_probe.get("status") == "pass"
            and "allow" in invoke_expression_benign_stdout
            and iex_benign_probe.get("status") == "pass"
            and "allow" in iex_benign_stdout,
            "PreToolUse should inspect literal Invoke-Expression content instead of denying every benign literal expression.",
        )
        add_check(
            "pretooluse_inspects_exec_command_tools",
            exec_command_protected_read_probe.get("status") == "pass"
            and "deny" in exec_command_protected_read_stdout
            and exec_command_destructive_probe.get("status") == "pass"
            and "deny" in exec_command_destructive_stdout
            and exec_command_regular_probe.get("status") == "pass"
            and "allow" in exec_command_regular_stdout,
            "PreToolUse should inspect functions.exec_command payloads for secret reads and broad destructive operations while preserving ordinary shell commands.",
        )
        add_check(
            "pretooluse_blocks_git_force_push",
            git_force_push_probe.get("status") == "pass"
            and "deny" in git_force_push_stdout
            and git_ps1_force_push_probe.get("status") == "pass"
            and "deny" in git_ps1_force_push_stdout
            and git_inline_option_force_push_probe.get("status") == "pass"
            and "deny" in git_inline_option_force_push_stdout
            and git_inline_option_clean_probe.get("status") == "pass"
            and "deny" in git_inline_option_clean_stdout
            and bash_nested_rm_probe.get("status") == "pass"
            and "deny" in bash_nested_rm_stdout
            and git_force_with_lease_push_probe.get("status") == "pass"
            and "deny" in git_force_with_lease_push_stdout
            and git_plus_refspec_push_probe.get("status") == "pass"
            and "deny" in git_plus_refspec_push_stdout
            and git_scoped_plus_refspec_push_probe.get("status") == "pass"
            and "deny" in git_scoped_plus_refspec_push_stdout
            and git_push_delete_probe.get("status") == "pass"
            and "deny" in git_push_delete_stdout
            and git_push_colon_delete_probe.get("status") == "pass"
            and "deny" in git_push_colon_delete_stdout
            and git_push_mirror_probe.get("status") == "pass"
            and "deny" in git_push_mirror_stdout
            and git_push_prune_probe.get("status") == "pass"
            and "deny" in git_push_prune_stdout
            and git_array_force_probe.get("status") == "pass"
            and "deny" in git_array_force_stdout
            and start_process_git_force_probe.get("status") == "pass"
            and "deny" in start_process_git_force_stdout
            and start_process_git_colon_force_probe.get("status") == "pass"
            and "deny" in start_process_git_colon_force_stdout
            and start_process_git_ps1_force_probe.get("status") == "pass"
            and "deny" in start_process_git_ps1_force_stdout
            and start_process_git_arg_force_probe.get("status") == "pass"
            and "deny" in start_process_git_arg_force_stdout
            and start_process_git_a_force_probe.get("status") == "pass"
            and "deny" in start_process_git_a_force_stdout
            and start_process_git_positional_force_probe.get("status") == "pass"
            and "deny" in start_process_git_positional_force_stdout
            and start_process_git_windowstyle_force_probe.get("status") == "pass"
            and "deny" in start_process_git_windowstyle_force_stdout
            and start_process_git_wi_force_probe.get("status") == "pass"
            and "deny" in start_process_git_wi_force_stdout
            and call_operator_git_force_probe.get("status") == "pass"
            and "deny" in call_operator_git_force_stdout
            and invoke_expression_git_force_probe.get("status") == "pass"
            and "deny" in invoke_expression_git_force_stdout
            and invoke_expression_variable_git_force_probe.get("status") == "pass"
            and "deny" in invoke_expression_variable_git_force_stdout
            and invoke_expression_call_operator_git_force_probe.get("status") == "pass"
            and "deny" in invoke_expression_call_operator_git_force_stdout
            and pwsh_colon_command_force_probe.get("status") == "pass"
            and "deny" in pwsh_colon_command_force_stdout
            and start_process_destructive_probe.get("status") == "pass"
            and "deny" in start_process_destructive_stdout
            and programmatic_exec_destructive_probe.get("status") == "pass"
            and "deny" in programmatic_exec_destructive_stdout
            and git_regular_push_probe.get("status") == "pass"
            and "allow" in git_regular_push_stdout,
            "PreToolUse should deny git push force/delete forms, plus-refspec forced updates, Start-Process wrappers, and functions.exec destructive wrappers while preserving ordinary push.",
        )
        sensitive_apply_patch = """*** Begin Patch
*** Update File: C:\\Users\\anise\\.codex\\auth.json
@@
-old
+new
*** End Patch
"""
        ordinary_apply_patch = """*** Begin Patch
*** Update File: docs\\note.md
@@
-old
+new
*** End Patch
"""
        parent_apply_patch = """*** Begin Patch
*** Update File: ..\\config.toml
@@
-old
+new
*** End Patch
"""
        rooted_apply_patch = """*** Begin Patch
*** Update File: C:\\Users\\anise\\.codex\\config.toml
@@
-old
+new
*** End Patch
"""
        current_drive_apply_patch = """*** Begin Patch
*** Update File: \\Users\\anise\\.codex\\config.toml
@@
-old
+new
*** End Patch
"""
        home_relative_apply_patch = """*** Begin Patch
*** Update File: ~\\config.toml
@@
-old
+new
*** End Patch
"""
        drive_relative_apply_patch = """*** Begin Patch
*** Update File: C:config.toml
@@
-old
+new
*** End Patch
"""
        sensitive_apply_patch_probe = run_apply_patch_sample(
            root, sensitive_apply_patch
        )
        sensitive_apply_patch_stdout = sensitive_apply_patch_probe.get(
            "stdout_preview", ""
        ).lower()
        nested_sensitive_apply_patch_probe = run_nested_apply_patch_sample(
            root, sensitive_apply_patch
        )
        nested_sensitive_apply_patch_stdout = nested_sensitive_apply_patch_probe.get(
            "stdout_preview", ""
        ).lower()
        parent_apply_patch_probe = run_apply_patch_sample(root, parent_apply_patch)
        parent_apply_patch_stdout = parent_apply_patch_probe.get(
            "stdout_preview", ""
        ).lower()
        rooted_apply_patch_probe = run_apply_patch_sample(root, rooted_apply_patch)
        rooted_apply_patch_stdout = rooted_apply_patch_probe.get(
            "stdout_preview", ""
        ).lower()
        current_drive_apply_patch_probe = run_apply_patch_sample(
            root, current_drive_apply_patch
        )
        current_drive_apply_patch_stdout = current_drive_apply_patch_probe.get(
            "stdout_preview", ""
        ).lower()
        home_relative_apply_patch_probe = run_apply_patch_sample(
            root, home_relative_apply_patch
        )
        home_relative_apply_patch_stdout = home_relative_apply_patch_probe.get(
            "stdout_preview", ""
        ).lower()
        drive_relative_apply_patch_probe = run_apply_patch_sample(
            root, drive_relative_apply_patch
        )
        drive_relative_apply_patch_stdout = drive_relative_apply_patch_probe.get(
            "stdout_preview", ""
        ).lower()
        ordinary_apply_patch_probe = run_apply_patch_sample(root, ordinary_apply_patch)
        ordinary_apply_patch_stdout = ordinary_apply_patch_probe.get(
            "stdout_preview", ""
        ).lower()
        add_check(
            "pretooluse_blocks_sensitive_apply_patch_targets",
            sensitive_apply_patch_probe.get("status") == "pass"
            and "deny" in sensitive_apply_patch_stdout
            and nested_sensitive_apply_patch_probe.get("status") == "pass"
            and "deny" in nested_sensitive_apply_patch_stdout
            and parent_apply_patch_probe.get("status") == "pass"
            and "deny" in parent_apply_patch_stdout
            and rooted_apply_patch_probe.get("status") == "pass"
            and "deny" in rooted_apply_patch_stdout
            and current_drive_apply_patch_probe.get("status") == "pass"
            and "deny" in current_drive_apply_patch_stdout
            and home_relative_apply_patch_probe.get("status") == "pass"
            and "deny" in home_relative_apply_patch_stdout
            and drive_relative_apply_patch_probe.get("status") == "pass"
            and "deny" in drive_relative_apply_patch_stdout
            and ordinary_apply_patch_probe.get("status") == "pass"
            and "allow" in ordinary_apply_patch_stdout,
            "PreToolUse should deny direct and nested apply_patch targeting sensitive, rooted, or parent-traversal files while preserving ordinary patch targets.",
        )
        blocked_probe = run_hook_sample(
            root, "Get-Content $env:USERPROFILE\\.codex\\auth.json"
        )
        blocked_stdout = blocked_probe.get("stdout_preview", "").lower()
        camel_blocked_probe = run_camel_hook_sample(
            root, "Get-Content $env:USERPROFILE\\.codex\\auth.json"
        )
        camel_blocked_stdout = camel_blocked_probe.get("stdout_preview", "").lower()
        npmrc_blocked_probe = run_hook_sample(
            root, "Get-Content $env:USERPROFILE\\.npmrc"
        )
        npmrc_blocked_stdout = npmrc_blocked_probe.get("stdout_preview", "").lower()
        kube_blocked_probe = run_hook_sample(
            root, "Get-Content $env:USERPROFILE\\.kube\\config"
        )
        kube_blocked_stdout = kube_blocked_probe.get("stdout_preview", "").lower()
        ordinary_config_probe = run_hook_sample(root, "Get-Content config.toml")
        ordinary_config_stdout = ordinary_config_probe.get("stdout_preview", "").lower()
        add_check(
            "pretooluse_blocks_direct_secret_reads",
            blocked_probe.get("status") == "pass"
            and "permissiondecision" in blocked_stdout
            and "deny" in blocked_stdout
            and npmrc_blocked_probe.get("status") == "pass"
            and "deny" in npmrc_blocked_stdout
            and kube_blocked_probe.get("status") == "pass"
            and "deny" in kube_blocked_stdout
            and ordinary_config_probe.get("status") == "pass"
            and "allow" in ordinary_config_stdout
            and "credential" in blocked_stdout,
            "PreToolUse should deny direct credential-file read probes instead of unconditionally allowing them.",
        )
        add_check(
            "pretooluse_inspects_camel_case_tool_payloads",
            camel_blocked_probe.get("status") == "pass"
            and "permissiondecision" in camel_blocked_stdout
            and "deny" in camel_blocked_stdout,
            "PreToolUse should inspect hookEventName/toolName/toolInput payloads as well as snake_case payloads.",
        )
        mcp_blocked_probe = run_compact_hook_sample(
            root,
            {
                "hook_event_name": "PreToolUse",
                "tool_name": "mcp__fs__read",
                "tool_input": {"path": str(Path.home() / ".codex" / "auth.json")},
            },
        )
        mcp_blocked_stdout = mcp_blocked_probe.get("stdout_preview", "").lower()
        mcp_fetch_blocked_probe = run_compact_hook_sample(
            root,
            {
                "hook_event_name": "PreToolUse",
                "tool_name": "mcp__codex_apps__github._fetch_file",
                "tool_input": {"path": str(Path.home() / ".codex" / "auth.json")},
            },
        )
        mcp_fetch_blocked_stdout = mcp_fetch_blocked_probe.get(
            "stdout_preview", ""
        ).lower()
        add_check(
            "pretooluse_blocks_mcp_secret_reads",
            mcp_blocked_probe.get("status") == "pass"
            and "permissiondecision" in mcp_blocked_stdout
            and "deny" in mcp_blocked_stdout
            and "credential" in mcp_blocked_stdout,
            "PreToolUse should deny MCP credential-file read probes as well as shell probes.",
        )
        add_check(
            "pretooluse_blocks_mcp_fetch_file_secret_reads",
            mcp_fetch_blocked_probe.get("status") == "pass"
            and "permissiondecision" in mcp_fetch_blocked_stdout
            and "deny" in mcp_fetch_blocked_stdout,
            "PreToolUse should deny MCP fetch_file-style credential reads, including connector tool names that use dots.",
        )
        mcp_non_file_get_probe = run_compact_hook_sample(
            root,
            {
                "hook_event_name": "PreToolUse",
                "tool_name": "mcp__github__get_issue",
                "tool_input": {
                    "query": "docs mention auth.json but no file path is read"
                },
            },
        )
        mcp_non_file_get_stdout = mcp_non_file_get_probe.get(
            "stdout_preview", ""
        ).lower()
        add_check(
            "pretooluse_allows_non_file_mcp_getters",
            mcp_non_file_get_probe.get("status") == "pass"
            and "permissiondecision" in mcp_non_file_get_stdout
            and "allow" in mcp_non_file_get_stdout,
            "PreToolUse should not classify every MCP getter as a filesystem read.",
        )
        more_blocked_probe = run_hook_sample(
            root, "more $env:USERPROFILE\\.codex\\auth.json"
        )
        more_blocked_stdout = more_blocked_probe.get("stdout_preview", "").lower()
        add_check(
            "pretooluse_blocks_more_secret_reads",
            more_blocked_probe.get("status") == "pass"
            and "permissiondecision" in more_blocked_stdout
            and "deny" in more_blocked_stdout,
            "PreToolUse should deny direct credential-file reads through more as well as cat/Get-Content.",
        )
        generic_name_probe = run_hook_sample(root, "Get-Content .\\token.json")
        generic_name_stdout = generic_name_probe.get("stdout_preview", "").lower()
        add_check(
            "pretooluse_blocks_generic_secret_filenames",
            generic_name_probe.get("status") == "pass"
            and "permissiondecision" in generic_name_stdout
            and "deny" in generic_name_stdout,
            "PreToolUse should deny generic secret-like filenames, not only auth.json and key material.",
        )
        interpreter_probe = run_hook_sample(
            root, "python -c \"open('$env:USERPROFILE\\.codex\\auth.json').read()\""
        )
        interpreter_stdout = interpreter_probe.get("stdout_preview", "").lower()
        add_check(
            "pretooluse_blocks_interpreter_secret_reads",
            interpreter_probe.get("status") == "pass"
            and "permissiondecision" in interpreter_stdout
            and "deny" in interpreter_stdout,
            "PreToolUse should deny interpreter payloads that directly target sensitive files.",
        )
        user_profile_ref = "$" + "env:USERPROFILE"
        private_path = f"{user_profile_ref}\\.codex\\{'auth' + '.json'}"
        nested_read_probe = run_compact_hook_sample(
            root,
            {
                "hook_event_name": "PreToolUse",
                "tool_name": "multi_tool_use.parallel",
                "tool_input": {
                    "tool_uses": [
                        {
                            "recipient_name": "functions.shell_command",
                            "parameters": {"command": f"Get-Content {private_path}"},
                        }
                    ]
                },
            },
        )
        nested_read_stdout = nested_read_probe.get("stdout_preview", "").lower()
        add_check(
            "pretooluse_blocks_nested_multitool_secret_reads",
            nested_read_probe.get("status") == "pass"
            and "permissiondecision" in nested_read_stdout
            and "deny" in nested_read_stdout,
            "PreToolUse should inspect nested multi_tool_use calls before allowing the wrapper call.",
        )
        safe_reference_probe = run_hook_sample(root, "rg auth.json docs")
        safe_reference_stdout = safe_reference_probe.get("stdout_preview", "").lower()
        add_check(
            "pretooluse_allows_safe_secret_reference_search",
            safe_reference_probe.get("status") == "pass"
            and "permissiondecision" in safe_reference_stdout
            and "allow" in safe_reference_stdout,
            "PreToolUse should allow safe reference searches that mention sensitive filenames without targeting the sensitive file path.",
        )
        unsafe_search_probe = run_hook_sample(
            root, "rg " + "to" + "ken" + " " + "to" + "ken" + ".txt"
        )
        unsafe_search_stdout = unsafe_search_probe.get("stdout_preview", "").lower()
        extra_target_search_probe = run_hook_sample(
            root, "rg " + "auth" + ".json docs " + "auth" + ".json"
        )
        extra_target_search_stdout = extra_target_search_probe.get(
            "stdout_preview", ""
        ).lower()
        select_unsafe_probe = run_hook_sample(
            root,
            "Select-String -Pattern "
            + "to"
            + "ken"
            + " -Path "
            + "to"
            + "ken"
            + ".txt",
        )
        select_unsafe_stdout = select_unsafe_probe.get("stdout_preview", "").lower()
        add_check(
            "pretooluse_blocks_search_secret_file_targets",
            unsafe_search_probe.get("status") == "pass"
            and "deny" in unsafe_search_stdout
            and extra_target_search_probe.get("status") == "pass"
            and "deny" in extra_target_search_stdout
            and select_unsafe_probe.get("status") == "pass"
            and "deny" in select_unsafe_stdout,
            "PreToolUse safe-reference exceptions should not allow secret-like search targets.",
        )
        select_string_blocked_probe = run_hook_sample(
            root, "Select-String -Pattern . -Path $env:USERPROFILE\\.codex\\auth.json"
        )
        select_string_blocked_stdout = select_string_blocked_probe.get(
            "stdout_preview", ""
        ).lower()
        add_check(
            "pretooluse_blocks_select_string_secret_path",
            select_string_blocked_probe.get("status") == "pass"
            and "permissiondecision" in select_string_blocked_stdout
            and "deny" in select_string_blocked_stdout,
            "PreToolUse should deny Select-String when the path target is a credential file.",
        )
        select_string_positional_probe = run_hook_sample(
            root, "Select-String -Pattern . $env:USERPROFILE\\.codex\\auth.json"
        )
        select_string_positional_stdout = select_string_positional_probe.get(
            "stdout_preview", ""
        ).lower()
        add_check(
            "pretooluse_blocks_select_string_positional_secret_path",
            select_string_positional_probe.get("status") == "pass"
            and "permissiondecision" in select_string_positional_stdout
            and "deny" in select_string_positional_stdout,
            "PreToolUse should deny Select-String when a positional path target is a credential file.",
        )
        select_string_reference_probe = run_hook_sample(
            root, "Select-String -Pattern auth.json -Path docs"
        )
        select_string_reference_stdout = select_string_reference_probe.get(
            "stdout_preview", ""
        ).lower()
        add_check(
            "pretooluse_allows_select_string_reference_search",
            select_string_reference_probe.get("status") == "pass"
            and "permissiondecision" in select_string_reference_stdout
            and "allow" in select_string_reference_stdout,
            "PreToolUse should allow Select-String reference searches when the target path is not sensitive.",
        )
        destructive_order_probe = run_hook_sample(
            root, "Remove-Item $env:USERPROFILE\\.codex\\tmp -Recurse -Force"
        )
        destructive_order_stdout = destructive_order_probe.get(
            "stdout_preview", ""
        ).lower()
        destructive_home_probe = run_hook_sample(
            root, "Remove-Item $HOME\\.codex\\tmp -Recurse -Force"
        )
        destructive_home_stdout = destructive_home_probe.get(
            "stdout_preview", ""
        ).lower()
        destructive_pwd_probe = run_hook_sample(
            root, "Remove-Item $PWD -Recurse -Force"
        )
        destructive_pwd_stdout = destructive_pwd_probe.get("stdout_preview", "").lower()
        destructive_drive_root_probe = run_hook_sample(
            root, "Remove-Item \\ -Recurse -Force"
        )
        destructive_drive_root_stdout = destructive_drive_root_probe.get(
            "stdout_preview", ""
        ).lower()
        destructive_forward_root_probe = run_hook_sample(
            root, "Remove-Item / -Recurse -Force"
        )
        destructive_forward_root_stdout = destructive_forward_root_probe.get(
            "stdout_preview", ""
        ).lower()
        forward_drive_target = (Path.home() / ".codex" / "tmp").as_posix()
        destructive_colon_recurse_probe = run_hook_sample(
            root, f"Remove-Item {forward_drive_target} -Recurse:$true -Force"
        )
        destructive_colon_recurse_stdout = destructive_colon_recurse_probe.get(
            "stdout_preview", ""
        ).lower()
        nonrecursive_force_probe = run_hook_sample(
            root, "Remove-Item .\\some-file.tmp -Force"
        )
        nonrecursive_force_stdout = nonrecursive_force_probe.get(
            "stdout_preview", ""
        ).lower()
        add_check(
            "pretooluse_blocks_destructive_any_argument_order",
            destructive_order_probe.get("status") == "pass"
            and "permissiondecision" in destructive_order_stdout
            and "deny" in destructive_order_stdout,
            "PreToolUse should deny broad recursive destructive operations regardless of argument order.",
        )
        add_check(
            "pretooluse_blocks_destructive_powershell_home_pwd",
            destructive_home_probe.get("status") == "pass"
            and "deny" in destructive_home_stdout
            and destructive_pwd_probe.get("status") == "pass"
            and "deny" in destructive_pwd_stdout
            and destructive_drive_root_probe.get("status") == "pass"
            and "deny" in destructive_drive_root_stdout
            and destructive_forward_root_probe.get("status") == "pass"
            and "deny" in destructive_forward_root_stdout,
            "PreToolUse should treat $HOME, $PWD, and current-drive root aliases as broad destructive targets.",
        )
        add_check(
            "pretooluse_blocks_forward_drive_recurse_true_delete",
            destructive_colon_recurse_probe.get("status") == "pass"
            and "permissiondecision" in destructive_colon_recurse_stdout
            and "deny" in destructive_colon_recurse_stdout,
            "PreToolUse should deny broad Windows paths written with forward slashes and -Recurse:$true.",
        )
        add_check(
            "pretooluse_allows_nonrecursive_remove_item_force",
            nonrecursive_force_probe.get("status") == "pass"
            and "permissiondecision" in nonrecursive_force_stdout
            and "allow" in nonrecursive_force_stdout,
            "PreToolUse should not treat ordinary nonrecursive Remove-Item -Force as a broad recursive delete.",
        )
        relative_destructive_probe = run_hook_sample(
            root, "Remove-Item . -Recurse -Force"
        )
        relative_destructive_stdout = relative_destructive_probe.get(
            "stdout_preview", ""
        ).lower()
        relative_recurse_abbrev_probe = run_hook_sample(
            root, "Remove-Item . -rec -Force"
        )
        relative_recurse_abbrev_stdout = relative_recurse_abbrev_probe.get(
            "stdout_preview", ""
        ).lower()
        relative_recurse_partial_probe = run_hook_sample(
            root, "Remove-Item . -recu -Force"
        )
        relative_recurse_partial_stdout = relative_recurse_partial_probe.get(
            "stdout_preview", ""
        ).lower()
        invoke_expression_relative_probe = run_hook_sample(
            root, "iex 'Remove-Item . -Recurse -Force'"
        )
        invoke_expression_relative_stdout = invoke_expression_relative_probe.get(
            "stdout_preview", ""
        ).lower()
        invoke_expression_variable_relative_probe = run_hook_sample(
            root, "$x='Remove-Item . -Recurse -Force'; Invoke-Expression $x"
        )
        invoke_expression_variable_relative_stdout = (
            invoke_expression_variable_relative_probe.get("stdout_preview", "").lower()
        )
        rm_relative_probe = run_hook_sample(root, "rm -rf .")
        rm_relative_stdout = rm_relative_probe.get("stdout_preview", "").lower()
        ri_relative_probe = run_hook_sample(root, "ri . -r -Force")
        ri_relative_stdout = ri_relative_probe.get("stdout_preview", "").lower()
        rd_relative_probe = run_hook_sample(root, "cmd /c rd /s .")
        rd_relative_stdout = rd_relative_probe.get("stdout_preview", "").lower()
        del_relative_probe = run_hook_sample(root, "cmd /c del /s .")
        del_relative_stdout = del_relative_probe.get("stdout_preview", "").lower()
        add_check(
            "pretooluse_blocks_relative_recursive_delete",
            relative_destructive_probe.get("status") == "pass"
            and "deny" in relative_destructive_stdout
            and relative_recurse_abbrev_probe.get("status") == "pass"
            and "deny" in relative_recurse_abbrev_stdout
            and relative_recurse_partial_probe.get("status") == "pass"
            and "deny" in relative_recurse_partial_stdout
            and invoke_expression_relative_probe.get("status") == "pass"
            and "deny" in invoke_expression_relative_stdout
            and invoke_expression_variable_relative_probe.get("status") == "pass"
            and "deny" in invoke_expression_variable_relative_stdout
            and rm_relative_probe.get("status") == "pass"
            and "deny" in rm_relative_stdout
            and ri_relative_probe.get("status") == "pass"
            and "deny" in ri_relative_stdout
            and rd_relative_probe.get("status") == "pass"
            and "deny" in rd_relative_stdout
            and del_relative_probe.get("status") == "pass"
            and "deny" in del_relative_stdout,
            "PreToolUse should deny recursive deletes of current or parent relative roots, including common Windows aliases.",
        )
        nested_destructive_probe = run_compact_hook_sample(
            root,
            {
                "hook_event_name": "PreToolUse",
                "tool_name": "multi_tool_use.parallel",
                "tool_input": {
                    "tool_uses": [
                        {
                            "recipient_name": "functions.shell_command",
                            "parameters": {
                                "command": "Remove-Item $HOME\\.codex\\tmp -Recurse -Force"
                            },
                        }
                    ]
                },
            },
        )
        nested_destructive_stdout = nested_destructive_probe.get(
            "stdout_preview", ""
        ).lower()
        add_check(
            "pretooluse_blocks_nested_multitool_destructive",
            nested_destructive_probe.get("status") == "pass"
            and "permissiondecision" in nested_destructive_stdout
            and "deny" in nested_destructive_stdout,
            "PreToolUse should inspect nested multi_tool_use destructive shell commands before allowing the wrapper call.",
        )
        post_probe = run_post_tool_hook_sample(
            root, "functions.shell_command", "Write-Output compact-hook-smoke"
        )
        stop_probe = run_stop_hook_sample(root, "compact hook smoke final")
        post_stdout = post_probe.get("stdout_preview", "").lower()
        stop_stdout = stop_probe.get("stdout_preview", "").lower()
        add_check(
            "posttool_and_stop_are_record_only",
            post_probe.get("status") == "pass"
            and stop_probe.get("status") == "pass"
            and "permissiondecision" not in post_stdout
            and "permissiondecision" not in stop_stdout
            and "deny" not in post_stdout
            and "deny" not in stop_stdout
            and '"decision":"block"' not in post_stdout
            and '"decision":"block"' not in stop_stdout
            and '"continue":false' not in post_stdout
            and '"continue":false' not in stop_stdout,
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
            if not original_state_dir_exists:
                try:
                    ledger_path.parent.rmdir()
                except OSError:
                    pass
    restored_ledger_exists = ledger_path.exists()
    restored_ledger_bytes = ledger_path.read_bytes() if restored_ledger_exists else None
    add_check(
        "hook_policy_smoke_restores_live_ledger",
        restored_ledger_exists == original_ledger_exists
        and restored_ledger_bytes == original_ledger_bytes,
        "Synthetic compact hook samples must not leave ledger mutations behind.",
    )
    return write_smoke_report(root, "hook-policy-smoke", checks)


def check_terms_file(
    root: Path, relative_path: str, terms: list[str]
) -> tuple[bool, str]:
    path = root / relative_path
    if not path.exists():
        return False, f"missing file: {relative_path}"
    text = read_text(path).lower()
    missing = [term for term in terms if term.lower() not in text]
    if missing:
        return False, f"{relative_path} missing terms: {', '.join(missing)}"
    return True, f"{relative_path} contains required terms"


def write_smoke_report(
    root: Path, name: str, checks: list[dict[str, Any]]
) -> dict[str, Any]:
    status = "pass" if all(item["status"] == "pass" for item in checks) else "fail"
    report = {"generated_at": utc_now(), "status": status, "checks": checks}
    write_json(root / "reports" / f"{name}.latest.json", report)
    return report


def check_adversarial_review_integration_smoke(root: Path) -> dict[str, Any]:
    checks: list[dict[str, Any]] = []

    def add_file_check(name: str, relative_path: str, terms: list[str]) -> None:
        passed, detail = check_terms_file(root, relative_path, terms)
        checks.append(
            {"name": name, "status": "pass" if passed else "fail", "detail": detail}
        )

    add_file_check(
        "skill_semantics",
        "skills/clean-all-slop/SKILL.md",
        ["audit mode", "read-only", "legacy residue", "unsupported success", "clean"],
    )
    add_file_check(
        "goal_gate_mapping",
        "maintenance/GOAL_INTEGRITY_GATE.md",
        [
            "clean",
            "c0",
            "p3",
            "c1",
            "p2",
            "c2",
            "p1",
            "c3",
            "p0",
            "c4",
            "clean is not completion authority",
            "immediately previous",
        ],
    )
    add_file_check(
        "watcher_template_lens",
        "maintenance/templates/WATCHER_REPORT.md",
        [
            "adversarial review verdict",
            "fix required",
            "clean",
            "defect classes checked",
            "pm merge recommendation",
        ],
    )
    add_file_check(
        "pre_ship_template_lens",
        "maintenance/templates/PRE_SHIP_AUDIT_CONTEXT.md",
        [
            "immediately previous turn to review",
            "required review lens",
            "clean-all-slop",
        ],
    )
    return write_smoke_report(root, "adversarial-review-integration-smoke", checks)


def check_worker_watcher_normalized_handoff_smoke(root: Path) -> dict[str, Any]:
    checks: list[dict[str, Any]] = []

    def add_file_check(name: str, relative_path: str, terms: list[str]) -> None:
        passed, detail = check_terms_file(root, relative_path, terms)
        checks.append(
            {"name": name, "status": "pass" if passed else "fail", "detail": detail}
        )

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
        [
            "clean-all-slop",
            "read-only",
            "do not repair",
            "watcher_report",
            "pm merge recommendation",
        ],
    )
    for template in [
        "maintenance/templates/NORMALIZED_WORKER_PACKET.md",
        "maintenance/templates/WATCHER_REPORT.md",
        "maintenance/templates/WATCHER_NOT_USED.md",
        "maintenance/templates/PM_MERGE_DECISION.md",
    ]:
        add_file_check(
            f"template:{Path(template).stem}",
            template,
            ["# " + Path(template).stem.upper()],
        )
    add_file_check(
        "delegation_charter_extension",
        "maintenance/SUBAGENT_DELEGATION_CHARTER.md",
        [
            "worker-watcher normalized handoff",
            "normalized_worker_packet",
            "watcher_not_used",
            "pm_merge_decision",
        ],
    )
    return write_smoke_report(root, "worker-watcher-normalized-handoff-smoke", checks)


def check_goal_integrity_gate_smoke(root: Path) -> dict[str, Any]:
    checks: list[dict[str, Any]] = []

    def add_file_check(name: str, relative_path: str, terms: list[str]) -> None:
        passed, detail = check_terms_file(root, relative_path, terms)
        checks.append(
            {"name": name, "status": "pass" if passed else "fail", "detail": detail}
        )

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
        [
            "immediately previous turn to review",
            "required review lens",
            "clean-all-slop",
            "reset to define",
        ],
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
        [
            "midpoint and pre-ship",
            "c0-c4",
            "normalized worker packets",
            "watcher_not_used",
        ],
    )
    return write_smoke_report(root, "goal-integrity-gate-smoke", checks)
