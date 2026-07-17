---
description: backlog 의 완료(Done) 태스크를 backlog/completed/ 로 비대화형 정리한다. 대화형 전용 `backlog cleanup` 의 스크립트 대체판으로, 기본은 "오늘 완료분만 보드에 남기고 나머지 이동"이다. "완료 태스크 정리 / cleanup tasks / done 정리 / 보드 정리" 요청, 또는 태스크 작업 흐름에서 Done 이 임계치 이상 쌓였을 때 사용한다.
allowed_tools: [Bash, Read, Grep]
---

backlog 의 완료(Done) 태스크를 `backlog/completed/` 로 옮겨 보드를 정리한다. `backlog cleanup` 은 age 플래그가 없는 **대화형 전용**이라 자동화가 안 되므로, 동일 동작을 `git mv` 로 하는 스크립트로 대체한다. 정리는 backlog 데이터(태스크 파일)만 건드리며 코드는 손대지 않는다.

## 0. 전제

- repo 루트에 `backlog/tasks/` 가 있어야 한다(backlog 모드 전용). 없으면 스크립트가 exit 2 로 알린다 — 레거시 PLAN.md repo 에는 completed 폴더 개념이 없으니 이 스킬을 쓰지 않는다.
- 이동 대상은 **status: Done** 인 태스크뿐이다. To Do·In Progress·Blocked 는 항상 보드에 남는다(Blocked 는 terminal 이 아니라 나이가 많아도 이동하지 않는다).

## 1. 정책 선택

기본은 `--today`(오늘 완료분만 남기고 나머지 이동)다. 사용자가 다르게 지시하면 그 정책으로 바꾼다.

- `--today` (기본): updated_date 가 오늘(로컬 날짜)인 Done 은 보드 유지, 나머지 Done 이동. updated_date 는 backlog 이 UTC 로 기록하므로 스크립트가 로컬 날짜로 변환해 "오늘" 을 판단한다.
- `--all`: Done 전부 이동(클린 슬레이트).
- `--keep-recent=N`: updated_date 최신 N 건만 남기고 나머지 이동.

## 2. 실행

먼저 `--dry-run` 으로 이동 대상을 확인한 뒤(스킵 가능), 실제 실행한다. 스킬 디렉터리의 `cleanup-tasks.sh` 를 쓴다(경로는 이 스킬의 base directory):

```bash
# 미리보기
"<이 스킬 base dir>/cleanup-tasks.sh" --today --dry-run
# 실제 정리(스크립트가 이동 + backlog 경로만 커밋)
"<이 스킬 base dir>/cleanup-tasks.sh" --today
```

스크립트는 이동 대상 파일을 `git mv` 하고 **backlog 경로만 범위로** 커밋한다(무관한 워킹트리 변경을 쓸어담지 않음). 이동 대상이 0건이면 아무것도 하지 않고 끝난다(멱등).

## 3. push (repo 관례에 따름)

스크립트는 **push 하지 않는다**. 커밋 후:

- 이 repo 처럼 PR 없이 main 직배포하는 관례면(프로젝트 메모리/CLAUDE 확인) `git push` 한다.
- PR 흐름 repo 면 push 하지 말고 로컬 커밋만 남긴 뒤 사용자에게 알린다.

## 4. 보고

정책, Done 총계, 이동 건수, 보드 잔류 건수, 커밋 해시(+push 여부)를 한 줄로 요약한다. dry-run 만 했으면 그 사실을 명시한다.
