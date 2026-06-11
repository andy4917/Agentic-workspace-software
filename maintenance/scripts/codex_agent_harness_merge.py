from __future__ import annotations

import argparse
import json
import os
import sys
import tomllib
from pathlib import Path
from typing import Any

from codex_agent_harness_base import *
from codex_agent_harness_lifecycle import audit_data, check_config, check_managed_files, cmd_apply, doctor_data, load_state
from codex_agent_harness_workflows import cmd_compact_summary, cmd_context, cmd_retrieve, write_verification_report


HOOK_MATCHER = "Bash|functions\\..*|multi_tool_use\\..*|multi_agent.*|tool_search\\..*|web\\..*|image_gen\\..*|codex_app\\..*|apply_patch|mcp__.*"


def compact_hook_fragment(hidden_hook_command: str) -> str:
    parts: list[str] = ["# Hook fragment. All enabled events call one deterministic runner.\n"]
    event_specs = [
        ("SessionStart", "startup|resume", 30),
        ("UserPromptSubmit", "", 30),
        ("PreToolUse", HOOK_MATCHER, 30),
        ("PostToolUse", HOOK_MATCHER, 30),
        ("Stop", "", 10),
    ]
    for event_name, matcher, timeout in event_specs:
        parts.append(f"[[hooks.{event_name}]]\n")
        if matcher:
            parts.append(f"matcher = {json.dumps(matcher)}\n")
        parts.append(f"[[hooks.{event_name}.hooks]]\n")
        parts.append('type = "command"\n')
        parts.append(f"command = '{hidden_hook_command}'\n")
        parts.append(f"commandWindows = '{hidden_hook_command}'\n")
        parts.append(f"timeout = {timeout}\n")
        parts.append('statusMessage = "compact scaffold hook"\n\n')
    return "".join(parts)


def resolve_pwsh_for_hook() -> Path:
    alias_stub = Path.home() / "AppData" / "Local" / "Microsoft" / "WindowsApps" / "pwsh.exe"
    program_files = Path(os.environ.get("ProgramFiles") or r"C:\Program Files")
    candidates: list[Path] = []
    windows_apps = program_files / "WindowsApps"
    if windows_apps.exists():
        candidates.extend(sorted(windows_apps.glob("Microsoft.PowerShell_*__8wekyb3d8bbwe/pwsh.exe"), reverse=True))
    candidates.append(program_files / "PowerShell" / "7" / "pwsh.exe")
    candidates.append(alias_stub)
    for candidate in candidates:
        if candidate.exists() and candidate != alias_stub:
            return candidate
    for candidate in candidates:
        if candidate.exists():
            return candidate
    return alias_stub


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
        merged_text = apply_toml_additions(read_text(target), additions, target_data)
        write_text(target, merged_text)
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
            'project_doc_fallback_filenames = ["CALIBRATION.md"]\n'
            "project_doc_max_bytes = 65536\n"
            "\n"
            "[features]\n"
            "plugins = true\n"
            "hooks = true\n"
            "goals = true\n"
            "memories = true\n"
            "multi_agent = true\n"
            "child_agents_md = true\n"
            "tool_search = true\n"
            "tool_suggest = true\n"
            "skill_mcp_dependency_install = true\n"
            "workspace_dependencies = true\n"
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
            'config_file = "agents/docs-researcher.toml"\n'
            "\n"
            "[agents.observer]\n"
            'description = "Independent watcher for worker handoff integrity, goal drift, evidence quality, and instruction compliance."\n'
            'config_file = "agents/observer.toml"\n'
            "\n"
            "[agents.calibration-verifier]\n"
            'description = "Checks whether a draft answer, diagnosis, or plan is sufficiently supported before acceptance."\n'
            'config_file = "agents/calibration-verifier.toml"\n',
        )
        write_text(
            root / "AGENTS.md",
            "# Test\n\n"
            "## Live Turn Calibration\n\n"
            "- Use CALIBRATION.md as the canonical live-turn calibration policy.\n"
            "- use role-prefixed nicknames with PM-* reserved for the main coordinator and EXP-*, REV-*, DOC-*, SEC-*, VAL-*, IMP-*, ENV-*, and OBS-* for subagents\n"
            "- require each subagent to state its own concrete goal\n"
            "- include Purpose, PM Context, Owned Surface, Expected Evidence, Anti-Reward-Hacking Rules, Exit Criteria, and Not Checked fields\n"
            "- require mid-report evidence for non-trivial delegated work\n"
            "- pm must continue useful non-overlapping work while agents run\n"
            "- subagent outputs are candidate evidence, not authority\n"
            "- reject unsupported success claims and close and replace agents that produce reward-hacked validation\n",
        )
        write_text(
            root / "CALIBRATION.md",
            "# Calibration\n\n"
            "Answer statuses: candidate, supported, inferred, uncertain, accepted, abstain.\n"
            "Claim evidence states: observed, derived, assumed, unchecked.\n"
            "## Falsifier-First\n\nCheck the strongest contradiction before accepting.\n"
            "## Completion Authority\n\nTests, tools, and reports are evidence only.\n",
        )
        write_text(root / ".gitignore", "auth.json\n.codex-global-state.json\n.codex-global-state.json.bak\n__pycache__/\n*.pyc\n")
        write_json(root / ".codex-global-state.json", {})
        hook_pwsh = resolve_pwsh_for_hook()
        hook_runner = Path.home() / ".codex" / "hooks" / "compact-codex-hook.ps1"
        hidden_hook_command = f"{hook_pwsh} -NoProfile -NonInteractive -WindowStyle Hidden -File {hook_runner}"
        hook_fragment = compact_hook_fragment(hidden_hook_command)
        write_text(root / "config.d" / "20-hooks.toml", hook_fragment)
        write_text(root / "config.toml", read_text(root / "config.toml") + "\n" + hook_fragment)
        write_text(root / "maintenance" / "MCP_RUNTIME_STATUS.md", "# MCP\n")
        write_text(
            root / "hooks" / "compact-codex-hook.ps1",
            "$ErrorActionPreference = 'Stop'\n"
            "$ledger = 'hook-ledger.jsonl'\n"
            "$runner = \"compact-codex-hook\"\n"
            "# compact hook active\n"
            "function Ensure-RuntimeCleanupWatch { return $true }\n"
            "# UserPromptSubmit PreToolUse treat claims as candidate until direct evidence supports them\n",
        )
        write_text(root / "evals" / "calibration-eval.yaml", "checks:\n  - confident_wrong\n  - unsupported_material_claim\n")
        for name in [
            "codex_agent_harness.py",
            "codex_agent_harness_base.py",
            "codex_agent_harness_calibration.py",
            "codex_agent_harness_lifecycle.py",
            "codex_agent_harness_merge.py",
            "codex_agent_harness_smoke.py",
            "codex_agent_harness_status.py",
            "codex_agent_harness_workflows.py",
            "worker_watcher_templates.py",
        ]:
            write_text(root / "maintenance" / "scripts" / name, "# self-test harness source placeholder\n")
        ensure_dir(root / "toolchains" / "shims")
        write_json(
            root / "reports" / "global-scan.latest.json",
            {
                "content_redacted": True,
                "active_hit_count": 0,
                "scan_error_count": 0,
                "harness_digest": harness_source_digest(root),
            },
        )
        write_text(root / "reports" / "eval-results.jsonl", "")
        ns = argparse.Namespace(root=str(root), profile="developer", module=None)
        cmd_apply(ns)
        state = load_state(root)
        if not any(op.get("remove_on_uninstall") is True for op in state.get("applied_operations", [])):
            print("uninstall ownership missing in self-test", file=sys.stderr)
            return 1
        stale_skill = root / "skills" / "dont-even-try" / "SKILL.md"
        write_text(stale_skill, "# Retired skill\n")
        stale_digest = sha256_file(stale_skill)
        state["applied_operations"].append(
            {
                "path": "skills/dont-even-try/SKILL.md",
                "action": "unchanged",
                "digest": stale_digest,
                "owner": OWNER,
                "managed": True,
                "remove_on_uninstall": False,
            }
        )
        write_json(install_state_path(root), state)
        write_text(root / "agents" / "explorer.toml", "drifted = true\n")
        cmd_apply(ns)
        if stale_skill.exists() or stale_skill.parent.exists():
            print("retired managed skill residue was not removed in self-test", file=sys.stderr)
            return 1
        write_json(
            root / "reports" / "global-scan.latest.json",
            {
                "content_redacted": True,
                "active_hit_count": 0,
                "scan_error_count": 0,
                "harness_digest": harness_source_digest(root),
            },
        )
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
        cmd_context(argparse.Namespace(root=str(root)))
        retrieve_ns = argparse.Namespace(root=str(root), query="codex harness verification workflow", limit=5)
        if cmd_retrieve(retrieve_ns) != 0:
            print("retrieve failed in self-test", file=sys.stderr)
            return 1
        compact_ns = argparse.Namespace(
            root=str(root),
            goal="self-test compact summary",
            constraints=None,
            current_plan=None,
            completed_work="self-test generated required harness evidence",
            in_progress_work=None,
            blockers=None,
            relevant_files=None,
            commands_run=None,
            test_results="self-test",
            next_steps="audit",
            risks="temporary root only",
        )
        cmd_compact_summary(compact_ns)
        verification_checks = [
            {"name": "self_test", "status": "pass", "exit_code": 0},
            {"name": "repair_dry_run", "status": "pass", "exit_code": 0},
            {"name": "uninstall_dry_run", "status": "pass", "exit_code": 0},
        ]
        if command_exists("pwsh"):
            verification_checks.append({"name": "pwsh_wrapper_doctor", "status": "pass", "exit_code": 0})
        if command_exists("powershell.exe"):
            verification_checks.append({"name": "windows_powershell_wrapper_doctor", "status": "pass", "exit_code": 0})
        write_verification_report(root, {"generated_at": utc_now(), "status": "pass", "checks": verification_checks})
        append_trajectory(root, "self-test trajectory", "pass", verification_checks)
        append_jsonl(
            root / "reports" / "benchmark-results.jsonl",
            {
                "timestamp": utc_now(),
                "benchmark_id": "self-test",
                "status": "pass",
                "harness_digest": harness_source_digest(root),
                "success_rate": 1.0,
                "error_count": 0,
                "checks": verification_checks,
            },
        )
        if audit_data(root)["status"] != "pass":
            print("audit failed in self-test", file=sys.stderr)
            return 1
    print("self-test pass")
    return 0
