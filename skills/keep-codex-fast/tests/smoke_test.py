#!/usr/bin/env python3
"""Smoke tests for keep-codex-fast using a fake Codex home."""

from __future__ import annotations

import argparse
import importlib.util
import json
import os
import sqlite3
import sys
import tempfile
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "keep_codex_fast.py"


def load_module():
    spec = importlib.util.spec_from_file_location("keep_codex_fast", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    sys.modules["keep_codex_fast"] = module
    assert spec.loader is not None
    spec.loader.exec_module(module)
    module.codex_processes_running = lambda: []
    module.top_node_processes = lambda: module.report("top_node_processes skipped_in_smoke")
    return module


def make_fake_home(root: Path) -> dict[str, Path]:
    codex_home = root / ".codex"
    sessions = codex_home / "sessions" / "2026" / "01" / "01"
    sessions.mkdir(parents=True)
    rollout = sessions / "rollout-2026-01-01T00-00-00-aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa.jsonl"
    rollout.write_text('{"type":"test"}\n', encoding="utf-8")
    old_time = time.time() - 30 * 86400
    os.utime(rollout, (old_time, old_time))

    (codex_home / ".codex-global-state.json").write_text('{"pinned-thread-ids":[]}', encoding="utf-8")
    marketplace = codex_home / "plugins" / "local-marketplaces" / "openai-bundled"
    marketplace.mkdir(parents=True)
    (codex_home / "config.toml").write_text(
        "\n".join(
            [
                '[projects."C:\\\\DefinitelyMissingKeepCodexFast"]',
                'trust_level = "trusted"',
                "",
                "[maintenance.contamination_prevention]",
                'profile = "codex_home_contamination_guard_v1"',
                "expected_app_connectors = [\"GitHub\"]",
                "unexpected_app_connectors = [\"Supabase\", \"Hugging Face\"]",
                "unexpected_app_tool_namespaces = [\"mcp__codex_apps__supabase\", \"mcp__codex_apps__hugging_face\"]",
                f"allowed_marketplace_source_roots = ['{marketplace.parent}']",
                "",
                "[maintenance.naming_convention]",
                'profile = "codex_home_naming_guard_v1"',
                "transient_root_names = [\".tmp\", \"tmp\", \"vendor_imports\"]",
                "normal_active_source_roots = [\"plugins/local-marketplaces\", \"skills\"]",
                "forbidden_active_source_name_fragments = [\".tmp\", \"tmp\", \"archive\"]",
                'log_archive_name_format = "codex-logs-{yyyymmdd-HHMMSS}.zip"',
                "",
                "[marketplaces.openai-bundled]",
                'source_type = "local"',
                f"source = '{marketplace}'",
                "",
            ]
        ),
        encoding="utf-8",
    )

    app_tools = codex_home / "cache" / "codex_apps_tools" / "github.json"
    app_tools.parent.mkdir(parents=True)
    app_tools.write_text(
        json.dumps(
            {
                "tools": [
                    {
                        "connector_name": "GitHub",
                        "tool_namespace": "mcp__codex_apps__github",
                        "name": "search",
                    }
                ]
            }
        ),
        encoding="utf-8",
    )

    worktree = codex_home / "worktrees" / "oldtree"
    worktree.mkdir(parents=True)
    (worktree / "file.txt").write_text("x", encoding="utf-8")
    os.utime(worktree, (old_time, old_time))

    log_file = codex_home / "logs_2.sqlite"
    log_file.write_text("log", encoding="utf-8")

    state_db = codex_home / "state_5.sqlite"
    conn = sqlite3.connect(state_db)
    conn.execute(
        "create table threads (id text primary key, title text, rollout_path text, cwd text, updated_at integer, archived_at integer, archived integer)"
    )
    conn.execute(
        "insert into threads values (?,?,?,?,?,?,?)",
        (
            "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",
            "Old test thread",
            str(rollout),
            r"\\?\C:\DefinitelyMissingKeepCodexFast",
            int(old_time),
            None,
            0,
        ),
    )
    conn.commit()
    conn.close()

    return {
        "codex_home": codex_home,
        "rollout": rollout,
        "worktree": worktree,
        "log_file": log_file,
        "state_db": state_db,
        "app_tools": app_tools,
    }


def assert_report_mode(module) -> None:
    with tempfile.TemporaryDirectory() as td:
        paths = make_fake_home(Path(td))
        backup = Path(td) / "backup-report"
        args = argparse.Namespace(
            apply=False,
            wait_for_codex_exit=False,
            codex_home=str(paths["codex_home"]),
            backup_root=str(backup),
            archive_older_than_days=10,
            worktree_older_than_days=7,
            rotate_logs_above_mb=0,
            compress_live_logs_snapshot=False,
        )
        assert module.run(args) == 0
        assert paths["rollout"].exists(), "report mode must not move sessions"
        assert paths["worktree"].exists(), "report mode must not move worktrees"
        assert paths["log_file"].exists(), "report mode must not rotate logs"
        assert paths["app_tools"].exists(), "normal app tool cache must not be moved in report mode"


def assert_apply_mode(module) -> None:
    with tempfile.TemporaryDirectory() as td:
        paths = make_fake_home(Path(td))
        backup = Path(td) / "backup-apply"
        args = argparse.Namespace(
            apply=True,
            wait_for_codex_exit=False,
            codex_home=str(paths["codex_home"]),
            backup_root=str(backup),
            archive_older_than_days=10,
            worktree_older_than_days=7,
            rotate_logs_above_mb=0,
            compress_live_logs_snapshot=False,
        )
        assert module.run(args) == 0

        conn = sqlite3.connect(paths["state_db"])
        archived, archived_at, rollout_path, cwd = conn.execute(
            "select archived, archived_at, rollout_path, cwd from threads where id=?",
            ("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa",),
        ).fetchone()
        conn.close()

        assert archived == 1
        assert archived_at is not None
        assert "archived_sessions" in rollout_path
        assert cwd == r"C:\DefinitelyMissingKeepCodexFast"
        assert not paths["rollout"].exists()
        assert not paths["worktree"].exists()
        assert not paths["log_file"].exists()
        assert paths["app_tools"].exists(), "normal GitHub app tool cache must be preserved"
        assert "DefinitelyMissingKeepCodexFast" not in (paths["codex_home"] / "config.toml").read_text(
            encoding="utf-8"
        )
        assert (backup / "restore-sessions.py").exists()
        assert (backup / "moved-sessions.jsonl").exists()
        assert (backup / "moved-worktrees.jsonl").exists()


def assert_reparse_points_skipped_in_backup(module) -> None:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        source = root / "source"
        dest = root / "dest"
        source.mkdir()
        (source / "normal.txt").write_text("keep", encoding="utf-8")
        reparse_dir = source / "fake-junction"
        reparse_dir.mkdir()
        (reparse_dir / "external.txt").write_text("skip", encoding="utf-8")

        original_isjunction = getattr(module.os.path, "isjunction", None)
        module.os.path.isjunction = lambda path: Path(path).name == "fake-junction"
        try:
            module.copy_if_exists(source, dest)
        finally:
            if original_isjunction is None:
                delattr(module.os.path, "isjunction")
            else:
                module.os.path.isjunction = original_isjunction

        assert (dest / "normal.txt").exists()
        assert not (dest / "fake-junction").exists()


def main() -> int:
    module = load_module()
    assert_report_mode(module)
    assert_apply_mode(module)
    assert_reparse_points_skipped_in_backup(module)
    print("smoke tests passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
