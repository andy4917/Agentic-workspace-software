---
name: verification-loop
description: Repeat deterministic checks until the local harness has no known failing checks.
version: 0.1.0
tags: [verification, audit, repair]
required_tools: [python]
---

# Verification Loop

Run doctor, verify, eval, and audit. Fix confirmed failures only, then rerun
the same checks. Record checks not run with reasons.
