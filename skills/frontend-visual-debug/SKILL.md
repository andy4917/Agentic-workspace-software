---
name: frontend-visual-debug
description: Use when debugging or reviewing rendered frontend UI, screenshots, responsive layout, text overflow, visual regressions, browser console errors, network issues, accessibility states, or interaction behavior.
---

# Frontend Visual Debug

## Workflow

1. Read project UI instructions and use `modern-web-guidance` and `ui-ux-pro-max` when their trigger matches.
2. Start the existing dev server or static preview command. Do not invent a new runtime path when the project provides one.
3. Inspect the rendered app with Browser or Chrome DevTools, using the browser tool that matches the user's target environment.
4. Capture desktop and mobile evidence. Check layout framing, text fit, responsive behavior, hover/focus/disabled states, contrast, console errors, and failed network requests.
5. Patch the smallest confirmed UI or data-flow issue, then repeat the same rendered check.

## Guardrails

- Do not claim visual quality from source inspection alone when a browser check is practical.
- Do not hide overflow, overlap, or broken states behind screenshots that miss the affected viewport.
- Prefer existing components, tokens, and design-system conventions over new one-off styling.

## Exit Evidence

Report target URL, viewport coverage, browser/tool used, screenshots or observations, console/network status, checks not run, and remaining visual risk.
