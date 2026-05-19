# Codex Plugin User Surface

Plugin support can remain enabled, but official bundled plugin sources must stay
owned by the installed Codex Desktop bundle.

Do not use this directory, `plugins\cache`, `local-marketplaces\openai-bundled`,
or `local-marketplaces\openai-primary-runtime` as active official sources.
Stale copied marketplaces, legacy plugin IDs, and accidental paths such as
`plugins\plugins` should be removed or moved to the Recycle Bin instead of being
replaced by sentinel or blocker files.
