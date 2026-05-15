from __future__ import annotations

import argparse
import datetime as dt
import json
import os
import re
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any

NODE_RUNTIME_RE = re.compile(r"\b(node|node_repl|npm|npx|pnpm|bun|deno|tsx|ts-node)\b", re.IGNORECASE)
NODE_SUFFIXES = {".js", ".mjs", ".cjs", ".ts", ".tsx", ".jsx"}
PACKAGE_FILES = {"package.json", "package-lock.json", "pnpm-lock.yaml", "yarn.lock", "bun.lockb"}
TEXT_SUFFIXES = {".json", ".toml", ".ps1", ".cmd", ".bat", ".py", ".md", ".yaml", ".yml", ".txt"}
SKIP_DIRS = {
    ".git",
    ".sandbox",
    ".sandbox-bin",
    ".sandbox-secrets",
    ".tmp",
    "__pycache__",
    "archived_sessions",
    "artifacts",
    "browser",
    "cache",
    "inventory",
    "log",
    "logs",
    "memories",
    "node_modules",
    "node_repl",
    "plugins",
    "reports",
    "sessions",
    "sqlite",
    "state",
    "tmp",
    "tools",
    "trajectories",
}
TOP_LEVEL_SCAN_FILES = {"AGENTS.md", "agent.md", "config.toml", "hooks.json", *PACKAGE_FILES}
SCAN_ROOTS = {"hooks", "maintenance/scripts", "toolchains"}
IMPORTANT_DOCS = {
    "AGENTS.md",
    "maintenance/AGENT_TOOL_REQUIREMENTS.md",
    "maintenance/MCP_RUNTIME_STATUS.md",
    "maintenance/WORKSTATION_MAINTENANCE.md",
}
SENSITIVE_FILES = {".codex-global-state.json", ".codex-global-state.json.bak", "models_cache.json", "session_index.jsonl"}
TOOLCHAIN_RUNTIME_WRAPPERS = {
    "bun.cmd",
    "deno.cmd",
    "node.cmd",
    "npm.cmd",
    "npx.cmd",
    "pnpm.cmd",
    "pnpx.cmd",
    "pnx.cmd",
    "tsc.cmd",
    "tsserver.cmd",
    "tsx.cmd",
}
SENSITIVE_NAME_RE = re.compile(r"(^\.env$|auth|credential|secret|token|key)", re.IGNORECASE)


@dataclass(frozen=True)
class Surface:
    surface_id: str
    current_owner: str
    current_path: str
    activation_surface: str
    runtime_type: str
    classification: str
    observed_problem: str
    memento_related: bool
    migration_decision: str
    replacement_contract: str
    risk_level: str
    approval_required: bool
    rollback: str
    evidence_required: list[str]
    matched_terms: list[str]


def rel_path(path: Path, root: Path) -> str:
    return path.resolve().relative_to(root.resolve()).as_posix()


def display_path(path: Path) -> str:
    home = Path.home().resolve()
    resolved = path.resolve()
    try:
        suffix = resolved.relative_to(home)
        return "%USERPROFILE%\\" + str(suffix)
    except ValueError:
        return str(resolved)


def is_relative_to(path: Path, parent: Path) -> bool:
    try:
        path.resolve().relative_to(parent.resolve())
        return True
    except ValueError:
        return False


def safe_slug(text: str) -> str:
    slug = re.sub(r"[^A-Za-z0-9]+", "-", text).strip("-").lower()
    return slug[:96] or "surface"


def should_skip_file(path: Path) -> bool:
    if path.name in SENSITIVE_FILES:
        return True
    return bool(SENSITIVE_NAME_RE.search(path.name))


def detect_runtime_type(path: Path, text: str) -> str | None:
    name = path.name.lower()
    suffix = path.suffix.lower()
    if name in PACKAGE_FILES:
        return "node"
    if suffix in NODE_SUFFIXES:
        return "js" if suffix in {".js", ".mjs", ".cjs", ".jsx"} else "ts"
    if NODE_RUNTIME_RE.search(text):
        if "npx" in text.lower():
            return "npx-backed"
        return "node"
    return None


def activation_surface(path: Path, root: Path) -> str:
    rel = rel_path(path, root)
    name = path.name.lower()
    if rel == "config.toml":
        return "config"
    if rel == "hooks.json" or rel.startswith("hooks/"):
        return "hook"
    if name in PACKAGE_FILES:
        return "package"
    if path.suffix.lower() in {".cmd", ".bat", ".ps1"}:
        return "script"
    return "file"


def owner_for(path: Path, root: Path) -> str:
    rel = rel_path(path, root)
    if rel.startswith("tools/") or rel.startswith("toolchains/"):
        return "local-chain"
    if rel.startswith("plugins/") or rel.startswith("cache/"):
        return "app-cache"
    if rel.startswith(("hooks/", "maintenance/", "runtime-migration/")):
        return "managed-source"
    if rel.startswith("skills/"):
        return "project-local"
    return "unknown"


def classification_for(path: Path, root: Path, surface: str) -> str:
    rel = rel_path(path, root)
    if rel.startswith("skills/"):
        return "skill/reference-only"
    if rel.startswith("runtime-migration/contracts/"):
        return "docs-only"
    if surface in {"config", "hook", "script", "package"}:
        return "active-runtime" if surface == "config" else "project-tooling"
    if path.suffix.lower() in {".md", ".txt"}:
        return "docs-only"
    return "unknown"


def migration_decision_for(memento_related: bool, classification: str) -> str:
    if memento_related:
        return "keep"
    if classification in {"docs-only", "skill/reference-only"}:
        return "keep"
    return "keep"


def build_surface(path: Path, root: Path, text: str, memento_roots: list[Path]) -> Surface | None:
    runtime_type = detect_runtime_type(path, text)
    if runtime_type is None:
        return None
    surface = activation_surface(path, root)
    rel = rel_path(path, root)
    memento_related = any(is_relative_to(path, item) for item in memento_roots if item.exists())
    classification = classification_for(path, root, surface)
    decision = migration_decision_for(memento_related, classification)
    matched_terms = sorted({match.group(1).lower() for match in NODE_RUNTIME_RE.finditer(text)})
    if path.name.lower() in PACKAGE_FILES:
        matched_terms.append(path.name.lower())
    return Surface(
        surface_id=safe_slug(f"{surface}-{rel}"),
        current_owner=owner_for(path, root),
        current_path=rel,
        activation_surface=surface,
        runtime_type=runtime_type,
        classification=classification,
        observed_problem="no-problem",
        memento_related=memento_related,
        migration_decision=decision,
        replacement_contract="capture before rewrite" if not memento_related else "excluded support-only Memento runtime",
        risk_level="observe",
        approval_required=False,
        rollback="no mutation; inventory only",
        evidence_required=["scanner output", "contract before rewrite"],
        matched_terms=matched_terms,
    )


def memento_marker(path: Path, root: Path, runtime_type: str) -> Surface:
    return Surface(
        surface_id=safe_slug(f"memento-{rel_path(path, root)}"),
        current_owner="local-chain",
        current_path=rel_path(path, root),
        activation_surface="managed-runtime",
        runtime_type=runtime_type,
        classification="active-runtime",
        observed_problem="no-problem",
        memento_related=True,
        migration_decision="keep",
        replacement_contract="excluded support-only Memento runtime",
        risk_level="observe",
        approval_required=False,
        rollback="no mutation; managed by maintenance/scripts/memento-mcp-runtime.ps1",
        evidence_required=["memento-mcp-runtime.ps1 verify", "doctor memento_runtime"],
        matched_terms=["memento"],
    )


def candidate_files(root: Path) -> list[Path]:
    files: list[Path] = []
    for filename in TOP_LEVEL_SCAN_FILES:
        path = root / filename
        if path.exists():
            files.append(path)
    for filename in IMPORTANT_DOCS:
        path = root / filename
        if path.exists():
            files.append(path)
    for dirname in SCAN_ROOTS:
        base = root / dirname
        if not base.exists():
            continue
        for dirpath, dirnames, filenames in os.walk(base):
            dirnames[:] = [name for name in dirnames if name not in SKIP_DIRS]
            current = Path(dirpath)
            for filename in filenames:
                files.append(current / filename)
    return sorted(set(files))


def scan(root: Path, memento_source_root: Path | None = None, memento_state_root: Path | None = None) -> list[Surface]:
    source_root = memento_source_root or root / "tools" / "memento-mcp"
    state_root = memento_state_root or root / "state" / "memento-mcp"
    memento_roots = [source_root, state_root]
    surfaces: list[Surface] = []
    for path in [source_root, state_root]:
        if path.exists():
            surfaces.append(memento_marker(path, root, "node" if path == source_root else "generated"))
    for path in candidate_files(root):
        if should_skip_file(path):
            continue
        rel = rel_path(path, root)
        if rel.startswith("toolchains/shims/") and path.name.lower() not in TOOLCHAIN_RUNTIME_WRAPPERS:
            continue
        if path.suffix.lower() == ".md" and rel_path(path, root) not in IMPORTANT_DOCS:
            continue
        suffix = path.suffix.lower()
        if path.name.lower() not in PACKAGE_FILES and suffix not in (TEXT_SUFFIXES | NODE_SUFFIXES):
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        surface = build_surface(path, root, text[:200000], memento_roots)
        if surface is not None:
            surfaces.append(surface)
    return sorted(surfaces, key=lambda item: item.current_path)


def yaml_scalar(value: Any) -> str:
    if isinstance(value, bool):
        return "true" if value else "false"
    if value is None:
        return "null"
    text = str(value)
    if text == "" or re.search(r"[%\\:#\[\]{}]|^\s|\s$|\n", text):
        return json.dumps(text)
    return text


def emit_yaml(data: dict[str, Any]) -> str:
    lines: list[str] = []

    def write_value(key: str, value: Any, indent: int) -> None:
        prefix = " " * indent
        if isinstance(value, dict):
            lines.append(f"{prefix}{key}:")
            for child_key, child_value in value.items():
                write_value(child_key, child_value, indent + 2)
        elif isinstance(value, list):
            lines.append(f"{prefix}{key}:")
            for item in value:
                if isinstance(item, dict):
                    lines.append(f"{prefix}  -")
                    for child_key, child_value in item.items():
                        write_value(child_key, child_value, indent + 4)
                else:
                    lines.append(f"{prefix}  - {yaml_scalar(item)}")
        else:
            lines.append(f"{prefix}{key}: {yaml_scalar(value)}")

    for key, value in data.items():
        write_value(key, value, 0)
    return "\n".join(lines) + "\n"


def report(root: Path, surfaces: list[Surface]) -> dict[str, Any]:
    return {
        "schema_version": 1,
        "generated_at": dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat(),
        "root": display_path(root),
        "scanner": {
            "mode": "read-only",
            "sensitive_content_emitted": False,
            "memento_exclusion": "paths under tools/memento-mcp or state/memento-mcp are keep-only",
        },
        "summary": {
            "surface_count": len(surfaces),
            "active_runtime_count": sum(1 for item in surfaces if item.classification == "active-runtime"),
            "memento_related_count": sum(1 for item in surfaces if item.memento_related),
        },
        "surfaces": [asdict(surface) for surface in surfaces],
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Read-only Node/JS surface scanner")
    parser.add_argument("--root", default=str(Path.home() / ".codex"))
    parser.add_argument("--output")
    parser.add_argument("--format", choices=["yaml", "json"], default="yaml")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    root = Path(args.root).expanduser().resolve()
    data = report(root, scan(root))
    rendered = json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n" if args.format == "json" else emit_yaml(data)
    if args.output:
        output = Path(args.output).expanduser().resolve()
        output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(rendered, encoding="utf-8", newline="\n")
    else:
        print(rendered, end="")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
