---
name: cleanup-backlog
description: backlog 의 완료(Done) 태스크를 backlog/completed/ 로 옮기고, 그 결과 남은 일이 없어진 마일스톤을 아카이브한다. "완료 태스크 정리 / done 정리 / 보드 정리" 요청, 또는 태스크 작업 흐름에서 Done 이 임계치 이상 쌓였을 때.
---

backlog 의 완료(Done) 태스크를 `backlog/completed/` 로 옮기고, **그 결과 남은 일이 없어진 마일스톤을 `backlog/archive/milestones/` 로 아카이브한다**. `backlog cleanup` 은 age 플래그가 없는 **대화형 전용**이라 자동화가 안 되므로, 동일 동작을 `git mv` 로 하는 스크립트로 대체한다. 정리는 backlog 데이터(태스크·마일스톤 파일)만 건드리며 코드는 손대지 않는다.

## 0. 전제

- repo 루트에 `backlog/tasks/` 가 있어야 한다(backlog 모드 전용). 없으면 스크립트가 exit 2 로 알린다 — 레거시 PLAN.md repo 에는 completed 폴더 개념이 없으니 이 스킬을 쓰지 않는다.
- 이동 대상은 **status: Done** 인 태스크뿐이다. To Do·In Progress·Blocked 는 항상 보드에 남는다(Blocked 는 terminal 이 아니라 나이가 많아도 이동하지 않는다).
- 마일스톤 아카이브는 **태스크 이동의 뒤처리**다. 마일스톤 카운터(`backlog milestone list`)는 `backlog/tasks/` 에 있는 태스크만 세므로, 완료분을 `completed/` 로 옮기는 순간 그 마일스톤은 `0/0` 이 되어 **끝난 것과 아직 시작 안 한 것이 보드에서 구별되지 않는다**. 정리가 만든 문제이니 같은 자리에서 함께 처리한다.

## 1. 정책 선택

기본은 `--all`(완료 시각과 무관하게 Done 전부 이동)이다. 사용자가 다르게 지시하면 그 정책으로 바꾼다.

- `--all` (기본): Done 전부 이동(클린 슬레이트). 오늘 완료한 것도 옮긴다 — 정리 요청의 의도는 대개 보드를 비우는 것이고, 방금 끝낸 태스크가 보드에 남아 있어야 할 이유가 없다.
- `--today`: updated_date 가 오늘(로컬 날짜)인 Done 은 보드 유지, 나머지 Done 이동. updated_date 는 backlog 이 UTC 로 기록하므로 스크립트가 로컬 날짜로 변환해 "오늘" 을 판단한다.
- `--keep-recent=N`: updated_date 최신 N 건만 남기고 나머지 이동.

## 1-1. 마일스톤 아카이브 판정

스크립트가 자동으로 한다. 인자로 끄고 켜지 않는다 — 태스크 이동과 한 몸이다.

- **아카이브한다**: 남은 태스크 0건(이번에 옮길 것까지 뺀 뒤) **이고** 완료 태스크가 1건 이상(`completed/` 에 있는 것 + 이번에 옮길 것).
- **건드리지 않는다**: 양쪽 다 0인 마일스톤. 태스크를 아직 안 붙인 **신규** 마일스톤이다(`/add-milestone` 이 마일스톤을 먼저 만들고 태스크를 나중에 붙인다). 이 구분이 이 판정의 핵심이다.
- Blocked·To Do 태스크가 하나라도 남아 있으면 그 마일스톤은 대상이 아니다(남은 태스크가 0이 아니므로 자동으로 걸러진다).
- 아카이브는 `backlog milestone archive` 와 같은 동작인 단순 파일 이동이다. 내용은 바뀌지 않으므로 되돌리려면 `backlog/milestones/` 로 다시 옮기면 된다.

## 2. 실행

먼저 `--dry-run` 으로 이동 대상을 확인한 뒤(스킵 가능), 실제 실행한다. 스킬 디렉터리의 `cleanup-backlog.sh` 를 쓴다(경로는 이 스킬의 base directory):

```bash
# 미리보기
"<이 스킬 base dir>/cleanup-backlog.sh" --dry-run
# 실제 정리(스크립트가 이동 + backlog 경로만 커밋)
"<이 스킬 base dir>/cleanup-backlog.sh"
```

스크립트는 이동 대상 파일을 `git mv` 하고 **자기가 옮긴 파일의 옛/새 경로만 범위로** 커밋한다(옆 세션이 backlog 에 만들어 둔 변경을 쓸어담지 않는다). 태스크·마일스톤 모두 이동 대상이 0건이면 아무것도 하지 않고 끝난다(멱등). dry-run 출력에서 태스크는 `→`, 마일스톤은 `⇒` 로 구분된다.

## 3. push (repo 관례에 따름)

스크립트는 **push 하지 않는다**. 커밋 후:

- 이 repo 처럼 PR 없이 main 직배포하는 관례면(프로젝트 메모리/AGENTS 확인) `git push` 한다.
- PR 흐름 repo 면 push 하지 말고 로컬 커밋만 남긴 뒤 사용자에게 알린다.

## 4. 보고

정책, Done 총계, 이동 건수, 보드 잔류 건수, **아카이브한 마일스톤(있으면 id·제목)**, 커밋 해시(+push 여부)를 한 줄로 요약한다. dry-run 만 했으면 그 사실을 명시한다.
