# Codex Automation Target Boundary

This runbook classifies Computer Use, Chrome Use, and Browser Use as the same
automation-risk family when they can click, type, navigate, inspect, or operate
an app or browser session on behalf of Codex.

It applies to:

- the `computer-use` plugin and related desktop automation helpers;
- the `chrome` plugin and Chrome-profile automation;
- the `browser` plugin and Codex in-app browser automation;
- Chrome DevTools MCP or similar browser-observation tooling when it can drive
  page state.

## Primary Rule

Do not use these tools to directly automate Codex itself, Codex CLI, terminal
apps, Codex extensions, plugin settings, security prompts, account or payment
screens, or other control-plane surfaces when a structured route exists.

Use structured routes first:

1. local files, logs, process metadata, and command output;
2. Codex CLI or app-server commands such as `codex app <workspace>`;
3. MCP tools or plugin APIs that expose structured data;
4. project scripts, tests, and build commands;
5. browser or desktop automation only for the narrow user-facing surface that
   cannot be verified through structured routes.

The completion target is the user's goal, not proving that a GUI automation
tool can force-control a protected target.

## Classification

Before calling Computer Use, Chrome Use, Browser Use, or browser-driving MCP
tools, classify the target:

- `protected-codex-control-plane`: Codex Desktop, Codex CLI, terminal shells,
  Codex extensions, plugin settings, native hosts, MCP registration, auth,
  safety prompts, or update dialogs.
- `ordinary-user-surface`: normal app or web UI that the user asked to inspect
  or operate.
- `browser-observation`: rendered page verification, screenshots, console,
  network, accessibility, DOM state, or responsive layout.
- `unclear-target`: app/window/title/process cannot be identified safely.

For `protected-codex-control-plane`, stop GUI automation and switch to
structured routes. For `unclear-target`, gather metadata first and do not click
or type until the target is known.

## Tool-Specific Rules

Computer Use:

- Use for ordinary Windows GUI targets only after the app/window is identified.
- Treat missing Codex or terminal windows from the target list as an expected
  policy boundary unless evidence proves a general app overblock.
- Do not patch helper binaries or plugin cache to bypass target policy.

Chrome Use:

- Use when the user's Chrome profile, cookies, logged-in state, extensions, or
  existing tabs are required.
- Do not use Chrome automation to operate Codex extensions, extension settings,
  browser security prompts, or account/payment/security pages.
- Prefer isolated browser tooling for unauthenticated local verification.

Browser Use:

- Use the Codex in-app browser for local web targets, screenshots, and
  interaction verification when it does not require the user's Chrome profile.
- Do not use it as a substitute for structured Codex control-plane operations.
- For frontend verification, prefer the browser tool that gives the narrowest
  evidence without exposing unrelated profile state.

Chrome DevTools MCP:

- Keep it optional and OFF by default.
- Enable only for bounded browser-observation tasks, then turn it OFF and
  confirm the disabled state.

## Overblock Diagnosis

If an automation tool cannot initialize or does not expose the expected target:

1. Determine whether the requested target is a protected Codex/control-plane
   surface.
2. If protected, treat the block as likely intentional and use a structured
   route.
3. If ordinary, check foreground state, app approval, window title, process
   name, plugin install/cache state, and version drift.
4. If prior unofficial binary or cache patches are found, prefer clean
   reinstall or backup restore before any new mutation.
5. Record path, version, hash, action, rollback, and not-run checks for any
   changed file.

## Runtime-Load Normalization

Computer Use, Chrome Use, and Browser Use depend on the current Codex turn's
tool-surface transport for `node_repl` calls. A stale exposed tool handle can
report `Transport closed` even when the bundled execution primitive, plugin
cache, Chrome native host, and Computer Use helper are healthy.

When that happens:

1. Re-run tool discovery once for `node_repl js`.
2. If the exposed tool still reports `Transport closed`, do not classify the
   Browser, Chrome, or Computer plugin as failed from that signal alone.
3. Run `maintenance\scripts\check-automation-plugin-health.ps1` to prove the
   standalone `node_repl` MCP stdio path, Browser plugin static health, Chrome
   official diagnostics, Chrome runtime status, and Computer Use helper health.
4. If standalone health passes but the current tool handle remains closed,
   classify the remaining issue as `current-session-tool-transport`, not plugin
   install failure or overblock bypass.
5. Do not patch plugin binaries, remove safety policy, or automate Codex UI to
   recover the stale handle. Prefer the next fresh Codex turn/session for the
   active tool-surface proof.

## Prohibited Fixes

- Repeatedly trying to click or type into Codex Desktop, Codex CLI, terminal
  apps, or Codex extensions through GUI automation.
- Editing vendor binaries, helper executables, or plugin cache as the default
  solution.
- Removing broad safety instructions to make one target visible.
- Auto-approving sensitive prompts or operating account, payment, security, or
  credential screens.
- Reporting a weaker alternate check as success after the original automation
  proof failed.

## Completion Evidence

For automation-boundary work, report:

- target classification;
- selected tool or structured fallback;
- why Computer Use, Chrome Use, Browser Use, or browser-driving MCP was used or
  intentionally not used;
- commands or observations that prove the user goal;
- changed files, hashes when relevant, rollback path, not-run checks, and
  residual risks.
