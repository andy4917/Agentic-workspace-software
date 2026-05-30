최신 기능 반영 포인트

OpenAI의 2026-05-29 Codex 26.527 changelog 기준으로, Codex에는 Windows Computer Use, Windows remote control, local project/worktree thread coordination, background threads, 과거 thread 검색 확장이 추가되었습니다. 특히 thread search가 conversation content와 Git branch name까지 포함하도록 확장된 점은 “릴리스 → 영향 분석 → 작업 스레드 → worktree → diff 검증” 자동화에 직접 활용할 수 있습니다.

Codex app은 기본적으로 parallel threads, built-in worktree, automations, Git diff/commit/PR 기능을 지원하며, automations는 skills와 결합해 telemetry error 평가, 수정 제출, 최근 코드베이스 변경 리포트 같은 반복 작업에 사용할 수 있습니다.

Sandcastle는 TypeScript 기반의 AI coding agent orchestration 도구로, isolated sandbox 안에서 agent를 실행하고 branch strategy를 관리하며 commits를 merge back하는 구조입니다. Docker, Podman, Vercel, no-sandbox provider를 지원합니다. 최신 릴리스 v0.6.6은 agent가 completion signal을 냈지만 gh, git, long-lived MCP server 같은 child process 때문에 stdout pipe가 닫히지 않는 경우를 처리하기 위해 completionTimeoutSeconds를 추가했습니다. 이는 유지보수 자동화에서 “완료 신호는 있는데 세션/프로세스가 매달리는 문제”를 다루는 데 직접적으로 중요합니다.

Treat the P0 cleanup markdown as prior evidence, not as proof of current state. Re-read the current files, inspect current runtime state, and verify the original failure modes before making any change. 수정 권한을 주려면 현재 repo 상태, 실제 스크립트, 현재 codex doctor, 현재 process status, 현재 diff를 다시 보도록 해야한다.