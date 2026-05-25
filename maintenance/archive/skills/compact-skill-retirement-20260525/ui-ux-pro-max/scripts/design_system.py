#!/usr/bin/env python3
"""Public entrypoint for ui-ux-pro-max design system generation."""

import sys
from pathlib import Path

_SCRIPT_DIR = Path(__file__).resolve().parent
if str(_SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(_SCRIPT_DIR))

from design_system_core import DesignSystemGenerator, generate_design_system
from design_system_format import format_ascii_box, format_markdown
from design_system_persistence import (
    format_master_md,
    format_page_override_md,
    persist_design_system,
)

__all__ = [
    "DesignSystemGenerator",
    "format_ascii_box",
    "format_markdown",
    "format_master_md",
    "format_page_override_md",
    "generate_design_system",
    "persist_design_system",
]


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(description="Generate Design System")
    parser.add_argument("query", help="Search query (e.g., 'SaaS dashboard')")
    parser.add_argument("--project-name", "-p", type=str, default=None, help="Project name")
    parser.add_argument("--format", "-f", choices=["ascii", "markdown"], default="ascii", help="Output format")
    args = parser.parse_args()
    print(generate_design_system(args.query, args.project_name, args.format))


if __name__ == "__main__":
    main()
