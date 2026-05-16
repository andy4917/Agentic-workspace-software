from __future__ import annotations

import importlib.util
import io
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[2]
CHROME_SCRIPTS = (
    ROOT / "plugins" / "patched" / "openai-bundled" / "plugins" / "chrome" / "scripts"
)
TECTONIC_SCRIPTS = (
    ROOT
    / "plugins"
    / "patched"
    / "openai-bundled"
    / "plugins"
    / "latex-tectonic"
    / "scripts"
)


def load_module(name: str, path: Path):
    sys.path.insert(0, str(path.parent))
    try:
        spec = importlib.util.spec_from_file_location(name, path)
        if spec is None or spec.loader is None:
            raise RuntimeError(f"Could not import {path}")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        return module
    finally:
        sys.path.remove(str(path.parent))


class PluginPythonHelperTests(unittest.TestCase):
    def test_extension_installed_fixture_reports_enabled(self) -> None:
        common = load_module("chrome_common_ext_test", CHROME_SCRIPTS / "chrome_common.py")
        helper = load_module(
            "check_extension_installed_test",
            CHROME_SCRIPTS / "check_extension_installed.py",
        )
        extension_id = common.load_expected_extension_id()
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            profile = root / "Profile 2"
            (profile / "Extensions" / extension_id / "1.0.0").mkdir(parents=True)
            (root / "Local State").write_text(
                '{"profile":{"last_used":"Profile 2"}}',
                encoding="utf-8",
            )
            (profile / "Preferences").write_text(
                '{"extensions":{"settings":{"%s":{"state":1}}}}' % extension_id,
                encoding="utf-8",
            )
            with patch.dict(os.environ, {"CODEX_CHROME_USER_DATA_DIR": str(root)}):
                result = helper.get_chrome_extension_install_status()

        self.assertTrue(result["installed"])
        self.assertTrue(result["registered"])
        self.assertTrue(result["enabled"])
        self.assertEqual(result["exitCode"], 0)

    def test_extension_installed_unsupported_args_keep_runtime_error_exit(self) -> None:
        helper = load_module(
            "check_extension_installed_args_test",
            CHROME_SCRIPTS / "check_extension_installed.py",
        )

        with redirect_stdout(io.StringIO()), redirect_stderr(io.StringIO()):
            exit_code = helper.main(["unexpected"])

        self.assertEqual(exit_code, 3)

    def test_native_host_manifest_fixture_reports_correct(self) -> None:
        common = load_module("chrome_common_manifest_test", CHROME_SCRIPTS / "chrome_common.py")
        helper = load_module(
            "check_native_host_manifest_test",
            CHROME_SCRIPTS / "check_native_host_manifest.py",
        )
        extension_id = common.load_expected_extension_id()
        host_name = common.load_expected_host_name()
        with tempfile.TemporaryDirectory() as td:
            manifest = Path(td) / "native-host.json"
            manifest.write_text(
                (
                    '{"name":"%s","description":"test","type":"stdio",'
                    '"path":"C:/test/host.exe","allowed_origins":["chrome-extension://%s/"]}'
                )
                % (host_name, extension_id),
                encoding="utf-8",
            )
            with patch.dict(
                os.environ, {"CODEX_CHROME_NATIVE_HOST_MANIFEST_PATH": str(manifest)}
            ):
                result = helper.get_native_host_manifest_status()

        self.assertTrue(result["exists"])
        self.assertTrue(result["nameMatches"])
        self.assertTrue(result["hasExpectedOrigin"])
        self.assertTrue(result["correct"])

    def test_chrome_is_running_parses_windows_tasklist(self) -> None:
        helper = load_module("chrome_is_running_test", CHROME_SCRIPTS / "chrome_is_running.py")
        output = '"chrome.exe","1234","Console","1","100,000 K"\n"other.exe","5","Console","1","1 K"'

        self.assertEqual(
            helper.parse_windows_task_list(output),
            [{"pid": 1234, "process_name": "chrome.exe", "command": "chrome.exe"}],
        )

    def test_tectonic_path_resolves_platform_binary(self) -> None:
        helper = load_module("tectonic_path_test", TECTONIC_SCRIPTS / "tectonic_path.py")
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            binary_name = "tectonic.exe" if sys.platform == "win32" else "tectonic"
            binary = root / "bin" / binary_name
            binary.parent.mkdir()
            binary.write_text("placeholder", encoding="utf-8")

            resolved = helper.get_tectonic_executable_path(root)

        self.assertEqual(resolved, binary)


if __name__ == "__main__":
    unittest.main()
