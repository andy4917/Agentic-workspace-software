#!/usr/bin/env python3
"""Smoke tests for codex-log-db.py."""

from __future__ import annotations

import json
import sqlite3
import subprocess
import sys
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parent
CLI = ROOT / "codex-log-db.py"


def run_cmd(*args: str, check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(
        [sys.executable, str(CLI), *args],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    if check and result.returncode != 0:
        raise AssertionError(f"command failed: {args}\nstdout={result.stdout}\nstderr={result.stderr}")
    return result


def main() -> int:
    with tempfile.TemporaryDirectory() as temp:
        root = Path(temp)
        db = root / "codex-log.sqlite"
        run_cmd("--db", str(db), "init-db")

        conn = sqlite3.connect(db)
        columns = {row[1].lower() for row in conn.execute("PRAGMA table_info(events)")}
        forbidden = {"raw", "raw_prompt", "raw_content", "raw_diff", "prompt", "diff", "tool_input"}
        assert not (columns & forbidden), columns & forbidden
        conn.close()

        out = run_cmd(
            "--db",
            str(db),
            "record-event",
            "--event",
            "UserPromptSubmit",
            "--source",
            "test",
            "--outcome",
            "observed",
            "--prompt-length",
            "12",
            "--prompt-sha256",
            "0" * 64,
            "--contains-non-ascii",
            "--changed-surface",
            "config/hook",
            "--validation-result",
            "parser check ok",
        )
        assert json.loads(out.stdout)["status"] == "recorded"

        rejected_payload = run_cmd(
            "--db",
            str(db),
            "record-event",
            "--event",
            "UserPromptSubmit",
            "--payload-json",
            '{"prompt":"do not store me"}',
            check=False,
        )
        assert rejected_payload.returncode != 0
        assert "forbidden raw key" in rejected_payload.stderr

        rejected_pass = run_cmd(
            "--db",
            str(db),
            "record-event",
            "--event",
            "Stop",
            "--outcome",
            "PASS",
            check=False,
        )
        assert rejected_pass.returncode != 0

        run_cmd("--db", str(db), "integrity-check")
        report = json.loads(run_cmd("--db", str(db), "report").stdout)
        assert report["counts"]["UserPromptSubmit"] == 1

        scan_root = root / "scan"
        scan_root.mkdir()
        (scan_root / "sample.log").write_text("metadata only\n", encoding="utf-8")
        (scan_root / "codex-log.sqlite-wal").write_text("skip\n", encoding="utf-8")
        scan = json.loads(
            run_cmd(
                "--db",
                str(scan_root / "codex-log.sqlite"),
                "scan",
                "--root",
                str(scan_root),
                "--output",
                str(root / "inventory.jsonl"),
                "--sha256",
            ).stdout
        )
        assert scan["rows"] == 1

        scan_root_2 = root / "scan2"
        scan_root_2.mkdir()
        (scan_root_2 / "extra.log").write_text("metadata only\n", encoding="utf-8")
        limited_scan = json.loads(
            run_cmd(
                "--db",
                str(root / "limited.sqlite"),
                "scan",
                "--root",
                str(scan_root),
                "--root",
                str(scan_root_2),
                "--output",
                str(root / "limited-inventory.jsonl"),
                "--max-files",
                "1",
            ).stdout
        )
        assert limited_scan["rows"] == 1

    print("codex-log smoke tests ok")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
