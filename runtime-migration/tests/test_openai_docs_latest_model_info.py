from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "skills" / ".system" / "openai-docs" / "scripts" / "resolve_latest_model_info.py"


def load_module():
    spec = importlib.util.spec_from_file_location("resolve_latest_model_info", SCRIPT)
    assert spec is not None
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


class OpenAiDocsLatestModelInfoTests(unittest.TestCase):
    def test_extracts_indented_latest_model_info(self) -> None:
        module = load_module()
        markdown = """# Latest model
latestModelInfo:
  model: gpt-5.5
  migrationGuide: /api/docs/guides/migrate
  promptingGuide: /api/docs/guides/prompt
"""

        info = module.normalize_info(module.extract_latest_model_info(markdown), "https://developers.openai.com")

        self.assertEqual(
            info,
            {
                "model": "gpt-5.5",
                "modelSlug": "gpt-5p5",
                "migrationGuideUrl": "https://developers.openai.com/api/docs/guides/migrate",
                "promptingGuideUrl": "https://developers.openai.com/api/docs/guides/prompt",
            },
        )

    def test_extracts_comment_latest_model_info(self) -> None:
        module = load_module()
        markdown = """# Latest
<!-- latestModelInfo
model: "gpt-5.4"
migrationGuide: /migrate
promptingGuide: /prompt
-->
"""

        info = module.normalize_info(module.extract_latest_model_info(markdown), "https://developers.openai.com/base/")

        self.assertEqual(info["model"], "gpt-5.4")
        self.assertEqual(info["modelSlug"], "gpt-5p4")
        self.assertEqual(info["migrationGuideUrl"], "https://developers.openai.com/migrate")
        self.assertEqual(info["promptingGuideUrl"], "https://developers.openai.com/prompt")

    def test_cli_reads_local_file_and_writes_json(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            source = Path(td) / "latest-model.md"
            source.write_text(
                """latestModelInfo:
  model: gpt-5.5
  migrationGuide: /migrate
  promptingGuide: /prompt
""",
                encoding="utf-8",
            )

            result = subprocess.run(
                [sys.executable, str(SCRIPT), "--source", str(source), "--base-url", "https://developers.openai.com"],
                check=True,
                capture_output=True,
                text=True,
            )

        self.assertEqual(json.loads(result.stdout)["model"], "gpt-5.5")


if __name__ == "__main__":
    unittest.main()
