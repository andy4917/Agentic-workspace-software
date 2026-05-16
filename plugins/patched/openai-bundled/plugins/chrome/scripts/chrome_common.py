from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

CHROME_EXTENSION_ID_CONFIG_FILENAME = "extension-id.json"
CHROME_NATIVE_HOST_MANIFEST_PATH_ENV = "CODEX_CHROME_NATIVE_HOST_MANIFEST_PATH"
CHROME_PREFERENCES_PATH_ENV = "CODEX_CHROME_PREFERENCES_PATH"
CHROME_USER_DATA_DIR_ENV = "CODEX_CHROME_USER_DATA_DIR"
WINDOWS_NATIVE_HOST_REGISTRY_KEY_PREFIX = (
    r"HKCU\Software\Google\Chrome\NativeMessagingHosts"
)


def script_dir() -> Path:
    return Path(__file__).resolve().parent


def sibling_script_path(filename: str) -> Path:
    return script_dir() / filename


def read_json_file(path: Path) -> object:
    return json.loads(path.read_text(encoding="utf-8"))


def read_json_file_if_present(path: Path) -> object | None:
    if not path.exists():
        return None
    return read_json_file(path)


def load_extension_config() -> dict[str, object]:
    config_path = sibling_script_path(CHROME_EXTENSION_ID_CONFIG_FILENAME)
    config = read_json_file(config_path)
    if not isinstance(config, dict) or not isinstance(config.get("extensionId"), str):
        raise RuntimeError(f"Could not read extensionId from {config_path}.")
    return config


def load_expected_extension_id() -> str:
    return str(load_extension_config()["extensionId"])


def load_expected_host_name() -> str:
    config = load_extension_config()
    install_manifest_path = sibling_script_path("installManifest.mjs")
    if not install_manifest_path.exists():
        host_name = config.get("extensionHostName")
        if isinstance(host_name, str):
            return host_name
        raise RuntimeError(f"Could not find installManifest.mjs at {install_manifest_path}.")

    source = install_manifest_path.read_text(encoding="utf-8")
    match = re.search(r'extensionHostName:"([^"]+)"', source)
    if not match:
        raise RuntimeError(f"Could not read extensionHostName from {install_manifest_path}.")
    return match.group(1)


def resolve_chrome_user_data_directory() -> Path:
    override = os.environ.get(CHROME_USER_DATA_DIR_ENV)
    if override:
        return Path(override).resolve()

    home = Path.home()
    if sys.platform == "darwin":
        return home / "Library" / "Application Support" / "Google" / "Chrome"
    if sys.platform == "win32":
        local_app_data = os.environ.get("LOCALAPPDATA") or str(
            home / "AppData" / "Local"
        )
        return Path(local_app_data) / "Google" / "Chrome" / "User Data"
    return home / ".config" / "google-chrome"


def resolve_chrome_preferences_path() -> Path:
    override = os.environ.get(CHROME_PREFERENCES_PATH_ENV)
    if override:
        return Path(override).resolve()

    user_data_directory = resolve_chrome_user_data_directory()
    profile_directory = resolve_chrome_profile_directory(user_data_directory)
    return user_data_directory / profile_directory / "Preferences"


def resolve_chrome_profile_path() -> Path:
    return resolve_chrome_preferences_path().parent


def resolve_chrome_profile_directory(user_data_directory: Path) -> str:
    local_state_profile = resolve_chrome_profile_directory_from_local_state(
        user_data_directory
    )
    if local_state_profile:
        return local_state_profile

    latest_profile = find_latest_chrome_profile(user_data_directory)
    if latest_profile:
        return latest_profile

    raise RuntimeError(
        "Could not find a Chrome profile directory with Preferences in "
        f"{user_data_directory}."
    )


def resolve_chrome_profile_directory_from_local_state(
    user_data_directory: Path,
) -> str | None:
    local_state = read_json_file_if_present(user_data_directory / "Local State")
    if not isinstance(local_state, dict):
        return None
    profile = local_state.get("profile")
    if not isinstance(profile, dict):
        return None

    last_used = profile.get("last_used")
    if is_usable_chrome_profile(user_data_directory, last_used):
        return str(last_used)

    last_active_profiles = profile.get("last_active_profiles")
    if isinstance(last_active_profiles, list):
        return choose_latest_usable_chrome_profile(
            user_data_directory,
            [item for item in last_active_profiles if isinstance(item, str)],
        )
    return None


def choose_latest_usable_chrome_profile(
    user_data_directory: Path, profile_directories: list[str]
) -> str | None:
    usable_profiles = [
        profile
        for profile in profile_directories
        if is_usable_chrome_profile(user_data_directory, profile)
    ]
    if not usable_profiles:
        return None
    return sorted(usable_profiles, key=chrome_profile_directory_sort_key)[-1]


def find_latest_chrome_profile(user_data_directory: Path) -> str | None:
    if not user_data_directory.exists():
        raise RuntimeError(
            f"Chrome user data directory does not exist: {user_data_directory}."
        )

    profile_directories = [
        path.name
        for path in user_data_directory.iterdir()
        if path.is_dir() and (path.name == "Default" or re.fullmatch(r"Profile \d+", path.name))
    ]
    return choose_latest_usable_chrome_profile(
        user_data_directory, profile_directories
    )


def is_usable_chrome_profile(
    user_data_directory: Path, profile_directory: object
) -> bool:
    if not isinstance(profile_directory, str) or not profile_directory:
        return False
    return (user_data_directory / profile_directory / "Preferences").exists()


def chrome_profile_directory_sort_key(profile_directory: str) -> int:
    if profile_directory == "Default":
        return 0
    match = re.fullmatch(r"Profile (\d+)", profile_directory)
    if not match:
        return -1
    return int(match.group(1))


def run_command(args: list[str]) -> str | None:
    try:
        return subprocess.run(
            args,
            check=True,
            encoding="utf-8",
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        ).stdout.strip()
    except Exception:
        return None


def read_windows_registry_default_value(registry_key: str) -> str | None:
    output = run_command(["reg", "query", registry_key, "/ve"])
    if not output:
        return None
    return read_registry_value(output, "(Default)")


def read_registry_value(output: str, value_name: str) -> str | None:
    for line in output.splitlines():
        match = re.match(r"^\s*(.*?)\s+REG_\w+\s+(.+?)\s*$", line)
        if match and match.group(1) == value_name:
            return strip_registry_string(match.group(2))
    return None


def strip_registry_string(value: str) -> str:
    match = re.fullmatch(r'"(.*)"', value)
    return match.group(1) if match else value

