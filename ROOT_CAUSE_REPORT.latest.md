# ROOT_CAUSE_REPORT.latest

Run id: `20260509-035137-final-pass-loop`
Status: blocked before full runtime PASS candidate

## Repeated Failure

The `required_tool_route_inspection` App inspector session did not promote to a canonical `inspector_spawn_event` after two reruns of the same bridge proof.

Repeated ledger reason:

- `event_type`: `unmatched_subagent_spawn_observed`
- `reason_code`: `no_matching_subagent_job`
- `agent_name`: `spark_tool_route_inspector`
- `route_id`: `required_tool_route_inspection`
- `app_session_id`: `019e08f5-be38-70f0-bca6-02fed94ab183`

## Exact Missing Link

`Get-CodexAppRecentSubagentSessions` extracts lineage fields by applying regexes to the first 30 JSONL lines of the subagent session preview and taking the last match.

For `rollout-2026-05-09T03-59-43-019e08f5-be38-70f0-bca6-02fed94ab183.jsonl`, the preview contains the correct user prompt envelope, but it also contains later tool outputs and report text. The last-match extraction therefore drifted away from the original envelope:

- expected `job_id`: `subagent-3d02b85c8d6d4edeb53d34526f4abc67`
- extracted last `job_id`: `subagent-f`
- expected `parent_turn_id`: `514a84a6821f1db426f3589aa1170a25a23f4ea94721ba0f1373e1da68c80f51`
- extracted last `parent_turn_id`: `35b5a6a3274f19ec62cb8cd780c6566ebf28e93f101a52d8e12adc7b8be6c172`

Because `Find-CodexAppSubagentSpawnJobMatch` uses the extracted parent turn to read matching jobs, it looks under the wrong turn and cannot find the queued job. The result is an unmatched App inspector spawn even though the correct job envelope exists in the session.

## Evidence

- Job ledger has the expected queued job: `Settings/Codex_App_RUNTIME/subagent_inspection_jobs.jsonl`
- Expected job id: `subagent-3d02b85c8d6d4edeb53d34526f4abc67`
- Expected route id: `required_tool_route_inspection`
- Expected agent: `spark_tool_route_inspector`
- Expected parent/attempt turn: `514a84a6821f1db426f3589aa1170a25a23f4ea94721ba0f1373e1da68c80f51`
- App session file contains the expected envelope in the user message, but later preview text changes the last regex match.

## Scope Of Patch Already Applied

Two narrow bridge fixes were applied before this repeated failure was confirmed:

- Decode literal `\n`, `\r`, and `\t` in App session previews and avoid treating an earlier unmatched lifecycle observation as a dedupe blocker.
- Allow explicit `job_id` match to satisfy target matching, and bind inspector route by `agent_name` when the preview contains multiple route strings.

These fixed the worker App bridge and three inspector App bridges, but the remaining tool-route inspector still fails because envelope extraction is not scoped to the original user prompt.

## Required Next Fix

Do not broaden the hook. The next fix should be limited to App subagent session envelope extraction:

- Parse only the initial user message/request envelope for `parent_turn_id`, `attempt_id`, `route_id`, and `job_id`, or
- prefer the first complete envelope containing all four fields before reading later tool outputs, and reject partial values such as `subagent-f`.

No further patch was applied after the same bridge failure repeated twice.
