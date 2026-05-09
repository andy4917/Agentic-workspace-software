from __future__ import annotations

import argparse
import json
from collections import deque
from pathlib import Path
from typing import Any, Iterable


RUNTIME_DIR = Path("Settings") / "Codex_App_RUNTIME"
REPORT_DIR = Path("Maintenance") / "reports"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="python -m Tools.harness_py",
        description="Read runtime ledgers and reports, then print concise summaries.",
    )
    parser.add_argument(
        "command",
        nargs="?",
        choices=("summary", "ledgers", "reports"),
        default="summary",
    )
    parser.add_argument("--root", type=Path, default=find_repo_root())
    parser.add_argument("--tail", type=int, default=5)
    args = parser.parse_args(argv)

    root = args.root.resolve()
    if args.command == "summary":
        print_summary(root, args.tail)
    elif args.command == "ledgers":
        print_ledgers(root, args.tail)
    else:
        print_reports(root)
    return 0


def find_repo_root() -> Path:
    here = Path.cwd()
    for candidate in (here, *here.parents):
        if (candidate / "Settings" / "Codex_App_RUNTIME").is_dir():
            return candidate
    return here


def read_json(path: Path) -> dict[str, Any]:
    if not path.is_file():
        return {}
    try:
        value = json.loads(path.read_text(encoding="utf-8-sig"))
    except json.JSONDecodeError:
        return {"_error": "invalid_json"}
    return value if isinstance(value, dict) else {"value": value}


def iter_jsonl_tail(path: Path, limit: int) -> tuple[int, int, list[dict[str, Any]]]:
    count = 0
    bad = 0
    tail: deque[dict[str, Any]] = deque(maxlen=max(limit, 0))
    if not path.is_file():
        return count, bad, []
    with path.open("r", encoding="utf-8-sig") as handle:
        for line in handle:
            if not line.strip():
                continue
            count += 1
            try:
                value = json.loads(line)
            except json.JSONDecodeError:
                bad += 1
                continue
            if isinstance(value, dict):
                tail.append(value)
    return count, bad, list(tail)


def print_summary(root: Path, tail: int) -> None:
    runtime = root / RUNTIME_DIR
    active = read_json(runtime / "active_contract.json")
    gate = read_json(runtime / "gate_issued_completion_receipt.json")
    completion = read_json(runtime / "completion_receipt.json")

    print("Runtime summary")
    print(f"root: {root}")
    print(f"active_state: {active.get('state', 'missing')}")
    print(f"turn_fingerprint: {active.get('turn_fingerprint', 'missing')}")
    print(f"gate: {gate.get('state', 'missing')} / {gate.get('decision', 'missing')}")
    print(f"gate_reason: {gate.get('reason', 'missing')}")
    print(f"completion_state: {completion.get('completion_state', 'missing')}")
    print(f"completion_blockers: {format_list(completion.get('blockers'))}")
    print()
    print_ledgers(root, tail)
    print()
    print_reports(root)


def print_ledgers(root: Path, tail: int) -> None:
    runtime = root / RUNTIME_DIR
    print("Ledger summary")
    if not runtime.is_dir():
        print(f"missing runtime folder: {runtime}")
        return
    ledgers = sorted(runtime.glob("*.jsonl"))
    if not ledgers:
        print("no jsonl ledgers found")
        return
    for path in ledgers:
        count, bad, recent = iter_jsonl_tail(path, tail)
        last = recent[-1] if recent else {}
        stamp = first_present(last, ("timestamp_utc", "created_at_utc", "reported_at_utc", "issued_at_utc", "generated_at_utc"))
        kind = first_present(last, ("record_type", "event_type", "route_id", "tool_name", "skill_id"))
        print(f"- {path.name}: records={count}; invalid={bad}; last={stamp or 'n/a'}; kind={kind or 'n/a'}")


def print_reports(root: Path) -> None:
    report_dir = root / REPORT_DIR
    print("Report summary")
    if not report_dir.is_dir():
        print(f"missing report folder: {report_dir}")
        return
    reports = sorted(report_dir.glob("*.md"))
    if not reports:
        print("no markdown reports found")
        return
    for path in reports:
        lines = path.read_text(encoding="utf-8-sig", errors="replace").splitlines()
        title = first_line(lines, "# ") or path.name
        status = first_prefix(lines, ("Verdict:", "Status:", "Authority:")) or "status: n/a"
        print(f"- {path.name}: {title}; {status}")


def first_present(item: dict[str, Any], keys: Iterable[str]) -> str:
    for key in keys:
        value = item.get(key)
        if value not in (None, ""):
            return str(value)
    return ""


def first_line(lines: Iterable[str], prefix: str) -> str:
    for line in lines:
        if line.startswith(prefix):
            return line[len(prefix):].strip()
    return ""


def first_prefix(lines: Iterable[str], prefixes: tuple[str, ...]) -> str:
    for line in lines:
        if line.startswith(prefixes):
            return line.strip()
    return ""


def format_list(value: Any) -> str:
    if isinstance(value, list):
        return ", ".join(str(item) for item in value) if value else "none"
    if value in (None, ""):
        return "none"
    return str(value)
