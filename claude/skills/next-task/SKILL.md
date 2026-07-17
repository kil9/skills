---
description: backlog(또는 PLAN.md)만 훑어 다음에 착수할 태스크 후보를 추려 보고한다. 추가 조사·구현은 하지 않는다. "다음 뭐 하지 / 다음 태스크 / 남은 일 뭐 있지" 를 물을 때 사용한다.
allowed_tools: [Bash, Read, Glob, Grep]
---

백로그(또는 플랜 파일)만 읽고 **다음에 착수할 태스크 후보**를 추려 보고한다. 추가 조사·구현·파일 수정은 하지 않는다. 그건 후보를 고른 뒤의 다음 행동(`/start-task` 등)의 몫이다. 근거는 backlog 데이터(레거시 모드는 플랜 본문)뿐 — 코드·이슈·git·웹은 조사하지 않는다.

## 0. 모드 감지

repo 루트에 `backlog/` 디렉터리(또는 `backlog/config.yml`)가 있으면 **backlog 모드**(§1-3), 없으면 **레거시 모드**(§4)로 동작한다. backlog 모드가 기본이다.

**CLI 없으면 중단.** backlog 모드면 `command -v backlog` 로 확인한다. 없으면 태스크 파일을 직접 읽어 폴백하지 말고(상태·의존을 잘못 읽는다) `bash "${K9HOME:-$HOME/kil9conf}/bootstrap/install-backlog-md.sh"` 설치를 안내한 뒤 멈춘다.

## 1. 목록 수집 (backlog 모드)

```
backlog task list --plain
```

`--plain` 은 필수다(보드/브라우저 실행 금지). 출력은 상태별 그룹(`To Do` / `In Progress` / `Done` / `Blocked`)으로 나오고, 각 줄은 `[PRIORITY] TASK-N - 제목` 형식이다(priority 미설정 시 앞의 대괄호 없음). draft·milestone 은 여기 안 나오므로 **자동 제외**된다.

이 한 번의 호출로 다음을 파악한다.

- **Done 그룹의 태스크 ID 집합** — 뒤에서 의존 해소 판정에 쓴다.
- In Progress / To Do / Blocked 각 그룹의 태스크 ID·제목·priority.

태스크가 하나도 없으면 그 상태를 보고하고 `/init-backlog` 을 안내한 뒤 멈춘다.

## 2. 상세 조회 (필요한 태스크만)

목록만으로는 의존·label·AC 가 안 보이므로, **In Progress·To Do·Blocked 태스크만** 개별 조회한다(Done·draft 는 조회하지 않는다).

```
backlog task <id> --plain
```

여기서 `Dependencies:` / `Labels:` / `Acceptance Criteria:` / `Implementation Notes:` 를 읽는다.

## 3. 후보 고르기 (backlog 모드)

- **In Progress** 태스크는 "이어서 할 일"로 **맨 앞**에 올린다.
- **To Do** 태스크는 의존(`Dependencies:`)이 **비었거나 나열된 ID 가 모두 Done 집합에 속할 때만** 후보다. 그렇지 않으면 후보에서 빼고 `막힘(task-x 대기)` 로 표시한다.
- **Blocked** 태스크는 후보에서 제외하고, `Implementation Notes:` 첫 줄을 사유로 `막힘(사유)` 별도 표시한다.
- priority(High > Medium > Low, 미설정은 최하) 순으로 후보를 정렬한다.
- 후보에 `Labels: solo` 가 있으면 `[solo]` 를 병기한다(단독실행 — `/parallel-tasks` 선택에 영향).
- draft·milestone 은 제외한다(§1 에서 이미 목록에 없음).

## 4. 레거시 모드 (PLAN.md)

`backlog/` 가 없으면, 이 스킬 디렉터리의 `plan-context.sh --dump` 를 Bash 1회로 실행해 플랜 파일 전문을 받는다.

```
bash ~/.claude/skills/next-task/plan-context.sh --dump
```

exit 1(플랜 파일 없음)이면 알리고 `/init-backlog` 을 안내한 뒤 멈춘다.

각 플랜 파일에서 태스크 상태를 파악한다(표기가 표준 `T-N`/`I-N`/`M-N` 이 아닐 수 있다 — 근거는 본문뿐).

- `[→] IN_PROGRESS` 는 이어서 할 일로 맨 앞.
- `[ ] TODO` 중 순서·우선순위·의존상 지금 착수 가능한 것을 후보로. 선행 의존 미완은 `막힘(T-x 대기)`.
- `[!] BLOCKED` 는 후보 제외 + `막힘(사유)` 별도 표시.
- `단독실행: 필요` 필드가 있으면 병기.
- `I-N`·`M-N` 자체는 제외. 플랜 파일이 여럿이면 파일별로 묶어 밝힌다.

## 5. 보고하기

후보 목록을 낸다. 항목마다 **task ID·제목·AC 요약·지금 착수 가능한 이유 한 줄**(레거시는 플랜 파일명·ID·제목·완료 조건·이유). 맨 앞 하나를 추천한다. 후보가 없으면(모두 Done 이거나 전부 막힘) 그 상태를 알린다. 여기서 멈춘다 — 태스크·플랜·코드를 건드리지 않는다.
