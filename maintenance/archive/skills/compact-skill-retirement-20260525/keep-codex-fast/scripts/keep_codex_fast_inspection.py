"""Read-only inspection helpers for keep_codex_fast.py."""

from keep_codex_fast_core import *

def inspect_marketplace_sources(codex_home: Path, config: dict, policy: dict) -> None:
    marketplaces = config.get("marketplaces", {}) if isinstance(config, dict) else {}
    if not isinstance(marketplaces, dict):
        report("marketplace_sources 0")
        return

    allowed_roots = policy_list(policy, "allowed_marketplace_source_roots", [])
    forbidden = policy_list(
        policy,
        "forbidden_active_source_fragments",
        DEFAULT_FORBIDDEN_ACTIVE_SOURCE_FRAGMENTS,
    )
    source_count = 0
    bad_count = 0
    for marketplace_id, value in sorted(marketplaces.items()):
        if not isinstance(value, dict) or not value.get("source"):
            continue
        source_count += 1
        source = Path(str(value["source"]))
        exists = source.exists()
        forbidden_hit = path_has_fragment(source, forbidden)
        allowed_hit = not allowed_roots or is_under_any_root(source, allowed_roots)
        status = "ok" if exists and not forbidden_hit and allowed_hit else "needs_attention"
        if status != "ok":
            bad_count += 1
        report(f"marketplace_source {marketplace_id} {status} exists={int(exists)} allowed={int(allowed_hit)} forbidden={int(forbidden_hit)} {source}")
    report(f"marketplace_sources {source_count}")
    report(f"marketplace_source_issues {bad_count}")


def load_app_tool_cache(path: Path) -> list[dict]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except Exception as exc:
        report(f"codex_apps_tools_cache_parse_error {path.name} {exc}")
        return []
    tools = data.get("tools", []) if isinstance(data, dict) else []
    return [tool for tool in tools if isinstance(tool, dict)]


def archive_unexpected_app_tool_caches(
    files: list[Path],
    codex_home: Path,
    backup_root: Path,
    stamp: str,
    apply: bool,
) -> None:
    if not files:
        return
    report(f"codex_apps_tools_unexpected_cache_files {len(files)}")
    if not apply:
        return

    archive_root = codex_home / "archived_app_tool_caches" / f"keep-codex-fast-{stamp}"
    manifest = backup_root / "moved-app-tool-caches.jsonl"
    archive_root.mkdir(parents=True, exist_ok=True)
    with manifest.open("w", encoding="utf-8") as handle:
        for source in files:
            dest = archive_root / source.name
            shutil.move(str(source), str(dest))
            handle.write(json.dumps({"from": str(source), "to": str(dest)}, ensure_ascii=False) + "\n")
    report(f"codex_apps_tools_archive_root {archive_root}")
    report(f"codex_apps_tools_manifest {manifest}")


def inspect_codex_apps_tools_cache(
    codex_home: Path,
    policy: dict,
    backup_root: Path,
    stamp: str,
    apply: bool,
) -> None:
    root = codex_home / "cache" / "codex_apps_tools"
    files = sorted(root.glob("*.json")) if root.exists() else []
    report(f"codex_apps_tools_cache_files {len(files)}")
    if not files:
        return

    expected = {item.lower() for item in policy_list(policy, "expected_app_connectors", [])}
    unexpected = {
        item.lower()
        for item in policy_list(policy, "unexpected_app_connectors", DEFAULT_UNEXPECTED_APP_CONNECTORS)
    }
    unexpected_namespaces = {
        item.lower()
        for item in policy_list(
            policy,
            "unexpected_app_tool_namespaces",
            DEFAULT_UNEXPECTED_TOOL_NAMESPACES,
        )
    }
    connector_counts: dict[str, int] = {}
    namespace_counts: dict[str, int] = {}
    unexpected_files: set[Path] = set()
    for path in files:
        tools = load_app_tool_cache(path)
        for tool in tools:
            connector = str(tool.get("connector_name") or "")
            namespace = str(tool.get("tool_namespace") or "")
            connector_counts[connector] = connector_counts.get(connector, 0) + 1
            namespace_counts[namespace] = namespace_counts.get(namespace, 0) + 1
            connector_key = connector.lower()
            namespace_key = namespace.lower()
            if connector_key in unexpected or namespace_key in unexpected_namespaces:
                unexpected_files.add(path)
            if expected and connector_key and connector_key not in expected:
                unexpected_files.add(path)

    for connector, count in sorted(connector_counts.items(), key=lambda item: item[0].lower()):
        report(f"codex_apps_tools_connector {connector or '<missing>'} {count}")
    for namespace, count in sorted(namespace_counts.items(), key=lambda item: item[0].lower()):
        report(f"codex_apps_tools_namespace {namespace or '<missing>'} {count}")
    archive_unexpected_app_tool_caches(
        sorted(unexpected_files),
        codex_home,
        backup_root,
        stamp,
        apply,
    )
    if not unexpected_files:
        report("codex_apps_tools_unexpected_cache_files 0")


def should_skip_audit_dir(path: Path, codex_home: Path) -> bool:
    if path.name in TEXT_AUDIT_EXCLUDED_DIRS:
        return True
    try:
        rel = path.relative_to(codex_home)
    except ValueError:
        return False
    parts = tuple(rel.parts)
    return any(parts[: len(prefix)] == prefix for prefix in TEXT_AUDIT_EXCLUDED_RELS)


def iter_audit_text_files(root: Path, codex_home: Path):
    if not root.exists():
        return
    for path in root.rglob("*"):
        if path.is_dir():
            continue
        if path.name == "config.toml" and path.parent == codex_home:
            continue
        if path.suffix.lower() not in TEXT_AUDIT_SUFFIXES:
            continue
        try:
            if path.stat().st_size > 2 * 1024 * 1024:
                continue
        except OSError:
            continue
        yield path


def inspect_deleted_path_references(codex_home: Path) -> None:
    roots = [
        codex_home / "hooks",
        codex_home / "Maintenance",
        codex_home / "skills" / "keep-codex-fast",
    ]
    direct_files = [
        path
        for path in codex_home.iterdir()
        if path.is_file() and path.suffix.lower() in TEXT_AUDIT_SUFFIXES and path.name != "config.toml"
    ]
    stale_roots = [
        codex_home / ".tmp",
        codex_home / "tmp",
        codex_home / "vendor_imports",
        codex_home / "wshobson-agents-scan",
        codex_home / "plugins" / "plugins",
    ]
    needles = [norm_text_path(path) for path in stale_roots]
    hits: list[str] = []

    for path in direct_files:
        try:
            text = path.read_text(encoding="utf-8", errors="ignore")
        except Exception:
            continue
        normalized = norm_text_path(text)
        if any(needle in normalized for needle in needles):
            hits.append(str(path))

    for root in roots:
        if not root.exists():
            continue
        for dirpath, dirnames, filenames in os.walk(root):
            current = Path(dirpath)
            dirnames[:] = [
                name
                for name in dirnames
                if not should_skip_audit_dir(current / name, codex_home)
            ]
            for filename in filenames:
                path = current / filename
                if path.suffix.lower() not in TEXT_AUDIT_SUFFIXES:
                    continue
                try:
                    if path.stat().st_size > 2 * 1024 * 1024:
                        continue
                    text = path.read_text(encoding="utf-8", errors="ignore")
                except Exception:
                    continue
                normalized = norm_text_path(text)
                if any(needle in normalized for needle in needles):
                    hits.append(str(path))

    report(f"deleted_temp_path_references {len(hits)}")
    for hit in hits[:10]:
        report(f"deleted_temp_path_reference {hit}")


def inspect_nested_git_repositories(codex_home: Path) -> None:
    repos = sorted(path.parent for path in codex_home.rglob(".git") if path.is_dir())
    report(f"nested_git_repositories {len(repos)}")
    for repo in repos[:25]:
        dirty = "unknown"
        try:
            proc = subprocess.run(
                ["git", "-C", str(repo), "status", "--porcelain"],
                text=True,
                capture_output=True,
                timeout=10,
                check=False,
            )
            if proc.returncode == 0:
                dirty = str(len([line for line in proc.stdout.splitlines() if line.strip()]))
        except Exception:
            pass
        report(f"nested_git_repository dirty={dirty} {repo}")


def inspect_same_name_nested_dirs(codex_home: Path) -> None:
    hits: list[Path] = []
    for dirpath, dirnames, _filenames in os.walk(codex_home):
        current = Path(dirpath)
        dirnames[:] = [
            name
            for name in dirnames
            if not should_skip_audit_dir(current / name, codex_home)
        ]
        if current == codex_home:
            continue
        parent = current.parent
        if current.name.lower() == parent.name.lower():
            hits.append(current)
    report(f"same_name_nested_directories {len(hits)}")
    for hit in hits[:10]:
        report(f"same_name_nested_directory {hit}")


def inspect_naming_convention(
    codex_home: Path,
    config: dict,
    backup_root: Path,
    stamp: str,
    apply: bool,
) -> None:
    policy = naming_policy(config)
    profile = str(policy.get("profile", "")) if policy else ""
    report(f"naming_convention {'present' if policy else 'missing'} {profile}".rstrip())
    if not policy:
        return

    transient_names = {item.lower() for item in policy_list(policy, "transient_root_names", [])}
    active_roots = policy_list(policy, "normal_active_source_roots", [])
    forbidden_fragments = policy_list(policy, "forbidden_active_source_name_fragments", [])

    transient_hits = []
    for child in codex_home.iterdir():
        if child.is_dir() and child.name.lower() in transient_names:
            transient_hits.append(child)
    report(f"naming_transient_root_hits {len(transient_hits)}")
    for hit in transient_hits[:10]:
        report(f"naming_transient_root_hit {hit}")
    if apply and transient_hits:
        archive_root = codex_home / "archived_transient_roots" / f"keep-codex-fast-{stamp}"
        manifest = backup_root / "moved-transient-roots.jsonl"
        archive_root.mkdir(parents=True, exist_ok=True)
        with manifest.open("w", encoding="utf-8") as handle:
            for source in transient_hits:
                source_resolved = source.resolve()
                if source_resolved.parent != codex_home.resolve():
                    report(f"naming_transient_root_archive_skipped_outside_root {source}")
                    continue
                dest = archive_root / source.name
                shutil.move(str(source), str(dest))
                handle.write(json.dumps({"from": str(source), "to": str(dest)}, ensure_ascii=False) + "\n")
        report(f"naming_transient_root_archive_root {archive_root}")
        report(f"naming_transient_root_manifest {manifest}")

    active_issues = []
    for root in active_roots:
        path = codex_home / root
        if not path.exists():
            continue
        for parent, dirnames, _filenames in os.walk(path):
            current = Path(parent)
            dirnames[:] = [
                name
                for name in dirnames
                if name not in TEXT_AUDIT_EXCLUDED_DIRS and name != ".git"
            ]
            if any(fragment.lower() in current.name.lower() for fragment in forbidden_fragments):
                active_issues.append(current)
    report(f"naming_active_source_name_issues {len(active_issues)}")
    for issue in active_issues[:10]:
        report(f"naming_active_source_name_issue {issue}")


def inspect_contamination_surfaces(
    codex_home: Path,
    config: dict,
    backup_root: Path,
    stamp: str,
    apply: bool,
) -> None:
    policy = contamination_policy(config)
    profile = str(policy.get("profile", "")) if policy else ""
    report(f"contamination_policy {'present' if policy else 'missing'} {profile}".rstrip())
    inspect_marketplace_sources(codex_home, config, policy)
    inspect_codex_apps_tools_cache(codex_home, policy, backup_root, stamp, apply)
    inspect_naming_convention(codex_home, config, backup_root, stamp, apply)
    inspect_nested_git_repositories(codex_home)
    inspect_same_name_nested_dirs(codex_home)
    inspect_deleted_path_references(codex_home)
