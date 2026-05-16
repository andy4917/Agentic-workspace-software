from __future__ import annotations

import argparse
import json
import os
import sys
from pathlib import Path

from chrome_common import (
    CHROME_NATIVE_HOST_MANIFEST_PATH_ENV,
    WINDOWS_NATIVE_HOST_REGISTRY_KEY_PREFIX,
    load_expected_extension_id,
    load_expected_host_name,
    read_json_file,
    read_windows_registry_default_value,
)


def get_native_host_manifest_location(
    expected_host_name: str,
) -> dict[str, object]:
    override = os.environ.get(CHROME_NATIVE_HOST_MANIFEST_PATH_ENV)
    if override:
        return {
            "manifestPath": str(Path(override).resolve()),
            "registryKey": None,
            "registryManifestPath": None,
            "registryKeyExists": None,
        }

    if sys.platform == "darwin":
        return {
            "manifestPath": str(
                Path.home()
                / "Library"
                / "Application Support"
                / "Google"
                / "Chrome"
                / "NativeMessagingHosts"
                / f"{expected_host_name}.json"
            ),
            "registryKey": None,
            "registryManifestPath": None,
            "registryKeyExists": None,
        }

    if sys.platform == "win32":
        registry_key = (
            f"{WINDOWS_NATIVE_HOST_REGISTRY_KEY_PREFIX}\\{expected_host_name}"
        )
        registry_manifest_path = read_windows_registry_default_value(registry_key)
        return {
            "manifestPath": registry_manifest_path
            or str(default_windows_manifest_path(expected_host_name)),
            "registryKey": registry_key,
            "registryManifestPath": registry_manifest_path,
            "registryKeyExists": registry_manifest_path is not None,
        }

    raise RuntimeError(
        "Unsupported platform for native host manifest check: "
        f"{sys.platform}. This script supports macOS and Windows."
    )


def default_windows_manifest_path(expected_host_name: str) -> Path:
    return Path.home() / "AppData" / "Local" / "OpenAI" / "extension" / (
        f"{expected_host_name}.json"
    )


def get_native_host_manifest_location_problem(
    location: dict[str, object], manifest_exists: bool
) -> str | None:
    problems: list[str] = []
    if location["registryKeyExists"] is False:
        problems.append(
            f"Windows native host registry key does not exist: {location['registryKey']}"
        )
    if not manifest_exists:
        problems.append(f"Native host manifest does not exist: {location['manifestPath']}")
    return "; ".join(problems) if problems else None


def read_native_host_manifest(path: Path) -> dict[str, object]:
    try:
        manifest = read_json_file(path)
    except Exception as error:
        raise RuntimeError(f"Could not read native host manifest {path}: {error}") from error
    if not isinstance(manifest, dict):
        raise RuntimeError(f"Native host manifest is not a JSON object: {path}")
    return manifest


def get_native_host_manifest_status() -> dict[str, object]:
    expected_extension_id = load_expected_extension_id()
    expected_host_name = load_expected_host_name()
    expected_origin = f"chrome-extension://{expected_extension_id}/"
    location = get_native_host_manifest_location(expected_host_name)
    manifest_path = Path(str(location["manifestPath"]))
    exists = manifest_path.exists()
    location_problem = get_native_host_manifest_location_problem(location, exists)

    base = {
        "manifestPath": str(manifest_path),
        "registryKey": location["registryKey"],
        "registryManifestPath": location["registryManifestPath"],
        "expectedHostName": expected_host_name,
        "expectedExtensionId": expected_extension_id,
        "expectedOrigin": expected_origin,
        "exists": exists,
    }
    if location_problem:
        return {**base, "correct": False, "problem": location_problem}

    manifest = read_native_host_manifest(manifest_path)
    allowed_origins = manifest.get("allowed_origins")
    if not isinstance(allowed_origins, list):
        allowed_origins = []
    name_matches = manifest.get("name") == expected_host_name
    has_expected_origin = expected_origin in allowed_origins
    registry_path = location["registryManifestPath"]
    registry_matches_manifest_path = (
        registry_path is None
        or Path(str(registry_path)).resolve() == manifest_path.resolve()
    )
    correct = name_matches and has_expected_origin and registry_matches_manifest_path

    return {
        **base,
        "actualHostName": manifest.get("name"),
        "allowedOrigins": allowed_origins,
        "nameMatches": name_matches,
        "hasExpectedOrigin": has_expected_origin,
        "registryMatchesManifestPath": registry_matches_manifest_path,
        "correct": correct,
        "problem": None
        if correct
        else describe_manifest_problem(
            expected_extension_id=expected_extension_id,
            expected_host_name=expected_host_name,
            name_matches=name_matches,
            has_expected_origin=has_expected_origin,
            registry_matches_manifest_path=registry_matches_manifest_path,
        ),
    }


def describe_manifest_problem(
    *,
    expected_extension_id: str,
    expected_host_name: str,
    name_matches: bool,
    has_expected_origin: bool,
    registry_matches_manifest_path: bool,
) -> str:
    problems: list[str] = []
    if not name_matches:
        problems.append(f"manifest name does not match {expected_host_name}")
    if not has_expected_origin:
        problems.append(
            "allowed_origins does not include "
            f"chrome-extension://{expected_extension_id}/"
        )
    if not registry_matches_manifest_path:
        problems.append("registry manifest path does not match checked manifest path")
    return "; ".join(problems)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="scripts/check_native_host_manifest.py",
        description="Check the Codex Chrome native host manifest.",
    )
    parser.add_argument("--json", action="store_true")
    return parser.parse_args(argv)


def print_text_report(result: dict[str, object]) -> None:
    print(f"Native host manifest: {result['manifestPath']}")
    if result.get("registryKey"):
        print(f"Windows registry key: {result['registryKey']}")
    if result.get("registryManifestPath"):
        print(f"Windows registry manifest path: {result['registryManifestPath']}")
    print(f"Expected host name: {result['expectedHostName']}")
    if result.get("actualHostName"):
        print(f"Actual host name: {result['actualHostName']}")
    print(f"Expected extension ID: {result['expectedExtensionId']}")
    print(f"Expected allowed origin: {result['expectedOrigin']}")
    if result.get("allowedOrigins"):
        print(f"Allowed origins: {', '.join(map(str, result['allowedOrigins']))}")
    print(f"Correct: {'yes' if result['correct'] else 'no'}")
    if result.get("problem"):
        print(f"Problem: {result['problem']}")


def main(argv: list[str] | None = None) -> int:
    try:
        args = parse_args(sys.argv[1:] if argv is None else argv)
        result = get_native_host_manifest_status()
        if args.json:
            print(json.dumps(result, indent=2))
        else:
            print_text_report(result)
        return 0 if result["correct"] else 1
    except SystemExit:
        raise
    except Exception as error:
        print(str(error), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())

