#!/usr/bin/env python3
"""CLI entrypoint for the local Codex harness."""

from __future__ import annotations

import argparse

from codex_agent_harness_lifecycle import cmd_apply, cmd_audit, cmd_discovery, cmd_doctor, cmd_plan, cmd_repair, cmd_uninstall
from codex_agent_harness_merge import cmd_merge_config, cmd_self_test
from codex_agent_harness_workflows import cmd_benchmark, cmd_compact_summary, cmd_context, cmd_eval, cmd_global_scan, cmd_retrieve, cmd_trajectory, cmd_verify
from codex_agent_harness_base import DEFAULT_PROFILE


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Local Codex harness")
    parser = argparse.ArgumentParser(description="Local Codex harness")
    parser.add_argument("--root", default=".", help="CODEX_HOME / harness root")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("discovery").set_defaults(func=cmd_discovery)
    p = sub.add_parser("plan")
    p.add_argument("--profile", default=DEFAULT_PROFILE)
    p.add_argument("--module", action="append")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_plan)
    p = sub.add_parser("apply")
    p.add_argument("--profile", default=DEFAULT_PROFILE)
    p.add_argument("--module", action="append")
    p.set_defaults(func=cmd_apply)
    p = sub.add_parser("doctor")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_doctor)
    p = sub.add_parser("repair")
    p.add_argument("--apply", action="store_true")
    p.set_defaults(func=cmd_repair)
    p = sub.add_parser("uninstall")
    p.add_argument("--apply", action="store_true")
    p.set_defaults(func=cmd_uninstall)
    p = sub.add_parser("audit")
    p.add_argument("--json", action="store_true")
    p.set_defaults(func=cmd_audit)
    sub.add_parser("context").set_defaults(func=cmd_context)
    sub.add_parser("verify").set_defaults(func=cmd_verify)
    p = sub.add_parser("eval")
    p.add_argument("--eval-id")
    p.set_defaults(func=cmd_eval)
    p = sub.add_parser("benchmark")
    p.add_argument("--eval-id")
    p.set_defaults(func=cmd_benchmark)
    p = sub.add_parser("trajectory")
    p.add_argument("--search")
    p.add_argument("--failed", action="store_true")
    p.add_argument("--recent", type=int, default=20)
    p.set_defaults(func=cmd_trajectory)
    p = sub.add_parser("compact-summary")
    p.add_argument("--goal")
    p.add_argument("--constraints")
    p.add_argument("--current-plan")
    p.add_argument("--completed-work")
    p.add_argument("--in-progress-work")
    p.add_argument("--blockers")
    p.add_argument("--relevant-files")
    p.add_argument("--commands-run")
    p.add_argument("--test-results")
    p.add_argument("--next-steps")
    p.add_argument("--risks")
    p.set_defaults(func=cmd_compact_summary)
    p = sub.add_parser("retrieve")
    p.add_argument("--query", required=True)
    p.add_argument("--limit", type=int, default=8)
    p.set_defaults(func=cmd_retrieve)
    sub.add_parser("global-scan").set_defaults(func=cmd_global_scan)
    p = sub.add_parser("merge-config")
    p.add_argument("--source", required=True)
    p.add_argument("--target", required=True)
    p.add_argument("--apply", action="store_true")
    p.add_argument("--update-managed", action="store_true")
    p.set_defaults(func=cmd_merge_config)
    sub.add_parser("self-test").set_defaults(func=cmd_self_test)
    return parser



def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
