from __future__ import annotations

import tempfile
import unittest
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "python"))

from runtime_migration.node_js_surface_scanner import emit_yaml, report, scan  # noqa: E402


class NodeJsSurfaceScannerTests(unittest.TestCase):
    def test_memento_paths_are_keep_only(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            source = root / "tools" / "memento-mcp"
            state = root / "state" / "memento-mcp"
            source.mkdir(parents=True)
            state.mkdir(parents=True)
            (source / "package.json").write_text('{"scripts":{"start":"node server.js"}}', encoding="utf-8")
            (state / "runtime.js").write_text("node should remain excluded", encoding="utf-8")

            surfaces = scan(root, source, state)

        self.assertTrue(surfaces)
        self.assertTrue(all(surface.memento_related for surface in surfaces))
        self.assertTrue(all(surface.migration_decision == "keep" for surface in surfaces))
        self.assertTrue(all("Memento" in surface.replacement_contract for surface in surfaces))
        self.assertEqual({surface.current_path for surface in surfaces}, {"state/memento-mcp", "tools/memento-mcp"})

    def test_sensitive_files_are_not_scanned(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            (root / "auth.json").write_text('{"cmd":"npx secret-tool"}', encoding="utf-8")
            (root / "hooks").mkdir()
            (root / "hooks" / "lightweight-codex-hook.ps1").write_text("npx allowed-tool", encoding="utf-8")

            surfaces = scan(root)

        paths = {surface.current_path for surface in surfaces}
        self.assertIn("hooks/lightweight-codex-hook.ps1", paths)
        self.assertNotIn("auth.json", paths)

    def test_patched_plugin_js_is_inventoried_as_handoff_surface(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            script = root / "plugins" / "patched" / "openai-bundled" / "plugins" / "chrome" / "scripts"
            script.mkdir(parents=True)
            (script / "browser-client.mjs").write_text("export const runtime = 'browser';", encoding="utf-8")

            surfaces = scan(root)

        self.assertEqual(len(surfaces), 1)
        surface = surfaces[0]
        self.assertEqual(surface.current_owner, "app-cache")
        self.assertEqual(surface.classification, "app-cache")
        self.assertEqual(surface.observed_problem, "github-language-stat-noise")
        self.assertEqual(surface.migration_decision, "keep")
        self.assertIn("plugin", surface.replacement_contract.lower())

    def test_report_has_required_ticket_fields(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            (root / "package.json").write_text('{"scripts":{"build":"node build.js"}}', encoding="utf-8")
            data = report(root, scan(root))
            rendered = emit_yaml(data)

        self.assertIn("surface_id:", rendered)
        self.assertIn("migration_decision:", rendered)
        self.assertIn("replacement_contract:", rendered)
        self.assertEqual(data["summary"]["surface_count"], 1)


if __name__ == "__main__":
    unittest.main()
