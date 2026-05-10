---
name: git-easy-korean
description: Use when Codex performs, explains, summarizes, reviews, or plans Git/GitHub work for Korean users, including status, diff, add/stage, commit, push, pull, branch, merge, conflict, rejected push, untracked files, ignored files, dangerous files, PR publishing, or release handoff. Automatically convert Git jargon and error output into easy Korean while preserving exact commands, file paths, branch names, commit hashes, and irreversible-operation warnings.
---

# Git Easy Korean

## Core Rule

Use exact Git commands internally, but explain user-facing Git work in easy Korean.

Do not replace command names inside commands, logs, file paths, branch names, commit hashes, or code blocks. Translate the meaning around them.

## Word Map

- `commit` -> `세이브`
- `push` -> `GitHub에 올리기`
- `pull` -> `GitHub에서 받아오기`
- `branch` -> `작업 사본`
- `merge` -> `합치기`
- `stage`, `add` -> `담아두기`
- `conflict` -> `충돌`
- `untracked` -> `아직 Git이 모르는 새 파일`
- `modified` -> `고침`
- `deleted` -> `삭제됨`
- `remote` -> `GitHub 쪽`
- `local` -> `내 컴퓨터 쪽`
- `upstream` -> `기준 GitHub 위치`
- `working tree` -> `작업 folder`

## Reporting Shape

When reporting Git state, prefer this shape:

```text
작업 중 - N개 파일 고침, 아직 세이브 안 함

작업 folder -> 담아둠 -> 세이브 -> GitHub에 올리기
```

When the work is done:

```text
세이브 + GitHub 올리기 완료

담은 내용:
- path/file.ts [고침]
- path/new.ts [새 파일]

세이브:
"사용자에게 쉬운 제목"

상태:
안전
```

When many files changed, group by folder:

```text
작업 folder (27개)
- src/pages/orders/ - 5개 (고침 3 + 새 파일 2)
- src/hooks/orders/ - 2개 (새 파일 2)
- 기타 - 20개
```

When local commits are not pushed:

```text
GitHub에 안 올린 세이브 2개

- "리뷰 파이프라인 보완" (5일 전)
- "Git 도우미 Skill 추가" (방금)

위험한 건 아니에요. GitHub 백업만 아직 안 된 상태입니다.
```

## Error Translation

Explain the practical meaning first, then include the exact Git line if it helps.

- `rejected`, `non-fast-forward`:
  `GitHub에 새로 올라온 내용이 있어요. 먼저 받아온 다음에 다시 올려야 합니다.`
- `merge conflict`, `CONFLICT`:
  `같은 파일을 양쪽에서 고쳐서 자동으로 합칠 수 없습니다. 어느 쪽 코드를 쓸지 정해야 합니다.`
- `nothing to commit`:
  `새로 세이브할 변경이 없습니다.`
- `working tree clean`:
  `작업 folder가 깨끗합니다. 세이브할 변경이 없습니다.`
- `untracked files`:
  `Git이 아직 모르는 새 파일이 있습니다. 올릴 파일이면 담아두고, 아니면 무시 파일에 넣어야 합니다.`
- `permission denied`:
  `권한이 막혔습니다. 로그인/권한/키 설정을 확인해야 합니다.`
- `could not resolve host`:
  `네트워크나 GitHub 주소 연결이 막혔습니다.`
- `not a git repository`:
  `지금 위치는 Git 작업 folder가 아닙니다. 올바른 repository folder에서 다시 해야 합니다.`
- `detached HEAD`:
  `작업 사본 이름 없이 특정 세이브 지점에 직접 올라와 있습니다. 새 작업 사본을 만들고 진행하는 편이 안전합니다.`
- `Please tell me who you are`:
  `Git 세이브 작성자 이름/email 설정이 없습니다.`

## Safety Rules

Block or clearly warn before adding likely-dangerous files:

- `.env`, `.env.*`
- files containing `token`, `secret`, `credential`, `auth`, or `key` in sensitive contexts
- `node_modules/`
- build/cache folders such as `dist/`, `.next/`, `.turbo/`, `coverage/`, `.cache/`
- large binary artifacts unless the user explicitly asked to version them

Never make destructive Git changes without explicit user instruction. This includes `git reset --hard`, `git clean -fd`, deleting branches, force-push, rebasing published work, or overwriting conflict choices.

## Commit Message Style

Make commit messages short and human-readable. Prefer Korean when the surrounding task is Korean.

Examples:

- `대시보드 페이지 추가`
- `Git 작업 설명 Skill 추가`
- `주문 필터 오류 수정`

When reporting a commit hash, say:

```text
세이브됨: abc1234 "대시보드 페이지 추가"
```

## Conflict Handling

When a conflict appears, stop automatic merge resolution unless the correct choice is obvious from the user's explicit request and repository context.

Explain it like this:

```text
충돌 감지

같은 파일을 양쪽에서 고쳐서 자동으로 합칠 수 없습니다.
충돌 파일:
- path/file.ts

제가 판단 가능한 코드 충돌이면 정리해서 검증하겠습니다.
어느 쪽 의도가 맞는지 모호하면 그 파일만 멈추고 선택지를 짧게 보여드리겠습니다.
```

## Verification

Before saying Git work is done, check the relevant state:

- `git status --short`
- `git branch --show-current`
- `git log --oneline -5` when commits were made
- `git status -sb` or upstream ahead/behind state when pushing/pulling matters

Report the result in easy Korean, not as raw Git output unless the user asks for raw output.
