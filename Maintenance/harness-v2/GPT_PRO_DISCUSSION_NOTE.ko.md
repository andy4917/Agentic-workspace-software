# GPT Pro 전달문

리뷰 결론에 동의합니다.

기존 production hook에 예외를 계속 덧칠하는 방식은 중단하고, 현재 패치
내역은 trace/log로만 보겠습니다. 다음 정상 경로는 격리된 Harness V2를
먼저 만들고, acceptance test를 통과시킨 뒤 shadow mode로 관측하는
순서입니다.

확인한 내용:

- `C:\Users\anise\Downloads\codex_dev_env_remodel_review.md` 문서를 직접
  확인했습니다.
- 공식 Codex 문서와도 핵심 전제가 맞습니다. Hooks는 lifecycle surface이고,
  Stop은 완료 주장을 거부하거나 continuation을 만들 수 있습니다. Skills는
  progressive disclosure라서 설치됨이 사용됨을 뜻하지 않습니다. AGENTS.md는
  scope와 precedence가 있는 guidance이지 완료권이 아닙니다. Subagent는
  명시적으로 spawn되는 helper이며 완료권 authority가 아니라 candidate evidence입니다.
- 현재 live hook은 사용자가 명시한 review 문서 읽기까지
  `path_outside_active_scope`로 막는 false positive를 재현했습니다.

이번에 만든 V2 격리 산출물:

- `Maintenance/harness-v2/HARNESS_V2_DESIGN.md`
- `Maintenance/harness-v2/harness_v2_policy.yaml`
- `Maintenance/harness-v2/harness_v2_acceptance_tests.yaml`
- `Maintenance/harness-v2/Invoke-HarnessV2Acceptance.ps1`
- `Maintenance/harness-v2/MIGRATION_PLAN.md`
- `Maintenance/harness-v2/harness_v2_integrity_compatibility_actions.md`

논의 확인이 필요한 지점:

1. 사용자가 명시한 외부 참고문서는 private material이 아닌 한 read-only allow로
   보는 데 동의하는가?
2. path-scope mismatch는 hard blocker가 아니라 `path_scope_observed`로
   기록하고, secret/auth, destructive side effect, unauthorized
   control-plane mutation, evaluator manipulation, fake-success shortcut은
   계속 `BLOCKED`로 두는 데 동의하는가?
3. 일반 이미지 생성은 executable/procedural artifact가 아니므로 dynamic
   reproduction과 direct evidence blocker에서 제외하는 데 동의하는가?
4. missing required-tool route는 PreToolUse 차단이 아니라 Stop의
   `DO_NOT_CLAIM_COMPLETE`로만 처리하는 데 동의하는가?
5. production 적용은 즉시 교체가 아니라 shadow observation부터 시작하는 데
   동의하는가?
6. worker subagent는 실제 코드와 production 작업을 하므로 최신 기본 모델
   `gpt-5.5`, `reasoning_effort=medium`으로 운영하고, Spark inspector는 계속
   read-only `gpt-5.3-codex-spark`, fallback `latest-mini`,
   `reasoning_effort=high` 후보 증거 전용으로 분리하는 데 동의하는가?
7. agent limit은 `agents.max_threads = 8`, `agents.max_depth = 1`로 두고,
   recursive spawn은 금지하며 동시성은 thread/job limit으로만 다루는 데
   동의하는가?

제안 답변:

V2 acceptance test를 계약으로 삼고, production hook 교체 전 shadow mode로
정상 경로가 조용한지와 reward-hacking 경로가 완료권을 얻지 못하는지를 먼저
검증하는 방향으로 진행하겠습니다. PM은 worker와 inspector를 분리해 운영하고,
worker 결과와 inspector 보고서를 모두 append-only ledger 및 PM decision으로
검토한 뒤에만 Stop 제출 후보로 올리겠습니다.
