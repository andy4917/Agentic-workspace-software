from __future__ import annotations

import tomllib
from pathlib import Path
from typing import Any


CALIBRATION_ROLE_CONFIG = """# Managed as a local Codex verifier role.
name = "calibration-verifier"
description = "Checks whether a draft answer, diagnosis, or plan is sufficiently supported before acceptance."
model = "gpt-5.5"
model_reasoning_effort = "high"
sandbox_mode = "workspace-write"
developer_instructions = \"\"\"
You are not the implementer. You are a calibration verifier.

Check the parent draft for:
1. Unsupported factual, config, version, path, API, dependency, security, or test-result claims.
2. Missing falsifier checks.
3. Evidence that contradicts the selected answer.
4. Places where the draft treats inference as observation.
5. Places where tests, tools, memory, citations, or subagent reports are treated as authority without inspection.

Return:
- ACCEPTED only if material claims are supported for the task risk level.
- PARTIAL if some parts are supported and others are uncertain.
- REJECTED if the answer is likely wrong or materially unsupported.
- ABSTAIN if evidence is insufficient.

Do not generate a replacement solution unless asked.
Do not reward confidence. Reward calibrated uncertainty.
\"\"\"
nickname_candidates = ["REV-Calibrator", "REV-Evidence", "REV-Falsifier"]
"""


CALIBRATION_EVAL_TEMPLATE: dict[str, Any] = {
    "eval_id": "calibration-policy-smoke",
    "task": "Verify calibration policy is discoverable and wired into Codex workflow surfaces.",
    "setup": "Run from CODEX_HOME after calibration policy, local config, hook, agent, or eval manifest changes.",
    "success_criteria": [
        "CALIBRATION.md exists and defines answer statuses, claim-level evidence, falsifier-first checks, and completion authority",
        "AGENTS.md points to CALIBRATION.md without duplicating it as a second source of truth",
        "local/runtime config.toml registers CALIBRATION.md as a project doc fallback",
        "calibration-verifier agent TOML parses",
        "calibration scoring manifest exists",
        "lightweight policy and prompt reminder point to calibration without making hooks completion authority",
    ],
    "grader": "python maintenance/scripts/codex_agent_harness.py eval --eval-id calibration-policy-smoke",
    "timeout_seconds": 30,
    "risk_notes": "Static local/runtime smoke test only; it does not prove every live response is calibrated. Repo-safe verification skips ignored private config.toml.",
}


def read_text(path: Path) -> str:
    return path.read_text(encoding="utf-8")


def check_calibration_policy(root: Path, require_config: bool = True) -> dict[str, Any]:
    checks: list[dict[str, str]] = []

    def add_check(name: str, passed: bool) -> None:
        checks.append({"name": name, "status": "pass" if passed else "fail"})

    def add_skip(name: str, reason: str) -> None:
        checks.append({"name": name, "status": "skip", "reason": reason})

    calibration_path = root / "CALIBRATION.md"
    agents_path = root / "AGENTS.md"
    config_path = root / "config.toml"
    policy_path = root / "hooks" / "lightweight-codex-policy.json"
    workflow_path = root / "hooks" / "lib" / "lightweight-codex-workflow.ps1"
    agent_path = root / "agents" / "calibration-verifier.toml"
    scoring_path = root / "evals" / "calibration-eval.yaml"
    eval_path = root / "evals" / "calibration-policy-smoke.json"

    calibration_text = read_text(calibration_path) if calibration_path.exists() else ""
    agents_text = read_text(agents_path) if agents_path.exists() else ""
    config_text = read_text(config_path) if require_config and config_path.exists() else ""
    policy_text = read_text(policy_path) if policy_path.exists() else ""
    workflow_text = read_text(workflow_path) if workflow_path.exists() else ""
    scoring_text = read_text(scoring_path) if scoring_path.exists() else ""

    add_check("CALIBRATION.md exists", calibration_path.exists())
    add_check("answer statuses documented", all(term in calibration_text for term in ["candidate", "supported", "inferred", "uncertain", "accepted", "abstain"]))
    add_check("claim evidence states documented", all(term in calibration_text for term in ["observed", "derived", "assumed", "unchecked"]))
    add_check("falsifier-first documented", "Falsifier-First" in calibration_text)
    add_check("completion authority documented", "Completion Authority" in calibration_text)
    add_check("AGENTS references canonical calibration", "CALIBRATION.md" in agents_text and "Live Turn Calibration" in agents_text)
    if require_config:
        add_check("config registers calibration fallback", "project_doc_fallback_filenames" in config_text and "CALIBRATION.md" in config_text and "project_doc_max_bytes = 65536" in config_text)
    else:
        add_skip("config registers calibration fallback", "repo-safe mode excludes ignored private runtime config.toml")
    add_check("policy references calibration source", '"calibration"' in policy_text and '"source_path": "CALIBRATION.md"' in policy_text)
    add_check("prompt reminder references calibration", "selected answers, diagnoses, plans, and patch rationales stay candidate" in workflow_text)
    add_check("read-only incident terms stay out of L4", "incident terms inside read-only inspection output" in workflow_text)
    add_check("calibration verifier exists", agent_path.exists())
    add_check("calibration scoring manifest exists", scoring_path.exists() and "confident_wrong" in scoring_text and "unsupported_material_claim" in scoring_text)
    add_check("calibration eval definition exists", eval_path.exists())

    try:
        agent_parse = agent_path.exists() and bool(tomllib.loads(read_text(agent_path)))
    except Exception:
        agent_parse = False
    add_check("calibration verifier TOML parses", agent_parse)

    failures = [item["name"] for item in checks if item["status"] == "fail"]
    return {
        "mode": "local-runtime" if require_config else "repo-safe",
        "status": "pass" if not failures else "fail",
        "failures": failures,
        "checks": checks,
    }
