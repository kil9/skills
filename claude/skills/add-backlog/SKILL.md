---
description: 작업이나 아이디어를 backlog 에 등록한다 — 태스크 하나, 마일스톤과 태스크들, 보류 draft 중 맞는 형태를 골라서. "백로그에 넣어줘 / 태스크 추가 / 마일스톤 추가 / 계획으로 정리해줘 / 나중에 해보자, 적어만 둬 / 이 draft 태스크로 올려줘" 라고 할 때. 작업은 시작하지 않는다(착수는 /start-backlog).
allowed_tools: [Bash, Read, Edit, Write, Glob, Grep, AskUserQuestion, Skill]
---

등록할 것: `$ARGUMENTS`

구현·커밋은 하지 않는다 — 등록만 한다. 공통 전제(CLI 전용·`--plain`·상태 4종)는
[`../references/backlog-basics.md`](../references/backlog-basics.md). `backlog/` 가 없으면
`/init-backlog` 를 안내한다.

## 형태는 판단한다

서술할 만큼만 조사하고(이름 중복·선행 태스크는 `backlog-context.sh` 나 `task list --plain`) 형태를 고른다.
쪼개는 방식(태스크 수·경계·마일스톤으로 묶을지·우선순위·의존)은 묻지 않고 정한 뒤 결과로 보고한다.
묻는 것은 **다르게 해석하면 다른 작업이 되는 것**뿐이다 — 목표·완료 조건·접근의 갈림길.

- **보류("나중에 / 적어만 둬 / 아이디어")** → draft. 묻지 않고, 사용자 구상을 손실 없이 담는다.
  명백한 기술적 충돌이 보이면 "착수 시 검토 필요: …" 를 덧붙인다.

  ```
  backlog draft create "<제목>" -d "<구상 원문>

  접수: <날짜>. 착수 전 상세화 필요."
  ```

  `draft create` 에는 `--ac` 가 없다(`unknown option` 으로 죽는다).
- **지금 할 일 하나** → 태스크.

  ```
  backlog task create "<제목>" -d "<배경·접근>" --ac "<완료 조건>" [--ac ...] \
    [--dep task-N[,task-M]] [--priority high|medium|low] [-l solo] [-m "<마일스톤>"]
  ```

  `--ac` 는 1개 이상 필수(검증 가능한 문장). `-l solo` 는 다른 태스크와 병렬이 안전하지 않을 때.
- **여러 태스크로 이뤄진 덩어리** → `backlog milestone add "<이름>" -d "<목표·범위>"` 후 태스크마다
  `-m "<이름>"`. 마일스톤엔 의존 필드가 없으니 순서는 태스크 `--dep` 로 표현한다. 구획만 확정되고 세부가
  없으면 마일스톤만 만들어도 된다.
- **기존 draft 승격** → `backlog draft promote <draft-id>` 후 `backlog task edit <id> --ac ...` 로 AC 를
  최소 1개 채운다(draft 엔 AC 가 없다).

## 보고

고른 형태와 근거 한 줄, 만든 마일스톤·태스크·draft 의 ID·제목.
