# WSHOBSON Agents Tools Full Tree Scan

## Checkout Evidence

- Repository URL: `https://github.com/wshobson/agents.git`
- Branch: `main`
- Commit: `9f9ba3237022cd88d8660060fc58e0492002f978`
- Checkout path: `C:\Users\anise\.codex\.tmp\wshobson-agents-scan\agents`
- Checkout timestamp: `2026-05-09T17:01:45.932602+00:00`
- `git status --short`: `<clean>`
- Total tracked files: 714
- Target folders: `docs/`, `plugins/`, `tools/`
- Target file count: 696
- Read count: 696
- Skipped count: 0

This document is generated from a local checkout and the machine manifest `WSHOBSON_AGENTS_FULL_TREE_MANIFEST.json`.


## Complete File List Under `tools/`

- `tools/generate_gemini_commands.py`
- `tools/requirements.txt`
- `tools/yt-design-extractor.py`

## Per-File Utility Analysis

### `tools/generate_gemini_commands.py`

- Read status: `read`
- Purpose: !/usr/bin/env python3: """Generate Gemini CLI TOML slash commands from Claude Code command .md files.""" import argparse import json import os import re import sys from pathlib import Path WORKTREE = Path(__file__).resolve().parent.parent PLUGINS_DIR = WORKTREE / "plugins"
- Dependencies observed: argparse, json, yaml, pathlib
- Inputs and outputs: infer from CLI/options or file content; see manifest hash `dfc39718f0654849f51a0d63cb273f8ed51a4db4f9b259e269a1deb45d59d3cb` for source identity.
- Execution model: CLI/script utility
- Codex App decision: reference first; port only if Codex needs the same local utility
- Pattern demonstrated: small single-purpose utility with explicit inputs and inspectable output.

### `tools/requirements.txt`

- Read status: `read`
- Purpose: Core dependencies: yt-dlp>=2024.0.0 youtube-transcript-api>=0.6.0 Pillow>=10.0.0 pytesseract>=0.3.10 colorthief>=0.2.1
- Dependencies observed: standard file/content only or none obvious
- Inputs and outputs: infer from CLI/options or file content; see manifest hash `3a86fe045a02a1df167522200bb2275576a6317b13869d153f44ca3fe56b333b` for source identity.
- Execution model: reference/config utility
- Codex App decision: reference only
- Pattern demonstrated: small single-purpose utility with explicit inputs and inspectable output.

### `tools/yt-design-extractor.py`

- Read status: `read`
- Purpose: !/usr/bin/env python3: """ YouTube Design Concept Extractor ================================= Extracts transcript + keyframes from a YouTube video and produces a structured markdown reference document ready for agent consumption. Usage: python3 tools/yt-design-extractor.py <youtube_url> [options]
- Dependencies observed: argparse, json, subprocess, pathlib, click
- Inputs and outputs: infer from CLI/options or file content; see manifest hash `252837edd196c1fd3464aeb3444c4a1dfcaa1d32eb94e8b362010e95ac6a1875` for source identity.
- Execution model: CLI/script utility
- Codex App decision: reference first; port only if Codex needs the same local utility
- Pattern demonstrated: small single-purpose utility with explicit inputs and inspectable output.

## Explicit Read/Classify Evidence

- Tools manifest count: 3
- Tools read count: 3
- Tools skipped count: 0

## Shared Conclusion

### Keep

- small single-purpose capability packs;
- progressive disclosure;
- PM-led team presets;
- Context -> Spec -> Plan -> Implement workflow;
- static quality checks for skills/agents;
- explicit invocation over hidden automatic behavior;
- file ownership and graceful shutdown patterns.

### Reject

- copying the entire Claude marketplace;
- mass installation of every agent;
- Claude-only slash command assumptions;
- tmux or Claude teammate mode as a Codex requirement;
- heavy enforcement hooks;
- completion authority gates from the old failed harness.

### Codex App Mapping

- plugin -> capability pack;
- agent file -> Codex custom agent definition;
- command -> prompt template or task-runner recipe;
- skill -> Codex skill;
- plugin-eval -> skill/agent quality audit;
- conductor track -> lightweight work track;
- agent-teams preset -> PM-selected team workflow.
