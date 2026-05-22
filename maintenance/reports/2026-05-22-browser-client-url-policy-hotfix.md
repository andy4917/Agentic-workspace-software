# Browser Client URL Policy Hotfix - 2026-05-22

## Status

Status: continue, with IAB current-runtime recovery verified.

Resolved in the active plugin cache:

- The Chrome and Browser `browser-client.mjs` URL policy hotfix was reapplied to
  the current active cache version `26.519.31651`.
- `create_tab` is now in the URL-policy target set.
- Product extension support remains a narrow existing-tab claim exception for
  the Codex product extension id only.
- Arbitrary `chrome-extension://...` navigation is still blocked by the general
  URL policy.

Not resolved yet:

- Chrome extension backend runtime proof is not available in this local thread
  because the active Browser runtime discovered only the IAB backend.
- The earlier prepared `app.asar` patch for Store app `26.519.2736.0` is stale
  and was excluded from this handoff. It must not be applied to the current app.

## Current Canonical Sources

Current Store app package:

```text
C:\Program Files\WindowsApps\OpenAI.Codex_26.519.3891.0_x64__2p2nqsd0c76g0
```

Current canonical `openai-bundled` source from `C:\Users\anise\.codex\config.toml`:

```text
C:\Program Files\WindowsApps\OpenAI.Codex_26.519.3891.0_x64__2p2nqsd0c76g0\app\resources\plugins\openai-bundled
```

Current official `app.asar` SHA256:

```text
7C9CCC2DE3EB41AB251E34B53D6A4391711EF5FAA7FDF296B935E5823074ED19
```

## Active Runtime Cache Files Patched

```text
C:\Users\anise\.codex\plugins\cache\openai-bundled\browser\26.519.31651\scripts\browser-client.mjs
C:\Users\anise\.codex\plugins\cache\openai-bundled\chrome\26.519.31651\scripts\browser-client.mjs
```

Current patched SHA256 for both active cache files:

```text
AADA37F6066D512CBB79F56D9920A1B41CFDEFEDEC1856BF60E1CB54018702AA
```

Rollback backup:

```text
C:\Users\anise\.codex\maintenance\backups\browser-policy-hotfix-20260522-141500
```

## URL Policy Shape

The general URL allowlist still accepts only:

```text
about:blank
http:
https:
```

The product extension exception is limited to an existing-tab claim flow for:

```text
chrome-extension://jeidoobjhbnnicfkcdfncheimgdnhmjk/...
```

The helper `CODEX_CLAIM_OPEN_EXTENSION_TAB(...)` can claim an already-open
product extension tab and mark it as claimed. Current-tab operations may proceed
only when the backend is `extension` and the tab id was claimed. Direct
navigation to arbitrary `chrome-extension://...` and `chrome://...` remains
blocked by Browser Use URL policy.

## Current Verification

Static checks run after the active cache patch:

```text
node --check C:\Users\anise\.codex\plugins\cache\openai-bundled\browser\26.519.31651\scripts\browser-client.mjs
node --check C:\Users\anise\.codex\plugins\cache\openai-bundled\chrome\26.519.31651\scripts\browser-client.mjs
```

Both passed using the Codex-owned Node shim.

Structure checks:

```text
maintenance\scripts\check-naming-conventions.ps1 -Json
maintenance\scripts\check-codex-native-alignment.ps1 -Json -WriteReport
```

Both passed on the current Store app and plugin-source alignment.

Static code evidence in both active cache files:

```text
CODEX_PRODUCT_EXTENSION_IDS includes jeidoobjhbnnicfkcdfncheimgdnhmjk
CODEX_CLAIM_OPEN_EXTENSION_TAB is present
F5 contains navigate_tab_url and create_tab
U5 no longer contains create_tab
ensureCurrentTabOriginAllowed can allow only claimed extension tabs
```

## Current Runtime Evidence

Runtime import:

```text
file:///C:/Users/anise/.codex/plugins/cache/openai-bundled/chrome/26.519.31651/scripts/browser-client.mjs
```

Discovered backend list:

```text
Codex In-app Browser, type=iab, current thread session id=019e4e10-1879-7821-a35b-ab44f7f11a7a
```

IAB runtime checks:

```text
agent.browsers.get("iab"): ok
iab.tabs.list(): ok, 1 tab
selected tab initial url: about:blank
selected tab goto https://example.com/: ok
selected tab final url: https://example.com/
selected tab final title: Example Domain
```

Chrome extension backend check:

```text
agent.browsers.get("extension"): Browser is not available: extension
```

Current conclusion: the prior IAB blocker `No active Codex browser pane
available` is not reproduced on current Store app `26.519.3891.0` and active
cache `26.519.31651`. No current-version `app.asar` patch is needed unless the
failure recurs.

## Historical Evidence Not Reused As Current Proof

Earlier same-day runtime evidence applied to the previous active cache version
`26.519.22136` and Store app version `26.519.2736.0`. That evidence is useful
history, but it is not current proof for the active cache version `26.519.31651`
or Store app version `26.519.3891.0`.

The old prepared IAB patch targeted:

```text
OpenAI.Codex_26.519.2736.0_x64__2p2nqsd0c76g0
```

That package is no longer the current installed Store app. The old patch helper,
manifest, and packed asar artifacts were removed from the active handoff surface
to avoid an unsupported success claim.

## Remaining Work

1. Runtime-check the current Chrome backend against the active
   `26.519.31651` hotfix when the Chrome extension backend is exposed:
   - existing product extension tab claim succeeds when the tab is open;
   - arbitrary `chrome-extension://aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/...` remains
     blocked.
2. If IAB fails again with `No active Codex browser pane available`, inspect the
   current `app.asar` renderer bundle for the webview recreation path and prepare
   a current-version patch only after confirming the same root cause.
3. Apply any future IAB app patch only after Codex Desktop exits, then restart and
   verify IAB through the live Browser backend.

## Residual Risk

- The active cache hotfix is static-verified but still needs fresh Chrome runtime
  proof on cache version `26.519.31651` in a thread where the extension backend
  is exposed.
- IAB is currently runtime-verified, but the earlier failure may still recur if
  Codex Desktop later tears down the hidden browser webview and fails to recreate
  it.
- Store app updates can overwrite official app contents and invalidate any
  current-version app patch.
