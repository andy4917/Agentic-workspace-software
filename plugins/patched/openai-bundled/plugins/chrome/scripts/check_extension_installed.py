from __future__ import annotations

import json
import sys
from pathlib import Path

from chrome_common import (
    load_expected_extension_id,
    read_json_file_if_present,
    resolve_chrome_profile_path,
)

EXIT_INSTALLED_AND_ENABLED = 0
EXIT_INSTALLED_NOT_ENABLED = 1
EXIT_NOT_INSTALLED = 2
EXIT_RUNTIME_ERROR = 3


def get_chrome_extension_install_status() -> dict[str, object]:
    extension_id = load_expected_extension_id()
    profile_path = resolve_chrome_profile_path()
    preferences = get_chrome_extension_preferences(profile_path, extension_id)
    extensions_directory = profile_path / "Extensions"
    extension_path = extensions_directory / extension_id
    versions = (
        sorted(path.name for path in extension_path.iterdir() if path.is_dir())
        if extension_path.is_dir()
        else []
    )
    installed = len(versions) > 0
    disabled = preferences["state"] == 0 or len(preferences["disableReasons"]) > 0
    enabled = installed and bool(preferences["registered"]) and not disabled

    return {
        "extensionId": extension_id,
        "preferencesPath": (
            str(preferences["preferencesPath"])
            if preferences["preferencesPath"] is not None
            else None
        ),
        "profilePath": str(profile_path),
        "extensionsDirectory": str(extensions_directory),
        "extensionPath": str(extension_path),
        "installed": installed,
        "registered": preferences["registered"],
        "enabled": enabled,
        "disabled": disabled,
        "exitCode": get_exit_code(enabled=enabled, installed=installed),
        "state": preferences["state"],
        "disableReasons": preferences["disableReasons"],
        "versions": versions,
    }


def get_chrome_extension_preferences(
    profile_path: Path, extension_id: str
) -> dict[str, object]:
    for preferences_path in [
        profile_path / "Secure Preferences",
        profile_path / "Preferences",
    ]:
        preferences = read_json_file_if_present(preferences_path)
        if not isinstance(preferences, dict):
            continue
        extensions = preferences.get("extensions")
        settings = extensions.get("settings") if isinstance(extensions, dict) else None
        extension_settings = (
            settings.get(extension_id) if isinstance(settings, dict) else None
        )
        if not isinstance(extension_settings, dict):
            continue

        state = extension_settings.get("state")
        return {
            "preferencesPath": preferences_path,
            "registered": True,
            "state": state if isinstance(state, int) else None,
            "disableReasons": get_disable_reasons(
                extension_settings.get("disable_reasons")
            ),
        }

    return {
        "preferencesPath": None,
        "registered": False,
        "state": None,
        "disableReasons": [],
    }


def get_disable_reasons(disable_reasons: object) -> list[object]:
    if isinstance(disable_reasons, list):
        return disable_reasons
    if isinstance(disable_reasons, int) and disable_reasons != 0:
        return [disable_reasons]
    return []


def get_exit_code(*, enabled: bool, installed: bool) -> int:
    if enabled:
        return EXIT_INSTALLED_AND_ENABLED
    if installed:
        return EXIT_INSTALLED_NOT_ENABLED
    return EXIT_NOT_INSTALLED


def parse_args(argv: list[str]) -> object:
    if "-h" in argv or "--help" in argv:
        print("Usage: scripts/check_extension_installed.py [--json]")
        raise SystemExit(0)
    positional_args = [arg for arg in argv if arg != "--json"]
    if positional_args:
        print("Usage: scripts/check_extension_installed.py [--json]", file=sys.stderr)
        raise ValueError("unsupported arguments")
    return type("Args", (), {"json": "--json" in argv})()


def print_text_report(result: dict[str, object]) -> None:
    print(f"Checked Chrome profile: {result['profilePath']}")
    print(f"Extension ID: {result['extensionId']}")
    print(f"Extension path: {result['extensionPath']}")
    print(f"Installed: {'yes' if result['installed'] else 'no'}")
    print(f"Registered in Chrome preferences: {'yes' if result['registered'] else 'no'}")
    print(f"Enabled: {'yes' if result['enabled'] else 'no'}")
    if result["disabled"]:
        print(f"Disable reasons: {', '.join(map(str, result['disableReasons']))}")
    if result["versions"]:
        print(f"Installed versions: {', '.join(map(str, result['versions']))}")


def main(argv: list[str] | None = None) -> int:
    try:
        args = parse_args(sys.argv[1:] if argv is None else argv)
        result = get_chrome_extension_install_status()
        if args.json:
            print(json.dumps(result, indent=2))
        else:
            print_text_report(result)
        return int(result["exitCode"])
    except SystemExit:
        raise
    except Exception as error:
        print(str(error), file=sys.stderr)
        return EXIT_RUNTIME_ERROR


if __name__ == "__main__":
    sys.exit(main())
