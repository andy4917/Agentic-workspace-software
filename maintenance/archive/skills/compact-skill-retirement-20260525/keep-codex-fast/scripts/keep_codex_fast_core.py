#!/usr/bin/env python3
"""Backup-first Codex local-state maintenance.

Default mode is report-only. Use --apply to archive/move/normalize.
"""

from __future__ import annotations

import argparse
import json
import os
import platform
import re
import shutil
import sqlite3
import subprocess
import sys
import time
import zipfile
from dataclasses import dataclass
from datetime import datetime, timedelta
from pathlib import Path

try:
    import tomllib
except ModuleNotFoundError:  # pragma: no cover - Python < 3.11 fallback.
    tomllib = None


THREAD_ID_RE = re.compile(
    r"([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})",
    re.I,
)
PROJECT_HEADER_RE = re.compile(r"^\[projects\.([\"'])(.+)\1\]\s*$")
TEMP_PROJECT_RE = re.compile(
    r"(\\AppData\\Local\\Temp\\|/AppData/Local/Temp/|\\Temp\\codex-|/Temp/codex-|\\Temp\\spark-|/Temp/spark-)",
    re.I,
)
DEFAULT_UNEXPECTED_APP_CONNECTORS = {"supabase", "hugging face"}
DEFAULT_UNEXPECTED_TOOL_NAMESPACES = {
    "mcp__codex_apps__supabase",
    "mcp__codex_apps__hugging_face",
}
DEFAULT_FORBIDDEN_ACTIVE_SOURCE_FRAGMENTS = [
    "\\.tmp\\",
    "\\tmp\\",
    "\\archived_sessions\\",
    "\\vendor_imports\\",
    "\\bundled-marketplaces\\",
    "\\plugins\\plugins\\",
    "\\wshobson-agents-scan\\",
    "\\quarantine\\",
    "\\quarantined\\",
    "\\Maintenance\\upstream\\",
]
TEXT_AUDIT_SUFFIXES = {
    ".json",
    ".jsonl",
    ".md",
    ".ps1",
    ".py",
    ".toml",
    ".txt",
    ".yaml",
    ".yml",
}
TEXT_AUDIT_EXCLUDED_DIRS = {
    ".git",
    ".tmp",
    "tmp",
    "sessions",
    "archived_sessions",
    "archived_worktrees",
    "archived_logs",
    "worktrees",
    "node_modules",
    "__pycache__",
    ".pytest_cache",
}
TEXT_AUDIT_EXCLUDED_RELS = {
    ("cache", "codex_apps_tools"),
    ("plugins", "cache"),
    ("plugins", "local-marketplaces"),
}


@dataclass
class SessionCandidate:
    size: int
    thread_id: str
    title: str
    source: Path
    relative: Path
    updated_at: int | None


def now_stamp() -> str:
    return datetime.now().strftime("%Y%m%d-%H%M%S")


def codex_home_from_args(value: str | None) -> Path:
    if value:
        return Path(value).expanduser().resolve()
    override = os.environ.get("CODEX_HOME")
    if override:
        return Path(override).expanduser().resolve()
    return Path.home() / ".codex"


def documents_backup_root() -> Path:
    docs = Path.home() / "Documents" / "Codex" / "codex-backups"
    if docs.parent.exists() or platform.system() == "Windows":
        return docs
    return Path.home() / ".codex" / "backups"


def size_bytes(path: Path) -> int:
    if not path.exists():
        return 0
    if path.is_file():
        return path.stat().st_size
    total = 0
    for item in path.rglob("*"):
        if item.is_file():
            try:
                total += item.stat().st_size
            except OSError:
                pass
    return total


def gb(value: int) -> str:
    return f"{value / 1024 / 1024 / 1024:.3f}"


def mb(value: int) -> str:
    return f"{value / 1024 / 1024:.1f}"


def report(line: str) -> None:
    print(line)


def norm_text_path(value: str | Path) -> str:
    return str(value).replace("/", "\\").lower()


def load_toml_config(codex_home: Path) -> dict:
    path = codex_home / "config.toml"
    if not path.exists():
        report("config_toml missing")
        return {}
    if tomllib is None:
        report("config_toml skipped_tomllib_unavailable")
        return {}
    try:
        data = tomllib.loads(path.read_text(encoding="utf-8-sig"))
        report("config_toml parsed")
        return data
    except Exception as exc:
        report(f"config_toml_parse_error {exc}")
        return {}


def contamination_policy(config: dict) -> dict:
    maintenance = config.get("maintenance", {}) if isinstance(config, dict) else {}
    policy = maintenance.get("contamination_prevention", {}) if isinstance(maintenance, dict) else {}
    return policy if isinstance(policy, dict) else {}


def naming_policy(config: dict) -> dict:
    maintenance = config.get("maintenance", {}) if isinstance(config, dict) else {}
    policy = maintenance.get("naming_convention", {}) if isinstance(maintenance, dict) else {}
    return policy if isinstance(policy, dict) else {}


def policy_list(policy: dict, key: str, default: list[str] | set[str]) -> list[str]:
    value = policy.get(key, default)
    if not isinstance(value, list):
        value = list(default)
    return [str(item) for item in value]


def path_has_fragment(path: str | Path, fragments: list[str]) -> bool:
    normalized = norm_text_path(path)
    return any(norm_text_path(fragment) in normalized for fragment in fragments)


def is_under_any_root(path: Path, roots: list[str]) -> bool:
    resolved = path.expanduser().resolve()
    for root in roots:
        try:
            resolved.relative_to(Path(root).expanduser().resolve())
            return True
        except Exception:
            continue
    return False
