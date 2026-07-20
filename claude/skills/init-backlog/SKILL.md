---
description: 작업 계획을 수립하고 현재 저장소를 backlog 백엔드로 초기화한다. 산문은 backlog/docs/, 태스크는 `backlog task create` 로 만든다. 구현은 시작하지 않는다(소비는 /start-task·/parallel-tasks 몫). 사용자가 명시적으로 지시할 때만 이어서 진행한다.
allowed_tools: [Bash, Read, Edit, Glob, Grep, AskUserQuestion]
---

작업 설명: `$ARGUMENTS`

이 스킬은 backlog 도입점이다. 저장소를 backlog 백엔드로 초기화하고 계획을 태스크로 심는다. 기존 PLAN.md 가 있어도 새 PLAN 파일을 만들지 않고 backlog 를 쓴다(기존 PLAN 파일은 건드리지 않는다). 레거시(PLAN.md) 분기는 없다.

**backlog CLI 조회 명령엔 항상 `--plain` 을 붙인다. board·browser 등 인터랙티브 명령은 실행하지 않는다.** CLI 옵션이 낯설면 `backlog <command> --help` 로 확인한다.

**CLI 없으면 중단.** 시작 전 `command -v backlog` 로 확인한다. 없으면 태스크 파일 손편집으로 폴백하지 말고(`SECTION:` 마커·ordinal·AC 포맷이 조용히 어긋난다) `bash "${K9HOME:-$HOME/kil9conf}/bootstrap/install-backlog-md.sh"` 설치를 안내한 뒤 멈춘다.

## 절차

**1. 인터뷰.** 조사로 메워지지 않는 디테일(문제 정의, 목표·비목표, 접근 방식과 근거, 작업 범위, 제약, 검증 전략, 우선순위, 태스크 의존 관계, 단독 실행 필요 여부)은 의문이 없어질 때까지 집요하게 `AskUserQuestion` 으로 인터뷰한다. 추측으로 채우지 않고 줄글 자유 입력도 받지 않는다.

**2. 초기화.** `backlog/config.yml`(또는 `backlog/`)이 없으면 초기화한다. 이미 초기화돼 있으면 건너뛴다.

```bash
backlog init "<프로젝트명>" --defaults --integration-mode none --zero-padded-ids 0
```

`--integration-mode none` 으로 에이전트 지침(CLAUDE.md/AGENTS.md) 자동 주입을 막는다. 그 역할은 이 스킬군이 한다.

**3. config 표준 적용.** 공유 스크립트로 일괄 적용한다(멱등 — 이미 표준이면 아무것도 바꾸지 않는다). 항목을 손으로 확인하지 않는다.

```bash
bash ~/.claude/skills/init-backlog/backlog-config-standard.sh
```

statuses·default_status·auto_commit 을 표준으로 맞추고, origin 리모트가 없을 때만 remoteOperations 를 끈다. 근거는 스크립트 헤더 주석 참조. `/migrate-to-backlog` 도 같은 스크립트를 쓴다.

**4. 산문 저장.** 배경/문제/목표/비목표/제약/접근 방식과 근거/검증 방법을 `backlog/docs/` 에 저장한다. 세션 리셋 후에도 이 문서 + 태스크만으로 재개 가능할 만큼 상세히 적는다.

```bash
backlog doc create "<제목>"
backlog doc update <docId> --content "<본문 마크다운>"
```

`doc create` 는 본문을 받지 않으므로 생성 후 `doc update --content` 로 본문을 채운다(문서 파일을 직접 편집하지 않는다).

**5. 태스크 생성.** 각 태스크를 `backlog task create` 로 만든다.

```bash
backlog task create "<제목>" --ac "<완료 조건>" --dep task-N --priority high -l solo -m "<마일스톤>" --plain
```

- `--ac` 는 반드시 1개 이상(항목마다 `--ac` 반복). 완료 조건 = Acceptance Criteria.
- 의존은 `--dep task-N`(쉼표 구분 다중 가능). 참조 유효성은 CLI 가 검증한다. 선행이 없으면 `--dep` 를 생략한다(빈 의존 = 의존 없음 확정).
- 우선순위는 `--priority`(high / medium / low).
- 다른 태스크와 병렬 실행이 안전하지 않으면 `-l solo`.
- 규모가 커 태스크를 묶을 단위가 있으면 `backlog milestone add "<이름>"` 후 `-m "<이름>"` 로 배정한다.

접수일(created_date)은 자동 기록되므로 따로 넣지 않는다. 태스크는 기본 `To Do` 로 생성된다. 상태 4종은 `[ ]` To Do / `[→]` In Progress / `[x]` Done / `[!]` Blocked 이고(Blocked 사유는 태스크 notes 첫 줄), 상태 전이는 소비자 스킬이 다룬다.

아직 착수하지 않을 보류 아이디어는 태스크로 만들지 말고 `/add-draft` 로 draft 에 남기도록 안내한다.

## 마무리

생성한 태스크 목록과 doc 경로를 보고하고 **멈춘다. 구현은 시작하지 않는다**(생산자 원칙: 이 스킬은 계획 수립까지만 담당한다). 소비는 `/start-task`(순차)·`/parallel-tasks`(병렬) 몫임을 안내한다. 사용자가 이 세션에서 바로 진행하라고 명시적으로 지시할 때만 `/start-task` 절차로 이어간다.

계획에 태스크를 더 얹거나 보류 아이디어를 관리하려면 `/add-task`·`/add-draft`, 다음 착수 후보 조회는 `/next-backlog` 를 쓴다.
