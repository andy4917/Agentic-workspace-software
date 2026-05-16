from __future__ import annotations

import argparse
import csv
import json
import os
import re
import subprocess
import sys
from pathlib import Path

CHROME_PROCESS_NAMES_BY_PLATFORM = {
    "darwin": {"Google Chrome", "Google Chrome Helper"},
    "win32": {"chrome.exe"},
}
MACOS_CHROME_APP_PATH_FRAGMENT = "/Google Chrome.app/Contents/"
MACOS_CHROME_SINGLETON_LOCK_PATH = (
    "Library",
    "Application Support",
    "Google",
    "Chrome",
    "SingletonLock",
)


def format_command_error(command: str, args: list[str], error: Exception) -> str:
    command_display = " ".join([command, *args])
    details = [str(error)]
    return f"Failed to run {command_display}: {'; '.join(details)}"


def run_command(command: str, args: list[str]) -> str:
    try:
        return subprocess.run(
            [command, *args],
            check=True,
            encoding="utf-8",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        ).stdout.strip()
    except Exception as error:
        raise RuntimeError(format_command_error(command, args, error)) from error


def strip_command_arguments(command: str) -> str:
    return re.sub(r"\s--.*$", "", command.strip())


def chrome_process_name_for_command(command: str) -> str:
    executable = strip_command_arguments(command)
    process_name = Path(executable).name
    if sys.platform == "darwin" and MACOS_CHROME_APP_PATH_FRAGMENT in executable:
        if process_name == "Google Chrome" or process_name.startswith(
            "Google Chrome Helper"
        ):
            return process_name
    return process_name


def parse_process_list(output: str, process_names: set[str]) -> list[dict[str, object]]:
    if not output:
        return []
    processes: list[dict[str, object]] = []
    for line in output.splitlines():
        match = re.match(r"^\s*(\d+)\s+(.+?)\s*$", line)
        if not match:
            continue
        pid, command = match.groups()
        process_name = chrome_process_name_for_command(command)
        if process_name not in process_names:
            continue
        processes.append(
            {
                "pid": int(pid),
                "process_name": process_name,
                "command": strip_command_arguments(command),
            }
        )
    return processes


def parse_macos_application_process_list(output: str) -> list[dict[str, object]]:
    processes = parse_process_list(output, CHROME_PROCESS_NAMES_BY_PLATFORM["darwin"])
    return [
        chrome_process
        for chrome_process in processes
        if MACOS_CHROME_APP_PATH_FRAGMENT in str(chrome_process["command"])
    ]


def parse_windows_task_list(output: str) -> list[dict[str, object]]:
    if not output:
        return []
    processes: list[dict[str, object]] = []
    for row in csv.reader(output.splitlines()):
        if len(row) < 2 or row[0].lower() != "chrome.exe":
            continue
        processes.append(
            {"pid": int(row[1]), "process_name": row[0], "command": row[0]}
        )
    return processes


def get_macos_chrome_singleton_process() -> dict[str, object] | None:
    home = os.environ.get("HOME")
    if not home:
        return None
    singleton_path = Path(home).joinpath(*MACOS_CHROME_SINGLETON_LOCK_PATH)
    try:
        singleton_lock_target = os.readlink(singleton_path)
    except OSError:
        return None
    pid_match = re.search(r"-(\d+)$", singleton_lock_target)
    if not pid_match:
        return None
    pid = int(pid_match.group(1))
    if pid <= 0:
        return None
    try:
        os.kill(pid, 0)
    except PermissionError:
        pass
    except OSError:
        return None
    return {"pid": pid, "process_name": "Google Chrome", "command": "Google Chrome"}


def find_running_chrome_processes() -> list[dict[str, object]]:
    process_names = CHROME_PROCESS_NAMES_BY_PLATFORM.get(sys.platform, {"chrome"})
    if sys.platform == "win32":
        return parse_windows_task_list(
            run_command(
                "tasklist",
                ["/fo", "csv", "/nh", "/fi", "imagename eq chrome.exe"],
            )
        )

    singleton_process = (
        get_macos_chrome_singleton_process() if sys.platform == "darwin" else None
    )
    try:
        process_list = run_command("ps", ["-A", "-o", "pid=", "-o", "comm="])
    except RuntimeError:
        if singleton_process is not None:
            return [singleton_process]
        raise

    processes = parse_process_list(process_list, process_names)
    if processes or sys.platform != "darwin":
        return processes

    try:
        return parse_macos_application_process_list(
            run_command("ps", ["-A", "-ww", "-o", "pid=", "-o", "command="])
        )
    except RuntimeError:
        if singleton_process is not None:
            return [singleton_process]
        raise


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="scripts/chrome_is_running.py",
        description="Detect whether Google Chrome is currently running.",
    )
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--json", action="store_true")
    return parser.parse_args(argv)


def print_text_report(result: dict[str, object], check: bool) -> None:
    if check:
        print("Google Chrome running check")
        print(f"status: {'ok' if result['running'] else 'not running'}")
        print("")
    print(f"Google Chrome running: {'yes' if result['running'] else 'no'}")
    for chrome_process in result["processes"]:
        print(f"  - pid: {chrome_process['pid']}")
        print(f"    process: {chrome_process['process_name']}")


def main(argv: list[str] | None = None) -> int:
    try:
        args = parse_args(sys.argv[1:] if argv is None else argv)
        processes = find_running_chrome_processes()
        result = {
            "platform": sys.platform,
            "running": len(processes) > 0,
            "processes": processes,
        }
        if args.json:
            print(json.dumps(result, indent=2))
        else:
            print_text_report(result, args.check)
        return 1 if args.check and not result["running"] else 0
    except SystemExit:
        raise
    except Exception as error:
        print(str(error), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
