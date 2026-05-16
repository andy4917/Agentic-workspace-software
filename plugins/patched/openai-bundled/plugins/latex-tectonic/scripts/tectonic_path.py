from __future__ import annotations

import sys
from pathlib import Path


def get_tectonic_executable_path(plugin_root: str | Path | None = None) -> Path:
    root = Path(plugin_root).resolve() if plugin_root else Path(__file__).resolve().parent.parent
    executable_name = "tectonic.exe" if sys.platform == "win32" else "tectonic"
    executable_path = root / "bin" / executable_name
    if not executable_path.exists():
        raise RuntimeError(f"Bundled Tectonic executable not found at {executable_path}.")
    return executable_path


def main() -> int:
    try:
        print(get_tectonic_executable_path())
        return 0
    except Exception as error:
        print(str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())

