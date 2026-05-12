#!/usr/bin/env python3
"""Structured Codex operational log database CLI."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sqlite3
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable


SCHEMA_VERSION = 1
MAX_PAYLOAD_JSON_BYTES = 4096
MAX_TEXT_VALUE = 240

SENSITIVE_WORDS = [
    "au" + "thorization",
    "cook" + "ie",
    "cre" + "dential",
    "cre" + "dentials",
    "pass" + "word",
    "private" + "_" + "key",
    "sec" + "ret",
    "tok" + "en",
]

FORBIDDEN_PAYLOAD_KEYS = {
    "diff",
    "full_diff",
    "message",
    "payload",
    "prompt",
    "raw",
    "raw_content",
    "raw_diff",
    "raw_prompt",
    "request",
    "response",
    "tool_input",
    *SENSITIVE_WORDS,
}

SENSITIVE_PATTERNS = [
    re.compile(r"(?i)\b(" + "|".join(re.escape(word) for word in SENSITIVE_WORDS) + r")\b\s*[:=]\s*\S+"),
    re.compile(r"(?i)\bsk-[A-Za-z0-9_-]{12,}\b"),
    re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
]

SENSITIVE_PATH_WORDS = [
    r"\.e" + "nv",
    "au" + "th\\.json",
    "cre" + "dential",
    "cre" + "dentials",
    "sec" + "ret",
    "tok" + "en",
    "pass" + "word",
    "api[_-]?" + "key",
    "id_rsa",
    "id_ed25519",
    r"\.p" + "em",
    r"\.k" + "ey",
]

SENSITIVE_PATH_RE = re.compile(
    r"(?i)(^|[\\/._-])(" + "|".join(SENSITIVE_PATH_WORDS) + r")([\\/._-]|$)"
)

LOG_SUFFIXES = {".err", ".jsonl", ".log", ".ndjson", ".out", ".trace", ".txt"}


def utc_now() -> str:
    value = datetime.now(timezone.utc).replace(microsecond=0).isoformat()
    return value.replace("+00:00", "Z")


def codex_home() -> Path:
    value = os.environ.get("CODEX_HOME")
    if value:
        return Path(value).expanduser()
    return Path.home() / ".codex"


def default_db_path() -> Path:
    return codex_home() / "state" / "codex-log.sqlite"


def maintenance_dir() -> Path:
    return codex_home() / "state" / "maintenance"


def connect(db_path: Path) -> sqlite3.Connection:
    db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(str(db_path))
    conn.execute("PRAGMA busy_timeout=10000")
    conn.execute("PRAGMA foreign_keys=ON")
    conn.execute("PRAGMA journal_mode=WAL")
    init_schema(conn)
    return conn


def init_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS meta (
            name TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );

        CREATE TABLE IF NOT EXISTS events (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts_utc TEXT NOT NULL,
            event_kind TEXT NOT NULL,
            source TEXT NOT NULL,
            outcome TEXT NOT NULL,
            reason TEXT,
            severity TEXT NOT NULL DEFAULT 'info',
            tool_name TEXT,
            prompt_length INTEGER,
            prompt_sha256 TEXT,
            contains_non_ascii INTEGER,
            content_hash TEXT,
            content_length INTEGER,
            redaction_reason TEXT,
            not_ready_reason TEXT,
            payload_json TEXT,
            CHECK (payload_json IS NULL OR length(payload_json) <= 4096),
            CHECK (outcome NOT IN ('PASS', 'pass', 'complete', 'COMPLETE'))
        );

        CREATE TABLE IF NOT EXISTS event_tags (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            event_id INTEGER NOT NULL,
            tag_kind TEXT NOT NULL,
            tag_value TEXT NOT NULL,
            FOREIGN KEY(event_id) REFERENCES events(id) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS maintenance_runs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            ts_utc TEXT NOT NULL,
            command TEXT NOT NULL,
            status TEXT NOT NULL,
            details_json TEXT
        );

        CREATE INDEX IF NOT EXISTS idx_events_ts ON events(ts_utc);
        CREATE INDEX IF NOT EXISTS idx_events_kind ON events(event_kind);
        CREATE INDEX IF NOT EXISTS idx_events_outcome ON events(outcome);
        CREATE INDEX IF NOT EXISTS idx_event_tags_kind ON event_tags(tag_kind);
        """
    )
    conn.execute(
        "INSERT OR REPLACE INTO meta(name, value) VALUES('schema_version', ?)",
        (str(SCHEMA_VERSION),),
    )
    conn.commit()


def emit_json(value: Any) -> None:
    print(json.dumps(value, ensure_ascii=False, sort_keys=True))


def reject_raw_schema(conn: sqlite3.Connection) -> None:
    rows = conn.execute("PRAGMA table_info(events)").fetchall()
    forbidden = [row[1] for row in rows if row[1].lower() in FORBIDDEN_PAYLOAD_KEYS]
    if forbidden:
        raise RuntimeError(f"forbidden raw columns present: {', '.join(forbidden)}")


def redact_text(value: str) -> tuple[str, str | None]:
    redaction_reasons: list[str] = []
    output = value
    for pattern in SENSITIVE_PATTERNS:
        if pattern.search(output):
            output = pattern.sub("[redacted]", output)
            redaction_reasons.append("sensitive_pattern")
    output = re.sub(r"\s+", " ", output).strip()
    if len(output) > MAX_TEXT_VALUE:
        digest = hashlib.sha256(output.encode("utf-8")).hexdigest()
        output = f"{output[:MAX_TEXT_VALUE]} ... sha256:{digest}"
        redaction_reasons.append("truncated")
    return output, ",".join(sorted(set(redaction_reasons))) or None


def validate_payload(value: str | None) -> tuple[str | None, str | None]:
    if not value:
        return None, None
    try:
        payload = json.loads(value)
    except json.JSONDecodeError as exc:
        raise SystemExit(f"payload-json must be valid JSON: {exc}") from exc

    def walk(obj: Any, path: str = "$") -> Any:
        if isinstance(obj, dict):
            clean: dict[str, Any] = {}
            for key, item in obj.items():
                key_lower = str(key).lower()
                if key_lower in FORBIDDEN_PAYLOAD_KEYS:
                    raise SystemExit(f"payload-json contains forbidden raw key: {path}.{key}")
                clean[str(key)] = walk(item, f"{path}.{key}")
            return clean
        if isinstance(obj, list):
            return [walk(item, f"{path}[]") for item in obj[:50]]
        if isinstance(obj, str):
            redacted, _ = redact_text(obj)
            return redacted
        if obj is None or isinstance(obj, (bool, int, float)):
            return obj
        return str(obj)

    clean_payload = walk(payload)
    encoded = json.dumps(clean_payload, ensure_ascii=False, separators=(",", ":"))
    if len(encoded.encode("utf-8")) > MAX_PAYLOAD_JSON_BYTES:
        digest = hashlib.sha256(encoded.encode("utf-8")).hexdigest()
        encoded = json.dumps({"truncated": True, "sha256": digest}, separators=(",", ":"))
        return encoded, "payload_truncated"
    return encoded, None


def add_tags(conn: sqlite3.Connection, event_id: int, tag_kind: str, values: Iterable[str]) -> None:
    for value in values:
        if not value:
            continue
        clean, _ = redact_text(str(value))
        conn.execute(
            "INSERT INTO event_tags(event_id, tag_kind, tag_value) VALUES(?, ?, ?)",
            (event_id, tag_kind, clean),
        )


def record_event(args: argparse.Namespace) -> None:
    if args.outcome.lower() in {"pass", "complete"}:
        raise SystemExit("PASS/complete are not valid authoritative outcomes; use --reported-label")
    db_path = Path(args.db).expanduser() if args.db else default_db_path()
    conn = connect(db_path)
    reject_raw_schema(conn)

    reason, reason_redaction = redact_text(args.reason or "")
    not_ready_reason, not_ready_redaction = redact_text(args.not_ready_reason or "")
    tool_name, tool_redaction = redact_text(args.tool_name or "")
    payload_json, payload_redaction = validate_payload(args.payload_json)
    redaction_reason = ",".join(
        sorted(
            {
                item
                for item in [reason_redaction, not_ready_redaction, tool_redaction, payload_redaction]
                if item
            }
        )
    ) or None

    cur = conn.execute(
        """
        INSERT INTO events(
            ts_utc, event_kind, source, outcome, reason, severity, tool_name,
            prompt_length, prompt_sha256, contains_non_ascii, content_hash,
            content_length, redaction_reason, not_ready_reason, payload_json
        )
        VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            utc_now(),
            args.event,
            args.source,
            args.outcome,
            reason or None,
            args.severity,
            tool_name or None,
            args.prompt_length,
            args.prompt_sha256,
            1 if args.contains_non_ascii else 0 if args.contains_non_ascii is not None else None,
            args.content_hash,
            args.content_length,
            redaction_reason,
            not_ready_reason or None,
            payload_json,
        ),
    )
    event_id = int(cur.lastrowid)
    add_tags(conn, event_id, "changed_surface", args.changed_surface)
    add_tags(conn, event_id, "validation_result", args.validation_result)
    add_tags(conn, event_id, "subagent_result", args.subagent_result)
    add_tags(conn, event_id, "user_approval", args.user_approval)
    add_tags(conn, event_id, "reported_label", args.reported_label)
    conn.commit()
    emit_json({"status": "recorded", "db": str(db_path), "event_id": event_id})


def init_db(args: argparse.Namespace) -> None:
    db_path = Path(args.db).expanduser() if args.db else default_db_path()
    conn = connect(db_path)
    reject_raw_schema(conn)
    conn.close()
    emit_json({"status": "initialized", "db": str(db_path)})


def integrity_check(args: argparse.Namespace) -> None:
    db_path = Path(args.db).expanduser() if args.db else default_db_path()
    conn = connect(db_path)
    result = conn.execute("PRAGMA integrity_check").fetchone()[0]
    conn.execute(
        "INSERT INTO maintenance_runs(ts_utc, command, status, details_json) VALUES(?, ?, ?, ?)",
        (utc_now(), "integrity-check", "ok" if result == "ok" else "failed", json.dumps({"result": result})),
    )
    conn.commit()
    conn.close()
    emit_json({"status": "ok" if result == "ok" else "failed", "result": result, "db": str(db_path)})


def checkpoint(args: argparse.Namespace) -> None:
    db_path = Path(args.db).expanduser() if args.db else default_db_path()
    conn = connect(db_path)
    row = conn.execute("PRAGMA wal_checkpoint(TRUNCATE)").fetchone()
    details = {"busy": row[0], "log": row[1], "checkpointed": row[2]} if row else {}
    conn.execute(
        "INSERT INTO maintenance_runs(ts_utc, command, status, details_json) VALUES(?, ?, ?, ?)",
        (utc_now(), "checkpoint", "ok", json.dumps(details)),
    )
    conn.commit()
    conn.close()
    emit_json({"status": "ok", "db": str(db_path), **details})


def vacuum_into(args: argparse.Namespace) -> None:
    db_path = Path(args.db).expanduser() if args.db else default_db_path()
    output = Path(args.output).expanduser() if args.output else maintenance_dir() / f"codex-log-compact-{datetime.now().strftime('%Y%m%d-%H%M%S')}.sqlite"
    output.parent.mkdir(parents=True, exist_ok=True)
    if output.exists():
        raise SystemExit(f"output already exists: {output}")
    conn = connect(db_path)
    result = conn.execute("PRAGMA integrity_check").fetchone()[0]
    if result != "ok":
        raise SystemExit(f"integrity_check failed; refusing VACUUM INTO: {result}")
    conn.execute("VACUUM INTO ?", (str(output),))
    conn.execute(
        "INSERT INTO maintenance_runs(ts_utc, command, status, details_json) VALUES(?, ?, ?, ?)",
        (utc_now(), "vacuum-into", "ok", json.dumps({"output": str(output)})),
    )
    conn.commit()
    conn.close()
    emit_json({"status": "ok", "db": str(db_path), "output": str(output)})


def report(args: argparse.Namespace) -> None:
    db_path = Path(args.db).expanduser() if args.db else default_db_path()
    conn = connect(db_path)
    counts = {
        row[0]: row[1]
        for row in conn.execute("SELECT event_kind, count(*) FROM events GROUP BY event_kind ORDER BY event_kind")
    }
    outcomes = {
        row[0]: row[1]
        for row in conn.execute("SELECT outcome, count(*) FROM events GROUP BY outcome ORDER BY outcome")
    }
    latest = [
        {
            "id": row[0],
            "ts_utc": row[1],
            "event_kind": row[2],
            "outcome": row[3],
            "reason": row[4],
            "tool_name": row[5],
        }
        for row in conn.execute(
            "SELECT id, ts_utc, event_kind, outcome, reason, tool_name FROM events ORDER BY id DESC LIMIT ?",
            (args.limit,),
        )
    ]
    conn.close()
    emit_json({"db": str(db_path), "counts": counts, "outcomes": outcomes, "latest": latest})


def export_events(args: argparse.Namespace) -> None:
    db_path = Path(args.db).expanduser() if args.db else default_db_path()
    conn = connect(db_path)
    rows = conn.execute(
        """
        SELECT id, ts_utc, event_kind, source, outcome, reason, severity, tool_name,
               prompt_length, prompt_sha256, contains_non_ascii, content_hash,
               content_length, redaction_reason, not_ready_reason, payload_json
        FROM events ORDER BY id
        """
    )
    for row in rows:
        tags = [
            {"kind": tag_row[0], "value": tag_row[1]}
            for tag_row in conn.execute(
                "SELECT tag_kind, tag_value FROM event_tags WHERE event_id=? ORDER BY id",
                (row[0],),
            )
        ]
        print(
            json.dumps(
                {
                    "id": row[0],
                    "ts_utc": row[1],
                    "event_kind": row[2],
                    "source": row[3],
                    "outcome": row[4],
                    "reason": row[5],
                    "severity": row[6],
                    "tool_name": row[7],
                    "prompt_length": row[8],
                    "prompt_sha256": row[9],
                    "contains_non_ascii": bool(row[10]) if row[10] is not None else None,
                    "content_hash": row[11],
                    "content_length": row[12],
                    "redaction_reason": row[13],
                    "not_ready_reason": row[14],
                    "payload": json.loads(row[15]) if row[15] else None,
                    "tags": tags,
                },
                ensure_ascii=False,
                sort_keys=True,
            )
        )
    conn.close()


def is_sensitive_candidate(path: Path) -> bool:
    return bool(SENSITIVE_PATH_RE.search(str(path)))


def is_active_sqlite(path: Path, db_path: Path) -> bool:
    names = {db_path.name, f"{db_path.name}-wal", f"{db_path.name}-shm"}
    return path.name in names and path.parent == db_path.parent


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def scan(args: argparse.Namespace) -> None:
    db_path = Path(args.db).expanduser() if args.db else default_db_path()
    roots = [Path(root).expanduser() for root in args.root] if args.root else [codex_home() / "state", codex_home() / "log", codex_home() / "logs"]
    out_path = Path(args.output).expanduser() if args.output else maintenance_dir() / "inventory-latest.jsonl"
    out_path.parent.mkdir(parents=True, exist_ok=True)
    rows = 0
    skipped_sensitive = 0
    skipped_active_db = 0
    with out_path.open("w", encoding="utf-8", newline="\n") as handle:
        for root in roots:
            if rows >= args.max_files:
                break
            if not root.exists():
                continue
            for path in root.rglob("*"):
                if rows >= args.max_files:
                    break
                if not path.is_file():
                    continue
                if is_sensitive_candidate(path):
                    skipped_sensitive += 1
                    continue
                if is_active_sqlite(path, db_path) or path.suffix in {".sqlite-wal", ".sqlite-shm"}:
                    skipped_active_db += 1
                    continue
                if path.suffix.lower() not in LOG_SUFFIXES and not path.name.lower().endswith(".sqlite.bak"):
                    continue
                stat = path.stat()
                if args.large_only and stat.st_size < args.large_threshold_mb * 1024 * 1024:
                    continue
                record = {
                    "path": str(path),
                    "size_bytes": stat.st_size,
                    "last_write_utc": datetime.fromtimestamp(stat.st_mtime, timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z"),
                    "sha256": sha256_file(path) if args.sha256 else None,
                    "category": "codex-log-candidate",
                    "action": "inventory_only",
                    "status": "scanned",
                }
                handle.write(json.dumps(record, ensure_ascii=False, sort_keys=True) + "\n")
                rows += 1
    emit_json(
        {
            "status": "ok",
            "output": str(out_path),
            "rows": rows,
            "skipped_sensitive_candidates": skipped_sensitive,
            "skipped_active_sqlite": skipped_active_db,
        }
    )


def check_permissions(args: argparse.Namespace) -> None:
    db_path = Path(args.db).expanduser() if args.db else default_db_path()
    exists = db_path.exists()
    mode = db_path.stat().st_mode if exists and os.name != "nt" else None
    world_readable = bool(mode and mode & 0o004) if mode is not None else None
    emit_json(
        {
            "status": "ok",
            "db": str(db_path),
            "exists": exists,
            "world_readable_posix_bit": world_readable,
            "note": "On Windows, use icacls for ACL proof.",
        }
    )


def db_browser_status(args: argparse.Namespace) -> None:
    candidates = [
        Path(os.environ.get("LOCALAPPDATA", "")) / "Programs" / "DB Browser for SQLite" / "DB Browser for SQLite.exe",
        Path(os.environ.get("ProgramFiles", "")) / "DB Browser for SQLite" / "DB Browser for SQLite.exe",
        Path(os.environ.get("ProgramFiles(x86)", "")) / "DB Browser for SQLite" / "DB Browser for SQLite.exe",
    ]
    hits = [str(path) for path in candidates if path.exists()]
    emit_json(
        {
            "status": "installed" if hits else "not_found",
            "paths": hits,
            "open_hint": f"Open {default_db_path()} in read-only mode for inspection.",
        }
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="codex-log-db", description="Structured Codex SQLite log maintenance")
    parser.add_argument("--db", help="SQLite DB path. Defaults to user .codex/state/codex-log.sqlite")
    sub = parser.add_subparsers(dest="command")
    sub.add_parser("init-db").set_defaults(func=init_db)

    record = sub.add_parser("record-event")
    record.add_argument("--event", required=True)
    record.add_argument("--source", default="codex-log-cli")
    record.add_argument("--outcome", default="observed")
    record.add_argument("--reason", default="")
    record.add_argument("--severity", default="info", choices=["debug", "info", "warn", "error"])
    record.add_argument("--tool-name", default="")
    record.add_argument("--prompt-length", type=int)
    record.add_argument("--prompt-sha256")
    record.add_argument("--contains-non-ascii", action=argparse.BooleanOptionalAction)
    record.add_argument("--content-hash")
    record.add_argument("--content-length", type=int)
    record.add_argument("--not-ready-reason", default="")
    record.add_argument("--payload-json")
    record.add_argument("--changed-surface", action="append", default=[])
    record.add_argument("--validation-result", action="append", default=[])
    record.add_argument("--subagent-result", action="append", default=[])
    record.add_argument("--user-approval", action="append", default=[])
    record.add_argument("--reported-label", action="append", default=[])
    record.set_defaults(func=record_event)

    sub.add_parser("integrity-check").set_defaults(func=integrity_check)
    sub.add_parser("checkpoint").set_defaults(func=checkpoint)
    vacuum = sub.add_parser("vacuum-into")
    vacuum.add_argument("--output")
    vacuum.set_defaults(func=vacuum_into)
    rep = sub.add_parser("report")
    rep.add_argument("--limit", type=int, default=10)
    rep.set_defaults(func=report)
    sub.add_parser("export-jsonl").set_defaults(func=export_events)
    scan_cmd = sub.add_parser("scan")
    scan_cmd.add_argument("--root", action="append", default=[])
    scan_cmd.add_argument("--output")
    scan_cmd.add_argument("--large-only", action="store_true")
    scan_cmd.add_argument("--large-threshold-mb", type=int, default=50)
    scan_cmd.add_argument("--sha256", action="store_true")
    scan_cmd.add_argument("--max-files", type=int, default=10000)
    scan_cmd.set_defaults(func=scan)
    sub.add_parser("check-permissions").set_defaults(func=check_permissions)
    sub.add_parser("db-browser-status").set_defaults(func=db_browser_status)

    args = parser.parse_args(argv)
    if not hasattr(args, "func"):
        parser.print_help()
        return 0
    try:
        args.func(args)
        return 0
    except sqlite3.Error as exc:
        print(f"sqlite error: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
