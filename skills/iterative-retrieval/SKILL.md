---
name: iterative-retrieval
description: Retrieve focused context for subagents without dumping the whole tree.
version: 0.1.0
tags: [subagents, retrieval, context]
required_tools: [rg]
---

# Iterative Retrieval

Use up to three cycles: broad search, score files, refine query, select context,
and record the stop reason.
