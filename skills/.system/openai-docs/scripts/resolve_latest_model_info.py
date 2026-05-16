from __future__ import annotations

import argparse
import json
import os
import re
import sys
from pathlib import Path
from typing import Any
from urllib.parse import urljoin, urlparse
from urllib.request import Request, urlopen


DEFAULT_URL = "https://developers.openai.com/api/docs/guides/latest-model.md"
DEFAULT_BASE_URL = "https://developers.openai.com"


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Resolve latest OpenAI model guide links")
    parser.add_argument("--source", "--url", default=os.environ.get("LATEST_MODEL_URL", DEFAULT_URL))
    parser.add_argument("--base-url", default=os.environ.get("LATEST_MODEL_BASE_URL", DEFAULT_BASE_URL))
    return parser


def read_source(source: str) -> str:
    parsed = urlparse(source)
    if parsed.scheme == "file":
        return Path(parsed.path).read_text(encoding="utf-8")

    if parsed.scheme not in {"http", "https"}:
        return Path(source).resolve().read_text(encoding="utf-8")

    request = Request(source, headers={"accept": "text/markdown,text/plain,*/*"})
    with urlopen(request, timeout=20) as response:
        status = getattr(response, "status", 200)
        if status < 200 or status >= 300:
            raise RuntimeError(f"failed to fetch {source}: {status}")
        return response.read().decode("utf-8")


def strip_quotes(value: str) -> str:
    return re.sub(r"^[\"']|[\"']$", "", value)


def parse_indented_info(lines: list[str], start_index: int) -> dict[str, str]:
    info: dict[str, str] = {}
    for line in lines[start_index + 1 :]:
        if not line.strip():
            continue
        match = re.match(r"^ {2}([A-Za-z][A-Za-z0-9_-]*):\s*(.+?)\s*$", line)
        if not match:
            break
        info[match.group(1)] = strip_quotes(match.group(2))
    return info


def parse_flat_info(block: str) -> dict[str, str]:
    info: dict[str, str] = {}
    for line in block.splitlines():
        match = re.match(r"^\s*([A-Za-z][A-Za-z0-9_-]*):\s*(.+?)\s*$", line)
        if match:
            info[match.group(1)] = strip_quotes(match.group(2))
    return info


def extract_latest_model_info(markdown: str) -> dict[str, str] | None:
    lines = markdown.splitlines()
    for index, line in enumerate(lines):
        if re.match(r"^latestModelInfo:\s*$", line):
            return parse_indented_info(lines, index)

    comment_match = re.search(r"<!--\s*latestModelInfo\s*\n([\s\S]*?)\n\s*-->", markdown, re.MULTILINE)
    if comment_match:
        return parse_flat_info(comment_match.group(1))

    return None


def model_to_skill_slug(model: str) -> str:
    return model.strip().replace(".", "p")


def absolute_url(base_url: str, value: str) -> str:
    return urljoin(base_url, value)


def normalize_info(info: dict[str, str] | None, base_url: str) -> dict[str, Any]:
    model = (info or {}).get("model", "").strip()
    migration_guide = (info or {}).get("migrationGuide", "").strip()
    prompting_guide = (info or {}).get("promptingGuide", "").strip()

    if not model or not migration_guide or not prompting_guide:
        raise RuntimeError("latestModelInfo must include model, migrationGuide, and promptingGuide")

    return {
        "model": model,
        "modelSlug": model_to_skill_slug(model),
        "migrationGuideUrl": absolute_url(base_url, migration_guide),
        "promptingGuideUrl": absolute_url(base_url, prompting_guide),
    }


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    markdown = read_source(args.source)
    info = extract_latest_model_info(markdown)
    if not info:
        raise RuntimeError(f"latestModelInfo block not found in {args.source}")
    print(json.dumps(normalize_info(info, args.base_url), indent=2))
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as error:
        print(str(error), file=sys.stderr)
        raise SystemExit(1)
