"""Small deterministic Codex harness for the local CODEX_HOME root.

This intentionally does not clone external harnesses. It distills the local
operating rules into reversible, state-tracked commands.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import re
import shutil
import stat
import subprocess
import sys
import tomllib
from pathlib import Path
from typing import Any

from codex_agent_harness_calibration import CALIBRATION_EVAL_TEMPLATE, CALIBRATION_ROLE_CONFIG
SCHEMA_VERSION = "1"
RUBRIC_VERSION = "codex-harness-audit-v1"
OWNER = "codex-agent-harness"
DEFAULT_PROFILE = "developer"
SOURCE_PLAN = Path.home() / "Downloads" / "codex-agent-harness-distillation-plan.md"
COMMAND_PREVIEW_CHARS = 4000
COMMAND_ARTIFACT_THRESHOLD_CHARS = 12000
TRAJECTORY_VERSION = "codex-trajectory-v1"
DOCTOR_TIERS = {
    "core": ["config", "harness_engine_modules", "calibration_policy", "hook_tool_routing", "managed_files", "skill_frontmatter", "harness_file_size", "stale_active_references", "sentinel_blockers"],
    "extended": ["config", "pm_subagent_protocol", "harness_engine_modules", "app_runtime_state_writable", "generated_outputs_untracked", "compact_hook_contract", "subagent_nickname_policy", "calibration_policy", "hook_tool_routing", "managed_files", "skill_frontmatter", "harness_file_size", "workspace_script_file_size", "stale_active_references", "sentinel_blockers"],
    "stress": ["config", "harness_engine_modules", "generated_outputs_untracked", "calibration_policy", "managed_files", "harness_file_size", "stale_active_references", "sentinel_blockers"],
}
DOCTOR_TIERS["full"] = list(dict.fromkeys(DOCTOR_TIERS["extended"] + DOCTOR_TIERS["stress"]))

MODULES: dict[str, dict[str, str]] = {
    "codex-baseline": {"purpose": "Codex baseline config, global instructions, and role agents"},
    "rules-core": {"purpose": "Durable instruction and context-loading rules"},
    "skills-core": {"purpose": "Compact repo-local skill index and draft isolation"},
    "workflow-quality": {"purpose": "Verification, compaction, learning, and report workflows"},
    "security": {"purpose": "Secret hygiene and external action boundaries"},
    "orchestration": {"purpose": "Multi-agent role routing and iterative retrieval guidance"},
    "mcp-baseline": {"purpose": "Safe MCP recommendations and loading diagnostics"},
    "benchmarking": {"purpose": "Small deterministic eval and benchmark harness"},
}

PROFILES: dict[str, list[str]] = {
    "minimal": ["codex-baseline", "rules-core"],
    "core": ["codex-baseline", "rules-core", "skills-core", "workflow-quality", "mcp-baseline"],
    "developer": ["codex-baseline", "rules-core", "skills-core", "workflow-quality", "mcp-baseline", "benchmarking", "orchestration"],
    "security": ["codex-baseline", "rules-core", "skills-core", "workflow-quality", "security"],
    "full": list(MODULES),
}

ROLE_CONFIGS = {
    "agents/explorer.toml": """# Managed by codex-agent-harness.
name = "explorer"
description = "Focused read-only codebase and environment exploration for bounded evidence gathering."
developer_instructions = \"\"\"
Goal: gather focused evidence before implementation.
Stay read-oriented unless the PM explicitly assigns a write surface.
Lead with findings, evidence checked, not checked items, and risks.
Do not claim PASS or completion as authority.
\"\"\"
nickname_candidates = ["EXP-Scout", "EXP-Mapper", "EXP-Probe"]
# nickname_prefix = "EXP"
# required_delegation_fields, required_output_sections, success_claim_policy,
# and reward_hacking_guard are documented in maintenance/SUBAGENT_DELEGATION_CHARTER.md.
""",
    "agents/reviewer.toml": """# Managed by codex-agent-harness.
name = "reviewer"
description = "Independent read-only review for correctness, security, test gaps, and maintainability risks."
developer_instructions = \"\"\"
Goal: review correctness, security, behavior, missing tests, and maintainability.
Lead with blocking findings, evidence checked, not checked items, and residual risks.
Do not approve by summary or unsupported PASS claims.
\"\"\"
nickname_candidates = ["REV-Auditor", "REV-Critic", "REV-Verifier"]
# nickname_prefix = "REV"
# required_delegation_fields, required_output_sections, success_claim_policy,
# and reward_hacking_guard are documented in maintenance/SUBAGENT_DELEGATION_CHARTER.md.
""",
    "agents/docs-researcher.toml": """# Managed by codex-agent-harness.
name = "docs-researcher"
description = "Primary-source documentation research for version-sensitive OpenAI, MCP, and toolchain claims."
developer_instructions = \"\"\"
Goal: verify version-sensitive claims against primary documentation.
Use primary sources first. Report what the source proves, what it does not prove,
not checked items, and version risks.
\"\"\"
nickname_candidates = ["DOC-Source", "DOC-Cite", "DOC-Archivist"]
# nickname_prefix = "DOC"
# required_delegation_fields, required_output_sections, success_claim_policy,
# and reward_hacking_guard are documented in maintenance/SUBAGENT_DELEGATION_CHARTER.md.
""",
}

ROLE_CONFIGS["agents/calibration-verifier.toml"] = CALIBRATION_ROLE_CONFIG

DELEGATION_CHARTER = """# Subagent Delegation Charter

Use this charter whenever the PM delegates non-trivial work to a subagent.
The charter makes reward hacking uneconomical: unsupported completion claims
do not help the PM, while precise blockers and verifiable evidence do.

## Required Delegation Fields

Every delegated task must include:

- `Goal`: the concrete subtask the subagent owns.
- `Purpose`: why this subtask matters to the overall PM objective, which risk it reduces, and which decision it informs.
- `PM Context`: facts the PM already knows, claims the PM does not trust yet, and assumptions the subagent must challenge.
- `Owned Surface`: files, directories, commands, docs, or runtime surfaces the subagent may inspect or modify.
- `Out Of Scope`: surfaces the subagent must not touch.
- `Authority`: evidence only unless the PM explicitly assigned a bounded write surface; no subagent may mark the PM parent goal complete.
- `Expected Evidence`: paths, line references, commands, diffs, reproduction steps, or source citations the PM can independently verify.
- `Anti-Reward-Hacking Rules`: explicit invalid-success cases for this task.
- `Mid-Report`: inspected surfaces, preliminary findings, next checks, blockers, and not-yet-checked items.
- `Exit Criteria`: what counts as a useful handoff, including completion and completion-impossible conditions.
- `Not Checked`: required final disclosure of skipped, inaccessible, stale, fallback, or not-run checks.

## Authority Boundary

The PM owns the parent goal and the completion decision. Subagents own only their bounded subgoal and the evidence package they return. A subagent report may reduce uncertainty, expose a blocker, or recommend PM verification, but it cannot complete, pause, clear, or redefine the PM goal.

## Required Output Order

Subagent final reports must lead with evidence, not reassurance:

1. Blocking findings.
2. Major risks.
3. Evidence checked.
4. Not checked.
5. PM verification suggestions.
6. Brief summary only after the sections above.

## Invalid Success Claims

The PM must treat these as unsupported until independently verified:

- `PASS`, `complete`, or `no issues` without direct evidence.
- Counting `not-run`, skipped, fallback, stale, or inaccessible checks as success.
- Reporting only files changed without explaining why the task mattered.
- Omitting the delegated purpose or PM context.
- Hiding uncertainty to make the result look simpler.
- Treating a subagent report, MCP result, test pass, or citation as final authority.
- Treating a subagent subgoal or thread status as PM parent-goal completion.

## Replacement Rule

If a subagent hides failures, violates the charter, claims success without
evidence, or optimizes for PM approval rather than truth, the PM must close
that agent, start a replacement with a handoff that names the failure mode, and
independently verify the affected surface.
"""

SKILL_TEMPLATES: dict[str, str] = {}

EVAL_TEMPLATES = {
    "evals/config-parse.json": {
        "eval_id": "config-parse",
        "task": "Parse root config.toml with Python tomllib.",
        "setup": "Run from CODEX_HOME.",
        "success_criteria": ["config.toml parses", "stable workflow feature keys are present"],
        "grader": "python maintenance/scripts/codex_agent_harness.py doctor --json",
        "timeout_seconds": 30,
        "risk_notes": "Does not prove app runtime reloaded the config.",
    },
    "evals/managed-files.json": {
        "eval_id": "managed-files",
        "task": "Verify harness-managed files are present and match install-state digests.",
        "setup": "Run after harness apply.",
        "success_criteria": ["install-state exists", "managed files exist", "digests match"],
        "grader": "python maintenance/scripts/codex_agent_harness.py doctor --json",
        "timeout_seconds": 30,
        "risk_notes": "Only checks files owned by this harness.",
    },
    "evals/audit-threshold.json": {
        "eval_id": "audit-threshold",
        "task": "Run deterministic harness audit and require no critical failures.",
        "setup": "Run after harness apply.",
        "success_criteria": ["audit JSON exists", "overall audit status is pass"],
        "grader": "python maintenance/scripts/codex_agent_harness.py audit --json",
        "timeout_seconds": 30,
        "risk_notes": "Score is deterministic but intentionally conservative.",
    },
    "evals/context-inspection.json": {
        "eval_id": "context-inspection",
        "task": "Generate deterministic context selection report.",
        "setup": "Run from CODEX_HOME.",
        "success_criteria": ["context report exists", "selected instruction source is explicit"],
        "grader": "python maintenance/scripts/codex_agent_harness.py context",
        "timeout_seconds": 30,
        "risk_notes": "Does not prove the app injected the selected context into a live turn.",
    },
    "evals/trajectory-search.json": {
        "eval_id": "trajectory-search",
        "task": "Verify trajectory JSONL search path remains usable.",
        "setup": "Run after at least one verification or benchmark.",
        "success_criteria": ["trajectory command exits successfully", "recent listing is JSON"],
        "grader": "python maintenance/scripts/codex_agent_harness.py trajectory --recent 5",
        "timeout_seconds": 30,
        "risk_notes": "Checks local harness trajectory records only.",
    },
    "evals/orchestration-governance-smoke.json": {
        "eval_id": "orchestration-governance-smoke",
        "task": "Verify the local Goal governance policy, templates, and Stop hook audit prompt shape.",
        "setup": "Run from CODEX_HOME after goal governance policy/template changes.",
        "success_criteria": [
            "AGENTS.md records Goal as a tracking marker and PM-owned completion audit",
            "Subagent delegation charter states evidence-only authority",
            "Goal templates require checked, not-run, risks, and PM independent verification",
            "Stop hook synthetic input blocks missing audit and allows audit-present final text",
        ],
        "grader": "python maintenance/scripts/codex_agent_harness.py eval --eval-id orchestration-governance-smoke",
        "timeout_seconds": 30,
        "risk_notes": "Structural smoke test only; it does not prove runtime hook coverage for every tool surface.",
    },
    "evals/rg-resolution-smoke.json": {
        "eval_id": "rg-resolution-smoke",
        "task": "Verify ripgrep resolution uses the Codex bundle and the rg shim is available through supported invocation paths.",
        "setup": "Run from CODEX_HOME on Windows after toolchain or PATH-related changes.",
        "success_criteria": [
            "Persistent User/Machine PATH does not contain the managed shim root",
            "Bare rg resolves to a Codex-owned source and runs",
            "Explicit rg.ps1 shim invocation runs and preserves cmd metacharacter arguments",
            "rg.cmd remains a cmd.exe compatibility shim for simple or escaped arguments",
            "New pwsh can run rg.ps1 and new cmd can run rg.cmd with process-local PATH",
            "Bare rg.cmd without process-local PATH and unescaped rg.cmd metacharacters from PowerShell are documented as unsupported"
        ],
        "grader": "powershell.exe -NoProfile -ExecutionPolicy Bypass -File maintenance/scripts/check-rg-resolution.ps1",
        "timeout_seconds": 30,
        "risk_notes": "Windows-specific resolver smoke test; it does not mutate persistent PATH.",
    },
    "evals/doctor-tier-smoke.json": {
        "eval_id": "doctor-tier-smoke",
        "task": "Verify doctor tiering keeps core managed-source checks separate from heavier stress/full checks.",
        "setup": "Run from CODEX_HOME after doctor tier or runtime-health changes.",
        "success_criteria": [
            "core doctor excludes generated_outputs_untracked",
            "stress doctor includes generated_outputs_untracked",
            "full doctor remains backward-compatible and includes both core and stress checks"
        ],
        "grader": "python maintenance/scripts/codex_agent_harness.py eval --eval-id doctor-tier-smoke",
        "timeout_seconds": 60,
        "risk_notes": "Structural tiering smoke; it does not depend on retired Memento runtime state.",
    },
    "evals/repo-verify.json": {
        "eval_id": "repo-verify",
        "task": "Run the CI-capable managed-source verification path that does not require live private runtime state.",
        "setup": "Run from CODEX_HOME or a Windows CI checkout.",
        "success_criteria": [
            "tracked Python harness files compile",
            "tracked JSON eval and hook policy files parse",
            "PowerShell managed scripts parse",
            "repo-safe calibration smoke does not require ignored private config.toml",
            "mutable generated outputs are not tracked"
        ],
        "grader": "python maintenance/scripts/codex_agent_harness.py repo-verify",
        "timeout_seconds": 120,
        "risk_notes": "Does not prove live MCP, Memento, browser, or ignored config state.",
    },
}

EVAL_TEMPLATES["evals/calibration-policy-smoke.json"] = CALIBRATION_EVAL_TEMPLATE

from worker_watcher_templates import (
    DELEGATION_CHARTER as WORKER_WATCHER_DELEGATION_CHARTER,
    EVAL_TEMPLATES as WORKER_WATCHER_EVAL_TEMPLATES,
    ROLE_CONFIGS as WORKER_WATCHER_ROLE_CONFIGS,
    SKILL_TEMPLATES as WORKER_WATCHER_SKILL_TEMPLATES,
    WORKER_WATCHER_TEMPLATES,
)

ROLE_CONFIGS.update(WORKER_WATCHER_ROLE_CONFIGS)
SKILL_TEMPLATES.update(WORKER_WATCHER_SKILL_TEMPLATES)
EVAL_TEMPLATES.update(WORKER_WATCHER_EVAL_TEMPLATES)
DELEGATION_CHARTER += WORKER_WATCHER_DELEGATION_CHARTER
def utc_now() -> str:
    return dt.datetime.now(dt.timezone.utc).replace(microsecond=0).isoformat()


def local_stamp() -> str:
    return dt.datetime.now().strftime("%Y%m%d-%H%M%S")


def root_path(args: argparse.Namespace) -> Path:
    configured = getattr(args, "root", None)
    if configured in (None, "", "auto"):
        return Path(__file__).resolve().parents[2]
    return Path(configured).expanduser().resolve()


def rel(path: Path, root: Path) -> str:
    return path.resolve().relative_to(root.resolve()).as_posix()


def ensure_dir(path: Path) -> None:
    path.mkdir(parents=True, exist_ok=True)


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def write_text(path: Path, content: str) -> None:
    ensure_dir(path.parent)
    path.write_text(content, encoding="utf-8", errors="replace", newline="\n")


def write_json(path: Path, data: Any) -> None:
    write_text(path, json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + "\n")


def append_jsonl(path: Path, data: Any) -> None:
    ensure_dir(path.parent)
    with path.open("a", encoding="utf-8", newline="\n") as f:
        f.write(json.dumps(data, ensure_ascii=False, sort_keys=True) + "\n")


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def harness_source_files(root: Path) -> list[Path]:
    files = list((root / "maintenance" / "scripts").glob("codex_agent_harness*.py"))
    extra = [
        "AGENTS.md", "CALIBRATION.md", "config.toml",
        "config.d/20-hooks.toml", "hooks/compact-codex-hook.ps1",
        "agents/calibration-verifier.toml",
        "evals/calibration-eval.yaml", "evals/calibration-policy-smoke.json",
    ]
    files.extend(root / item for item in extra if (root / item).exists())
    return sorted(files)


def harness_source_digest(root: Path) -> str:
    h = hashlib.sha256()
    for path in harness_source_files(root):
        h.update(rel(path, root).encode("utf-8"))
        h.update(b"\0")
        h.update(sha256_file(path).encode("ascii"))
        h.update(b"\0")
    return h.hexdigest()


def load_json(path: Path, default: Any) -> Any:
    if not path.exists():
        return default
    return json.loads(read_text(path))


def install_state_path(root: Path) -> Path:
    return root / ".codex-harness" / "install-state.json"


def selected_modules(profile: str, modules: list[str] | None = None) -> list[str]:
    if modules:
        unknown = [m for m in modules if m not in MODULES]
        if unknown:
            raise SystemExit(f"Unknown modules: {', '.join(unknown)}")
        return modules
    if profile not in PROFILES:
        raise SystemExit(f"Unknown profile: {profile}")
    return PROFILES[profile]


def wrapper_script(command: str) -> str:
    return f"""param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Args)
$ErrorActionPreference = 'Stop'
$Script = Join-Path $PSScriptRoot 'codex_agent_harness.py'
$DefaultRoot = Join-Path $env:USERPROFILE 'Documents\\Codex'
$RootArgs = @()
if (Test-Path -LiteralPath $DefaultRoot -PathType Container) {{
    $RootArgs = @('--root', $DefaultRoot)
}}
python $Script @RootArgs {command} @Args
exit $LASTEXITCODE
"""


def managed_templates(root: Path, modules: list[str]) -> dict[str, str]:
    templates: dict[str, str] = {}

    templates[".codex-harness/manifests/modules.json"] = json.dumps(MODULES, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    templates[".codex-harness/manifests/profiles.json"] = json.dumps(PROFILES, ensure_ascii=False, indent=2, sort_keys=True) + "\n"
    templates[".codex-harness/schemas/install-state.schema.json"] = json.dumps(
        {
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "title": "Codex Harness Install State",
            "type": "object",
            "required": ["schema_version", "installed_at", "target", "requested_profile", "selected_modules", "applied_operations"],
            "properties": {
                "schema_version": {"type": "string"},
                "installed_at": {"type": "string"},
                "target": {"type": "object"},
                "requested_profile": {"type": "string"},
                "requested_modules": {"type": "array"},
                "selected_modules": {"type": "array"},
                "skipped_modules": {"type": "array"},
                "source": {"type": "object"},
                "applied_operations": {"type": "array"},
            },
        },
        ensure_ascii=False,
        indent=2,
        sort_keys=True,
    ) + "\n"

    if "codex-baseline" in modules or "orchestration" in modules:
        templates.update(ROLE_CONFIGS)

    if "skills-core" in modules and SKILL_TEMPLATES:
        templates.update(SKILL_TEMPLATES)
        templates["skills/SKILL_INDEX.md"] = skill_index_content(SKILL_TEMPLATES)

    if "workflow-quality" in modules:
        templates["maintenance/SUBAGENT_DELEGATION_CHARTER.md"] = DELEGATION_CHARTER
        templates.update(WORKER_WATCHER_TEMPLATES)
        templates["reports/README.md"] = (
            "# Codex Harness Reports\n\n"
            "Harness reports and templates for repo verification, context inspection,\n"
            "retrieval, eval, benchmark, P0 integrity, and audit work live here. `README.md`,\n"
            "templates, and seed discovery files are active managed source.\n\n"
            "`*.latest.json`, `*.latest.md`, and `*results.jsonl` are ignored\n"
            "runtime outputs. Use them for triage only; rerun the responsible\n"
            "command before treating a check as current validation. Keep not-run and\n"
            "failed checks explicit. Do not recreate retained dated evidence archives by default.\n"
        )
        templates["artifacts/tool-results/README.md"] = (
            "# Tool Result Artifacts\n\n"
            "This directory is for large command-output artifacts written by the\n"
            "harness. `README.md` is active managed source. `*.txt` files are ignored\n"
            "runtime output and historical evidence, not fresh validation unless the\n"
            "current run names the file and timestamp.\n\n"
            "Do not copy live runtime logs, secrets, sessions, SQLite state, browser\n"
            "state, or raw prompt payloads here. Prefer current command reruns, keep\n"
            "artifact references in reports or trajectories, and delete retired\n"
            "generated artifacts in a separate bounded cleanup pass.\n"
        )
        templates["artifacts/compact-summaries/README.md"] = "# Compact Summaries\n\nStructured phase-boundary summaries live here.\n"
        templates["trajectories/README.md"] = "# Trajectories\n\nJSONL run records for successes and failures live here.\n"
        templates["learning/README.md"] = "# Learning Drafts\n\nOnly unapproved, project-scoped instincts and skill candidates live here. Do not store raw private conversations or secrets.\n"
        templates["reports/context-inspection.template.md"] = context_template()
        templates["reports/retrieval-report.template.md"] = retrieval_template()

    if "benchmarking" in modules:
        for path, content in EVAL_TEMPLATES.items():
            templates[path] = json.dumps(content, ensure_ascii=False, indent=2, sort_keys=True) + "\n"

    wrappers = {
        "codex-harness-plan.ps1": "plan",
        "codex-harness-apply.ps1": "apply",
        "codex-harness-doctor.ps1": "doctor",
        "codex-harness-repair.ps1": "repair",
        "codex-harness-uninstall.ps1": "uninstall",
        "codex-harness-audit.ps1": "audit",
        "codex-verify.ps1": "verify",
        "codex-repo-verify.ps1": "repo-verify",
        "codex-eval.ps1": "eval",
        "codex-merge-config.ps1": "merge-config",
        "codex-global-scan.ps1": "global-scan",
        "codex-context.ps1": "context",
        "codex-retrieve.ps1": "retrieve",
        "codex-compact-summary.ps1": "compact-summary",
        "codex-trajectory.ps1": "trajectory",
        "codex-benchmark.ps1": "benchmark",
    }
    for name, command in wrappers.items():
        templates[f"maintenance/scripts/{name}"] = wrapper_script(command)

    return templates


def skill_index_content(skill_templates: dict[str, str]) -> str:
    entries = []
    for path, content in sorted(skill_templates.items()):
        if not path.endswith("/SKILL.md"):
            continue
        frontmatter = parse_frontmatter(content)
        entries.append(
            f"| {frontmatter.get('name', Path(path).parent.name)} | {frontmatter.get('description', '')} | {', '.join(frontmatter.get('tags', []))} |"
        )
    return "# Skill Index\n\nFull skill bodies are loaded only when their trigger matches.\n\n| Name | Description | Tags |\n|---|---|---|\n" + "\n".join(entries) + "\n"


def parse_frontmatter(content: str) -> dict[str, Any]:
    if not content.startswith("---\n"):
        return {}
    end = content.find("\n---", 4)
    if end == -1:
        return {}
    data: dict[str, Any] = {}
    for raw in content[4:end].splitlines():
        if ":" not in raw:
            continue
        key, value = raw.split(":", 1)
        value = value.strip()
        if value.startswith("[") and value.endswith("]"):
            data[key.strip()] = [v.strip() for v in value[1:-1].split(",") if v.strip()]
        else:
            data[key.strip()] = value.strip('"')
    return data


def context_template() -> str:
    return """# Context Inspection

- discovered instruction files:
- selected primary instruction source:
- skipped instruction sources:
- truncation decisions:
- warnings:
- estimated context size:
"""


def retrieval_template() -> str:
    return """# Iterative Retrieval Report

- cycles:
- query per cycle:
- candidate files:
- relevance scores:
- relevance reasons:
- missing context:
- refined query:
- selected context:
- stop reason:
"""


def command_exists(command: str) -> bool:
    return shutil.which(command) is not None


def run_command(command: list[str], cwd: Path, timeout: int = 60, *, include_stdout: bool = False) -> dict[str, Any]:
    started = dt.datetime.now()
    try:
        completed = subprocess.run(
            command,
            cwd=str(cwd),
            text=True,
            encoding="utf-8",
            errors="replace",
            capture_output=True,
            timeout=timeout,
        )
        status = "pass" if completed.returncode == 0 else "fail"
        result = {
            "command": command,
            "status": status,
            "exit_code": completed.returncode,
            "stdout_preview": redact_obvious_secrets(completed.stdout[-COMMAND_PREVIEW_CHARS:]),
            "stderr_preview": redact_obvious_secrets(completed.stderr[-COMMAND_PREVIEW_CHARS:]),
            "duration_seconds": (dt.datetime.now() - started).total_seconds(),
        }
        artifacts = []
        command_name = safe_slug("-".join(Path(part).name if index == 0 else part for index, part in enumerate(command[:4])), "command")
        if not include_stdout and len(completed.stdout) > COMMAND_ARTIFACT_THRESHOLD_CHARS:
            artifacts.append({"stream": "stdout", **store_tool_artifact(cwd, f"{command_name}-stdout", completed.stdout)})
        if not include_stdout and len(completed.stderr) > COMMAND_ARTIFACT_THRESHOLD_CHARS:
            artifacts.append({"stream": "stderr", **store_tool_artifact(cwd, f"{command_name}-stderr", completed.stderr)})
        if artifacts:
            result["artifacts"] = artifacts
        if include_stdout:
            result["stdout"] = redact_obvious_secrets(completed.stdout)
        return result
    except Exception as exc:  # noqa: BLE001 - diagnostics command wrapper
        return {
            "command": command,
            "status": "error",
            "exit_code": None,
            "stdout_preview": "",
            "stderr_preview": str(exc),
            "duration_seconds": (dt.datetime.now() - started).total_seconds(),
        }


def discover_instruction_files(root: Path) -> list[dict[str, Any]]:
    candidates = [root / name for name in ["instructions.md", "AGENTS.md", "CALIBRATION.md", "agent.md", "CLAUDE.md", ".cursorrules"]]
    cursor_rules = root / ".cursor" / "rules"
    if cursor_rules.exists():
        candidates.extend(sorted(cursor_rules.glob("*.mdc")))
    result = []
    for path in candidates:
        if path.exists():
            result.append({"path": rel(path, root), "bytes": path.stat().st_size})
    return result


def instruction_warnings(path: Path) -> list[str]:
    try:
        text = read_text(path)
    except UnicodeDecodeError:
        return ["non-utf8 instruction file skipped for content inspection"]
    patterns = [
        (r"(?i)ignore (all )?(previous|prior|above) instructions", "possible prompt-injection override language"),
        (r"(?i)(exfiltrate|send|upload).{0,40}(secret|token|credential|password)", "possible credential exfiltration instruction"),
        (r"(?i)BEGIN (RSA |OPENSSH |EC |DSA |PRIVATE )?PRIVATE KEY", "private key material pattern"),
    ]
    return [message for pattern, message in patterns if re.search(pattern, text)]


def discovery_data(root: Path) -> dict[str, Any]:
    files = set(p.as_posix() for p in iter_files(root, max_files=20000))
    commands = {
        "test": ["python maintenance/scripts/codex_agent_harness.py verify"],
        "lint": [],
        "typecheck": [],
        "build": [],
        "security": ["python maintenance/scripts/codex_agent_harness.py audit --json"],
    }
    if "package.json" in files:
        commands["test"].append("npm test")
    if "pyproject.toml" in files:
        commands["test"].append("pytest")
    return {
        "generated_at": utc_now(),
        "project_type": "Codex global state and local development-environment harness",
        "language_runtime": ["PowerShell", "Python", "TOML", "JSON"],
        "package_manager": "toolchain shims under toolchains/shims; no repo package manager required",
        "detected_commands": commands,
        "existing_harness_instruction_files": discover_instruction_files(root),
        "proposed_harness_script_language": "Python engine with PowerShell wrappers",
        "implementation_assumptions": [
            "CODEX_HOME resolves to the user profile .codex directory and is the GlobalSSOT root.",
            "Desktop is user-facing and must not be mutated by harness commands.",
            "Global config mutation requires an explicit apply path and any safety copy must be transient, not retained runtime fallback.",
            "Secrets and credential contents are not read.",
        ],
        "risks": [
            "Already-running Codex sessions may not reload newly enabled MCP tools until restart.",
            "Sentinel blocker files intentionally cause PATH/temp creation warnings for commands that try to create blocked roots.",
            "SQLite runtime DB files are live and are audited metadata-only.",
        ],
    }


def iter_files(root: Path, max_files: int = 100000) -> list[Path]:
    ignored = {
        ".git",
        "artifacts",
        "cache",
        "generated_images",
        "memories",
        "reports",
        "node_modules",
        ".sandbox",
        ".sandbox-bin",
        ".sandbox-secrets",
        "browser",
        "log",
        "sessions",
        "sqlite",
        "trajectories",
    }
    result: list[Path] = []
    for dirpath, dirnames, filenames in os.walk(root):
        dirnames[:] = [d for d in dirnames if d not in ignored]
        current = Path(dirpath)
        for filename in filenames:
            result.append((current / filename).relative_to(root))
            if len(result) >= max_files:
                return result
    return result

def clean_report_string(value: str, limit: int = 500) -> str:
    cleaned = "".join(ch if (ch == "\t" or ord(ch) >= 32) else "?" for ch in value)
    return cleaned[:limit]


def redact_obvious_secrets(value: str) -> str:
    patterns = [
        r"sk-[A-Za-z0-9_-]{20,}",
        r"ghp_[A-Za-z0-9_]{20,}",
        r"github_pat_[A-Za-z0-9_]{20,}",
        r"xox[baprs]-[A-Za-z0-9-]{20,}",
        r"AKIA[0-9A-Z]{16}",
        r"(?i)(api[_-]?key|secret|password|token)\s*[:=]\s*['\"][^'\"]{8,}['\"]",
    ]
    redacted = value
    for pattern in patterns:
        redacted = re.sub(pattern, "<redacted>", redacted)
    return redacted


def safe_slug(value: str, fallback: str = "artifact") -> str:
    slug = re.sub(r"[^A-Za-z0-9_.-]+", "-", value).strip(".-")
    return (slug or fallback)[:80]


def store_tool_artifact(root: Path, name: str, content: str) -> dict[str, Any]:
    safe_name = safe_slug(name)
    digest = sha256_text(content)[:12]
    path = root / "artifacts" / "tool-results" / f"{local_stamp()}-{digest}-{safe_name}.txt"
    write_text(path, redact_obvious_secrets(content))
    return {"path": rel(path, root), "bytes": path.stat().st_size, "sha256": sha256_file(path)}


def current_git_state(root: Path) -> dict[str, Any]:
    def run_git(args: list[str]) -> str:
        try:
            completed = subprocess.run(["git", *args], cwd=str(root), text=True, encoding="utf-8", errors="replace", capture_output=True, timeout=15)
        except Exception:  # noqa: BLE001 - best-effort metadata
            return ""
        return completed.stdout.strip() if completed.returncode == 0 else ""

    status = run_git(["status", "--short"])
    return {"sha": run_git(["rev-parse", "--short", "HEAD"]), "dirty": bool(status), "status_preview": status[:2000]}


def append_trajectory(root: Path, task: str, status: str, checks: list[dict[str, Any]], artifacts: list[dict[str, Any]] | None = None, error: str | None = None) -> dict[str, Any]:
    record = {
        "version": TRAJECTORY_VERSION,
        "run_id": f"{dt.datetime.now().strftime('%Y%m%d%H%M%S')}-{sha256_text(task + utc_now())[:8]}",
        "timestamp": utc_now(),
        "task": task,
        "repository": current_git_state(root),
        "tool_stats": {
            "commands": len(checks),
            "artifacts": len(artifacts or []),
            "failures": sum(1 for item in checks if item.get("status") != "pass"),
        },
        "checks": checks,
        "artifacts": artifacts or [],
        "verification_result": status,
        "completed": status == "pass",
        "error": error,
    }
    append_jsonl(root / "trajectories" / "runs.jsonl", record)
    return record
