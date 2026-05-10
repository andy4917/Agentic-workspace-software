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


def inspect_marketplace_sources(codex_home: Path, config: dict, policy: dict) -> None:
    marketplaces = config.get("marketplaces", {}) if isinstance(config, dict) else {}
    if not isinstance(marketplaces, dict):
        report("marketplace_sources 0")
        return

    allowed_roots = policy_list(policy, "allowed_marketplace_source_roots", [])
    forbidden = policy_list(
        policy,
        "forbidden_active_source_fragments",
        DEFAULT_FORBIDDEN_ACTIVE_SOURCE_FRAGMENTS,
    )
    source_count = 0
    bad_count = 0
    for marketplace_id, value in sorted(marketplaces.items()):
        if not isinstance(value, dict) or not value.get("source"):
            continue
        source_count += 1
        source = Path(str(value["source"]))
        exists = source.exists()
        forbidden_hit = path_has_fragment(source, forbidden)
        allowed_hit = not allowed_roots or is_under_any_root(source, allowed_roots)
        status = "ok" if exists and not forbidden_hit and allowed_hit else "needs_attention"
        if status != "ok":
            bad_count += 1
        report(f"marketplace_source {marketplace_id} {status} exists={int(exists)} allowed={int(allowed_hit)} forbidden={int(forbidden_hit)} {source}")
    report(f"marketplace_sources {source_count}")
    report(f"marketplace_source_issues {bad_count}")


def load_app_tool_cache(path: Path) -> list[dict]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        report(f"codex_apps_tools_cache_parse_error {path.name} {exc}")
        return []
    tools = data.get("tools", []) if isinstance(data, dict) else []
    return [tool for tool in tools if isinstance(tool, dict)]


def archive_unexpected_app_tool_caches(
    files: list[Path],
    codex_home: Path,
    backup_root: Path,
    stamp: str,
    apply: bool,
) -> None:
    if not files:
        return
    report(f"codex_apps_tools_unexpected_cache_files {len(files)}")
    if not apply:
        return

    archive_root = codex_home / "archived_app_tool_caches" / f"keep-codex-fast-{stamp}"
    manifest = backup_root / "moved-app-tool-caches.jsonl"
    archive_root.mkdir(parents=True, exist_ok=True)
    with manifest.open("w", encoding="utf-8") as handle:
        for source in files:
            dest = archive_root / source.name
            shutil.move(str(source), str(dest))
            handle.write(json.dumps({"from": str(source), "to": str(dest)}, ensure_ascii=False) + "\n")
    report(f"codex_apps_tools_archive_root {archive_root}")
    report(f"codex_apps_tools_manifest {manifest}")


def inspect_codex_apps_tools_cache(
    codex_home: Path,
    policy: dict,
    backup_root: Path,
    stamp: str,
    apply: bool,
) -> None:
    root = codex_home / "cache" / "codex_apps_tools"
    files = sorted(root.glob("*.json")) if root.exists() else []
    report(f"codex_apps_tools_cache_files {len(files)}")
    if not files:
        return

    expected = {item.lower() for item in policy_list(policy, "expected_app_connectors", [])}
    unexpected = {
        item.lower()
        for item in policy_list(policy, "unexpected_app_connectors", DEFAULT_UNEXPECTED_APP_CONNECTORS)
    }
    unexpected_namespaces = {
        item.lower()
        for item in policy_list(
            policy,
            "unexpected_app_tool_namespaces",
            DEFAULT_UNEXPECTED_TOOL_NAMESPACES,
        )
    }
    connector_counts: dict[str, int] = {}
    namespace_counts: dict[str, int] = {}
    unexpected_files: set[Path] = set()
    for path in files:
        tools = load_app_tool_cache(path)
        for tool in tools:
            connector = str(tool.get("connector_name") or "")
            namespace = str(tool.get("tool_namespace") or "")
            connector_counts[connector] = connector_counts.get(connector, 0) + 1
            namespace_counts[namespace] = namespace_counts.get(namespace, 0) + 1
            connector_key = connector.lower()
            namespace_key = namespace.lower()
            if connector_key in unexpected or namespace_key in unexpected_namespaces:
                unexpected_files.add(path)
            if expected and connector_key and connector_key not in expected:
                unexpected_files.add(path)

    for connector, count in sorted(connector_counts.items(), key=lambda item: item[0].lower()):
        report(f"codex_apps_tools_connector {connector or '<missing>'} {count}")
    for namespace, count in sorted(namespace_counts.items(), key=lambda item: item[0].lower()):
        report(f"codex_apps_tools_namespace {namespace or '<missing>'} {count}")
    archive_unexpected_app_tool_caches(
        sorted(unexpected_files),
        codex_home,
        backup_root,
        stamp,
        apply,
    )
    if not unexpected_files:
        report("codex_apps_tools_unexpected_cache_files 0")


def should_skip_audit_dir(path: Path, codex_home: Path) -> bool:
    if path.name in TEXT_AUDIT_EXCLUDED_DIRS:
        return True
    try:
        rel = path.relative_to(codex_home)
    except ValueError:
        return False
    parts = tuple(rel.parts)
    return any(parts[: len(prefix)] == prefix for prefix in TEXT_AUDIT_EXCLUDED_RELS)


def iter_audit_text_files(root: Path, codex_home: Path):
    if not root.exists():
        return
    for path in root.rglob("*"):
        if path.is_dir():
            continue
        if path.name == "config.toml" and path.parent == codex_home:
            continue
        if path.suffix.lower() not in TEXT_AUDIT_SUFFIXES:
            continue
        try:
            if path.stat().st_size > 2 * 1024 * 1024:
                continue
        except OSError:
            continue
        yield path


def inspect_deleted_path_references(codex_home: Path) -> None:
    roots = [
        codex_home / "hooks",
        codex_home / "Maintenance",
        codex_home / "skills" / "keep-codex-fast",
    ]
    direct_files = [
        path
        for path in codex_home.iterdir()
        if path.is_file() and path.suffix.lower() in TEXT_AUDIT_SUFFIXES and path.name != "config.toml"
    ]
    stale_roots = [
        codex_home / ".tmp",
        codex_home / "tmp",
        codex_home / "vendor_imports",
        codex_home / "wshobson-agents-scan",
        codex_home / "plugins" / "plugins",
    ]
    needles = [norm_text_path(path) for path in stale_roots]
    hits: list[str] = []

    for path in direct_files:
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except Exception:
            continue
        normalized = norm_text_path(text)
        if any(needle in normalized for needle in needles):
            hits.append(str(path))

    for root in roots:
        if not root.exists():
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            current = Path(dirpath)
            dirnames[:] = [
                name
                for name in dirnames
                if not should_skip_audit_dir(current / name, codex_home)
            ]
            for filename in filenames:
                path = current / filename
                if path.suffix.lower() not in TEXT_AUDIT_SUFFIXES:
                    continue
                try:
                    if path.stat().st_size > 2 * 1024 * 1024:
                        continue
                    text = path.read_text(encoding="utf-8", errors="ignore")
                except Exception:
                    continue
                normalized = norm_text_path(text)
                if any(needle in normalized for needle in needles):
                    hits.append(str(path))

    report(f"deleted_temp_path_references {len(hits)}")
    for hit in hits[:10]:
        report(f"deleted_temp_path_reference {hit}")


def inspect_nested_git_repositories(codex_home: Path) -> None:
    repos = sorted(path.parent for path in codex_home.rglob(".git") if path.is_dir())
    report(f"nested_git_repositories {len(repos)}")
    for repo in repos[:25]:
        dirty = "unknown"
        try:
            proc = subprocess.run(
                ["git", "-C", str(repo), "status", "--porcelain"],
                text=True,
                capture_output=True,
                timeout=10,
                check=False,
            )
            if proc.returncode == 0:
                dirty = str(len([line for line in proc.stdout.splitlines() if line.strip()]))
        except Exception:
            pass
        report(f"nested_git_repository dirty={dirty} {repo}")


def inspect_same_name_nested_dirs(codex_home: Path) -> None:
    hits: list[Path] = []
    for dirpath, dirnames, _filenames in os.walk(codex_home):
        current = Path(dirpath)
        dirnames[:] = [
            name
            for name in dirnames
            if not should_skip_audit_dir(current / name, codex_home)
        ]
        if current == codex_home:
            continue
        parent = current.parent
        if current.name.lower() == parent.name.lower():
            hits.append(current)
    report(f"same_name_nested_directories {len(hits)}")
    for hit in hits[:10]:
        report(f"same_name_nested_directory {hit}")


def inspect_naming_convention(
    codex_home: Path,
    config: dict,
    backup_root: Path,
    stamp: str,
    apply: bool,
) -> None:
    policy = naming_policy(config)
    profile = str(policy.get("profile", "")) if policy else ""
    report(f"naming_convention {'present' if policy else 'missing'} {profile}".rstrip())
    if not policy:
        return

    transient_names = {item.lower() for item in policy_list(policy, "transient_root_names", [])}
    active_roots = policy_list(policy, "normal_active_source_roots", [])
    forbidden_fragments = policy_list(policy, "forbidden_active_source_name_fragments", [])

    transient_hits = []
    for child in codex_home.iterdir():
        if child.is_dir() and child.name.lower() in transient_names:
            transient_hits.append(child)
    report(f"naming_transient_root_hits {len(transient_hits)}")
    for hit in transient_hits[:10]:
        report(f"naming_transient_root_hit {hit}")
    if apply and transient_hits:
        archive_root = codex_home / "archived_transient_roots" / f"keep-codex-fast-{stamp}"
        manifest = backup_root / "moved-transient-roots.jsonl"
        archive_root.mkdir(parents=True, exist_ok=True)
        with manifest.open("w", encoding="utf-8") as handle:
            for source in transient_hits:
                source_resolved = source.resolve()
                if source_resolved.parent != codex_home.resolve():
                    report(f"naming_transient_root_archive_skipped_outside_root {source}")
                    continue
                dest = archive_root / source.name
                shutil.move(str(source), str(dest))
                handle.write(json.dumps({"from": str(source), "to": str(dest)}, ensure_ascii=False) + "\n")
        report(f"naming_transient_root_archive_root {archive_root}")
        report(f"naming_transient_root_manifest {manifest}")

    active_issues = []
    for root in active_roots:
        path = codex_home / root
        if not path.exists():
            continue
        for parent, dirnames, _filenames in os.walk(path):
            current = Path(parent)
            dirnames[:] = [
                name
                for name in dirnames
                if name not in TEXT_AUDIT_EXCLUDED_DIRS and name != ".git"
            ]
            if any(fragment.lower() in current.name.lower() for fragment in forbidden_fragments):
                active_issues.append(current)
    report(f"naming_active_source_name_issues {len(active_issues)}")
    for issue in active_issues[:10]:
        report(f"naming_active_source_name_issue {issue}")


def inspect_contamination_surfaces(
    codex_home: Path,
    config: dict,
    backup_root: Path,
    stamp: str,
    apply: bool,
) -> None:
    policy = contamination_policy(config)
    profile = str(policy.get("profile", "")) if policy else ""
    report(f"contamination_policy {'present' if policy else 'missing'} {profile}".rstrip())
    inspect_marketplace_sources(codex_home, config, policy)
    inspect_codex_apps_tools_cache(codex_home, policy, backup_root, stamp, apply)
    inspect_naming_convention(codex_home, config, backup_root, stamp, apply)
    inspect_nested_git_repositories(codex_home)
    inspect_same_name_nested_dirs(codex_home)
    inspect_deleted_path_references(codex_home)


def codex_processes_running() -> list[str]:
    system = platform.system()
    try:
        if system == "Windows":
            output = subprocess.check_output(
                ["powershell", "-NoProfile", "-Command", "Get-CimInstance Win32_Process | Select-Object Name,ProcessId,CommandLine | ConvertTo-Json -Compress"],
                text=True,
                stderr=subprocess.DEVNULL,
            )
            if not output.strip():
                return []
            data = json.loads(output)
            rows = data if isinstance(data, list) else [data]
            hits = []
            for row in rows:
                name = str(row.get("Name") or "")
                cmd = str(row.get("CommandLine") or "")
                pid = row.get("ProcessId")
                if name == "Codex.exe" or (name == "codex.exe" and ("app-server" in cmd or "OpenAI.Codex" in cmd)):
                    hits.append(f"{pid} {name}")
            return hits
        output = subprocess.check_output(["ps", "-axo", "pid=,comm=,args="], text=True)
        hits = []
        for line in output.splitlines():
            lower = line.lower()
            if "codex" in lower and ("app-server" in lower or "openai.codex" in lower or "codex desktop" in lower):
                hits.append(line.strip())
        return hits
    except Exception:
        return []


def wait_for_codex_exit() -> None:
    while codex_processes_running():
        time.sleep(2)


def sqlite_backup(src: Path, dst: Path) -> None:
    if not src.exists():
        return
    dst.parent.mkdir(parents=True, exist_ok=True)
    source = sqlite3.connect(src)
    target = sqlite3.connect(dst)
    source.backup(target)
    target.close()
    source.close()


def copy_if_exists(src: Path, dst: Path) -> None:
    if not src.exists():
        return
    dst.parent.mkdir(parents=True, exist_ok=True)
    if src.is_dir():
        shutil.copytree(
            src,
            dst,
            ignore=shutil.ignore_patterns(
                "node_modules",
                ".git",
                ".next",
                "dist",
                "build",
                ".venv",
                "__pycache__",
                ".pytest_cache",
            ),
            dirs_exist_ok=True,
        )
    else:
        shutil.copy2(src, dst)
    report(f"backed_up {src.name}")


def backup_metadata(codex_home: Path, backup_root: Path) -> None:
    backup_root.mkdir(parents=True, exist_ok=True)
    for name in [
        ".codex-global-state.json",
        "config.toml",
        "history.jsonl",
        "installation_id",
        "models_cache.json",
        "session_index.jsonl",
        "version.json",
        "memories",
        "skills",
        "rules",
        "plugins",
        "automations",
    ]:
        copy_if_exists(codex_home / name, backup_root / name)
    sqlite_backup(codex_home / "state_5.sqlite", backup_root / "state_5.sqlite")


def load_pinned(codex_home: Path) -> set[str]:
    path = codex_home / ".codex-global-state.json"
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return set(data.get("pinned-thread-ids", []))
    except Exception:
        return set()


def normalize_extended_path(value: str) -> str:
    if value.startswith("\\\\?\\UNC\\"):
        return "\\\\" + value[8:]
    if value.startswith("\\\\?\\"):
        return value[4:]
    return value


def normalize_sqlite_paths(conn: sqlite3.Connection, apply: bool) -> int:
    cur = conn.cursor()
    total = 0
    tables = [
        row[0]
        for row in cur.execute(
            "select name from sqlite_master where type='table' and name not like 'sqlite_%'"
        )
    ]
    for table in tables:
        cols = cur.execute(f'pragma table_info("{table}")').fetchall()
        text_cols = [col[1] for col in cols if "TEXT" in (col[2] or "").upper() or col[2] == ""]
        for col in text_cols:
            rows = cur.execute(
                f'select rowid, "{col}" from "{table}" where "{col}" like ?',
                ("\\\\?\\%",),
            ).fetchall()
            changed = 0
            for rowid, value in rows:
                if isinstance(value, str) and value.startswith("\\\\?\\"):
                    changed += 1
                    if apply:
                        cur.execute(
                            f'update "{table}" set "{col}"=? where rowid=?',
                            (normalize_extended_path(value), rowid),
                        )
            if changed:
                report(f"extended_paths {table}.{col} {changed}")
                total += changed
    if total == 0:
        report("extended_paths 0")
    return total


def active_session_candidates(
    conn: sqlite3.Connection,
    codex_home: Path,
    archive_older_than_days: int,
) -> list[SessionCandidate]:
    sessions_root = codex_home / "sessions"
    cutoff = int((datetime.now() - timedelta(days=archive_older_than_days)).timestamp())
    pinned = load_pinned(codex_home)
    rows = conn.execute(
        "select id, title, rollout_path, updated_at from threads where archived_at is null"
    ).fetchall()
    candidates: list[SessionCandidate] = []
    for thread_id, title, rollout_path, updated_at in rows:
        if thread_id in pinned or not rollout_path:
            continue
        if updated_at is not None and int(updated_at) >= cutoff:
            continue
        source = Path(rollout_path)
        if not source.exists():
            continue
        try:
            relative = source.relative_to(sessions_root)
        except ValueError:
            continue
        candidates.append(
            SessionCandidate(source.stat().st_size, thread_id, title or "", source, relative, updated_at)
        )
    candidates.sort(key=lambda item: item.size, reverse=True)
    return candidates


def archive_sessions(
    conn: sqlite3.Connection,
    candidates: list[SessionCandidate],
    codex_home: Path,
    backup_root: Path,
    stamp: str,
    apply: bool,
) -> None:
    total = sum(item.size for item in candidates)
    report(f"old_session_candidates {len(candidates)}")
    report(f"old_session_candidate_gb {gb(total)}")
    for item in candidates[:10]:
        report(f"large_session_mb {mb(item.size)} {item.thread_id} {item.title[:70]}")
    if not apply or not candidates:
        return

    archive_root = codex_home / "archived_sessions" / f"keep-codex-fast-{stamp}"
    manifest = backup_root / "moved-sessions.jsonl"
    archive_root.mkdir(parents=True, exist_ok=True)
    now = int(time.time())
    cur = conn.cursor()
    with manifest.open("w", encoding="utf-8") as handle:
        for item in candidates:
            dest = archive_root / item.relative
            dest.parent.mkdir(parents=True, exist_ok=True)
            shutil.move(str(item.source), str(dest))
            record = {
                "thread_id": item.thread_id,
                "bytes": item.size,
                "from": str(item.source),
                "to": str(dest),
            }
            handle.write(json.dumps(record, ensure_ascii=False) + "\n")
            cur.execute(
                "update threads set rollout_path=?, archived=1, archived_at=? where id=?",
                (str(dest), now, item.thread_id),
            )
    write_session_restore_script(manifest, codex_home / "state_5.sqlite", backup_root)
    report(f"archived_sessions_root {archive_root}")
    report(f"archived_sessions_manifest {manifest}")


def write_session_restore_script(manifest: Path, state_db: Path, backup_root: Path) -> None:
    restore = backup_root / "restore-sessions.py"
    restore.write_text(
        f'''import json
import shutil
import sqlite3
from pathlib import Path

manifest = Path(r"{manifest}")
db = Path(r"{state_db}")
conn = sqlite3.connect(db)
conn.execute("pragma busy_timeout=10000")
for line in manifest.read_text(encoding="utf-8").splitlines():
    rec = json.loads(line)
    src = Path(rec["to"])
    dest = Path(rec["from"])
    if src.exists():
        dest.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(src), str(dest))
    if rec.get("thread_id"):
        conn.execute(
            "update threads set rollout_path=?, archived=0, archived_at=NULL where id=?",
            (str(dest), rec["thread_id"]),
        )
conn.commit()
conn.close()
''',
        encoding="utf-8",
    )
    report(f"session_restore_script {restore}")


def prune_config(codex_home: Path, backup_root: Path, apply: bool) -> None:
    path = codex_home / "config.toml"
    if not path.exists():
        report("config_prune_candidates 0")
        return
    lines = path.read_text(encoding="utf-8-sig").splitlines()
    out: list[str] = []
    removed: list[str] = []
    i = 0
    while i < len(lines):
        line = lines[i]
        match = PROJECT_HEADER_RE.match(line)
        if not match:
            out.append(line)
            i += 1
            continue
        project_path = match.group(2)
        block = [line]
        i += 1
        while i < len(lines) and not lines[i].startswith("["):
            block.append(lines[i])
            i += 1
        should_remove = bool(TEMP_PROJECT_RE.search(project_path)) or not Path(project_path).exists()
        if should_remove:
            removed.append(project_path)
        else:
            out.extend(block)

    (backup_root / "pruned-projects.txt").write_text(
        "\n".join(removed) + ("\n" if removed else ""),
        encoding="utf-8",
    )
    report(f"config_prune_candidates {len(removed)}")
    if apply and removed:
        path.write_text("\n".join(out) + "\n", encoding="utf-8")
        report("config_pruned applied")


def move_stale_worktrees(codex_home: Path, backup_root: Path, days: int, stamp: str, apply: bool) -> None:
    root = codex_home / "worktrees"
    if not root.exists():
        report("worktree_candidates 0")
        return
    cutoff = time.time() - days * 24 * 60 * 60
    candidates = [path for path in root.iterdir() if path.is_dir() and path.stat().st_mtime < cutoff]
    total = sum(size_bytes(path) for path in candidates)
    report(f"worktree_candidates {len(candidates)}")
    report(f"worktree_candidate_gb {gb(total)}")
    if not apply or not candidates:
        return
    archive_root = codex_home / "archived_worktrees" / f"keep-codex-fast-{stamp}"
    manifest = backup_root / "moved-worktrees.jsonl"
    archive_root.mkdir(parents=True, exist_ok=True)
    with manifest.open("w", encoding="utf-8") as handle:
        for source in candidates:
            dest = archive_root / source.name
            item_size = size_bytes(source)
            shutil.move(str(source), str(dest))
            handle.write(json.dumps({"from": str(source), "to": str(dest), "bytes": item_size}) + "\n")
    report(f"worktree_archive_root {archive_root}")
    report(f"worktree_manifest {manifest}")


def rotate_logs(codex_home: Path, threshold_mb: int, stamp: str, apply: bool) -> None:
    files = [path for path in codex_home.glob("logs_2.sqlite*") if path.is_file()]
    total = sum(path.stat().st_size for path in files)
    report(f"logs_mb {mb(total)}")
    if total < threshold_mb * 1024 * 1024:
        report("logs_rotate skipped_below_threshold")
        return
    if apply and files:
        archive_root = codex_home / "archived_logs" / f"keep-codex-fast-{stamp}"
        archive_root.mkdir(parents=True, exist_ok=True)
        zip_path = archive_root / f"codex-logs-{stamp}.zip"
        manifest = {
            "created_at": datetime.now().isoformat(),
            "mode": "compressed_archive",
            "source_root": str(codex_home),
            "files": [
                {"name": path.name, "bytes": path.stat().st_size}
                for path in files
            ],
        }
        with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
            archive.writestr("manifest.json", json.dumps(manifest, indent=2, ensure_ascii=False))
            for path in files:
                archive.write(path, path.name)
        for path in files:
            path.unlink()
        report(f"logs_archive_root {archive_root}")
        report(f"logs_archive_zip {zip_path}")


def compress_live_logs_snapshot(codex_home: Path, stamp: str) -> Path | None:
    source = codex_home / "logs_2.sqlite"
    if not source.exists():
        report("logs_live_snapshot skipped_missing_logs_db")
        return None

    snapshot_root = codex_home / "archived_logs" / f"live-snapshot-{stamp}"
    snapshot_root.mkdir(parents=True, exist_ok=True)
    snapshot_db = snapshot_root / "logs_2.sqlite"
    zip_path = snapshot_root / f"codex-logs-live-snapshot-{stamp}.zip"

    source_conn = sqlite3.connect(f"file:{source}?mode=ro", uri=True)
    target_conn = sqlite3.connect(snapshot_db)
    source_conn.backup(target_conn)
    target_conn.close()
    source_conn.close()

    manifest = {
        "created_at": datetime.now().isoformat(),
        "mode": "live_sqlite_backup_snapshot",
        "source": str(source),
        "source_bytes": source.stat().st_size,
        "snapshot_bytes": snapshot_db.stat().st_size,
        "note": "Active logs remain in place because Codex is running.",
    }
    with zipfile.ZipFile(zip_path, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        archive.writestr("manifest.json", json.dumps(manifest, indent=2, ensure_ascii=False))
        archive.write(snapshot_db, snapshot_db.name)
    snapshot_db.unlink()
    report(f"logs_live_snapshot_zip {zip_path}")
    report(f"logs_live_snapshot_zip_mb {mb(zip_path.stat().st_size)}")
    return zip_path


def top_node_processes() -> None:
    system = platform.system()
    report("top_node_processes")
    try:
        if system == "Windows":
            command = (
                "Get-Process node -ErrorAction SilentlyContinue | "
                "Sort-Object WorkingSet64 -Descending | Select-Object -First 10 "
                "Id,ProcessName,@{n='MB';e={[math]::Round($_.WorkingSet64/1MB,1)}},Path | "
                "ConvertTo-Json -Compress"
            )
            output = subprocess.check_output(["powershell", "-NoProfile", "-Command", command], text=True)
            if not output.strip():
                return
            data = json.loads(output)
            rows = data if isinstance(data, list) else [data]
            for row in rows:
                report(f"node_mb {row.get('MB')} pid={row.get('Id')} {row.get('Path')}")
            return
        output = subprocess.check_output(["ps", "-axo", "pid=,rss=,comm=,args="], text=True)
        rows = []
        for line in output.splitlines():
            parts = line.strip().split(None, 3)
            if len(parts) >= 3 and "node" in parts[2].lower():
                rows.append((int(parts[1]), line.strip()))
        for rss, line in sorted(rows, reverse=True)[:10]:
            report(f"node_mb {rss / 1024:.1f} {line}")
    except Exception as exc:
        report(f"node_process_report_skipped {exc}")


def verify_sizes(codex_home: Path) -> None:
    for rel in ["sessions", "archived_sessions", "worktrees", "archived_worktrees", "archived_logs"]:
        path = codex_home / rel
        if path.exists():
            report(f"size_{rel}_gb {gb(size_bytes(path))}")


def run(args: argparse.Namespace) -> int:
    codex_home = codex_home_from_args(args.codex_home)
    if not codex_home.exists():
        report(f"codex_home_missing {codex_home}")
        return 2

    stamp = now_stamp()
    backup_root = Path(args.backup_root).expanduser() if args.backup_root else documents_backup_root() / f"keep-codex-fast-{stamp}"
    backup_root = backup_root.resolve()

    running = codex_processes_running()
    if args.apply and running and args.wait_for_codex_exit:
        report("waiting_for_codex_exit")
        wait_for_codex_exit()
        running = []

    effective_apply = bool(args.apply and not running)
    report(f"codex_home {codex_home}")
    report(f"backup_root {backup_root}")
    report(f"requested_mode {'apply' if args.apply else 'report'}")
    report(f"effective_mode {'apply' if effective_apply else 'report'}")
    if args.apply and running:
        report("apply_skipped_codex_running")
        for proc in running:
            report(f"blocking_process {proc}")
    if args.compress_live_logs_snapshot:
        compress_live_logs_snapshot(codex_home, stamp)

    backup_metadata(codex_home, backup_root)

    state_db = codex_home / "state_5.sqlite"
    if state_db.exists():
        conn = sqlite3.connect(state_db)
        conn.execute("pragma busy_timeout=10000")
        normalize_sqlite_paths(conn, effective_apply)
        candidates = active_session_candidates(conn, codex_home, args.archive_older_than_days)
        archive_sessions(conn, candidates, codex_home, backup_root, stamp, effective_apply)
        if effective_apply:
            conn.commit()
            try:
                conn.execute("pragma wal_checkpoint(truncate)")
            except Exception as exc:
                report(f"wal_checkpoint_skipped {exc}")
            try:
                conn.execute("pragma optimize")
            except Exception as exc:
                report(f"sqlite_optimize_skipped {exc}")
        conn.close()
    else:
        report("state_db_missing")

    prune_config(codex_home, backup_root, effective_apply)
    config = load_toml_config(codex_home)
    inspect_contamination_surfaces(codex_home, config, backup_root, stamp, effective_apply)
    move_stale_worktrees(codex_home, backup_root, args.worktree_older_than_days, stamp, effective_apply)
    rotate_logs(codex_home, args.rotate_logs_above_mb, stamp, effective_apply)
    verify_sizes(codex_home)
    top_node_processes()
    report("done")
    return 0


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Safe, backup-first, archive-only Codex local-state cleanup."
    )
    parser.add_argument("--apply", action="store_true", help="Apply cleanup. Default is report-only.")
    parser.add_argument("--wait-for-codex-exit", action="store_true", help="Wait until Codex exits before applying.")
    parser.add_argument("--codex-home", help="Override Codex home. Defaults to CODEX_HOME or ~/.codex.")
    parser.add_argument("--backup-root", help="Override backup output folder.")
    parser.add_argument("--archive-older-than-days", type=int, default=10)
    parser.add_argument("--worktree-older-than-days", type=int, default=7)
    parser.add_argument("--rotate-logs-above-mb", type=int, default=64)
    parser.add_argument(
        "--compress-live-logs-snapshot",
        action="store_true",
        help="Create a compressed SQLite backup snapshot of active logs without moving live files.",
    )
    return parser.parse_args(argv)


if __name__ == "__main__":
    raise SystemExit(run(parse_args(sys.argv[1:])))
