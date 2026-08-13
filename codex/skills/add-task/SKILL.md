---
name: add-task
description: 새 태스크를 하나 추가한다(인터뷰로 완료 조건·의존 확정). "태스크 추가 / 이거 백로그에 넣어줘" 라고 할 때, 기존 draft 를 태스크로 승격할 때. 보류 아이디어는 $add-draft 다. 작업은 시작하지 않는다.
---

추가할 태스크: `$ARGUMENTS`

공통 전제(설치 명령·`--plain` 규칙·상태 4종)는 [`../references/backlog-basics.md`](../references/backlog-basics.md). 구현·커밋은 하지 않는다 — 태스크만 만든다. `backlog/` 가 없는 새 저장소면
`$init-backlog` 으로 먼저 초기화하도록 안내한다.

---

## 절차

**CLI 없으면 중단.** `command -v backlog` 로 확인하고, 없으면 파일 손편집으로 폴백하지 말고 설치를 안내한 뒤 멈춘다.

먼저 위임·승격 여부부터 가른다.

- **아이디어(보류) 위임.** `$ARGUMENTS` 가 "(아이디어)"로 시작하거나 사용자가 아직 착수하지 말고
  보류만 원하면, 태스크로 만들지 말고 `$add-draft` 로 넘긴다. 인터뷰·구현도 하지 않는다.
- **draft 승격(draft → task).** `$ARGUMENTS` 가 기존 draft 의 착수를 지시하면(대상 draft 는
  `backlog draft list --plain` 로 확인), 그 draft 본문을 출발점으로 아래 인터뷰를 거친 뒤
  `backlog draft promote <draft-id>` 로 승격하고, 곧바로 `backlog task edit <id> --ac ... [--dep ...]
  [--priority ...] [-l solo]` 로 완료 조건·의존을 보강한다. draft 는 승격 시점까지 AC 가 없으므로
  최소 1개 이상 AC 를 반드시 채운다.

그 외 신규 태스크는 다음 순서로 만든다.

1. 항목을 제대로 서술할 만큼만 코드베이스를 가볍게 조사한다(관련 파일·선행 태스크 확인 정도).
   선행 태스크 ID 는 `backlog task list --plain` 으로 확인한다.
2. 애매한 점(범위, 완료 조건, 접근 방식 등)이 하나라도 남으면 모두 해소될 때까지
   `request_user_input` 으로 인터뷰한다. 줄글 자유 입력은 쓰지 않는다. 단, **이 일을 태스크
   몇 개로 쪼갤지·마일스톤으로 묶을지는 묻지 않는다** — 재량으로 정하고 결과를 보고한다
   (`../references/backlog-basics.md` 의 '분할은 묻지 않는다'). 범위가 커서 태스크 여러 개가
   맞다고 판단되면 `$add-milestone` 으로 넘긴다.
3. 확정 내용으로 태스크를 생성한다:

   ```
   backlog task create "<제목>" \
     -d "<배경·접근>" \
     --ac "<완료 조건 1>" [--ac "<완료 조건 2>" ...] \
     [--dep task-N[,task-M]] [--priority high|medium|low] [-l solo]
   ```

   생성 직후 ID 가드를 태스크마다 1회 돌린다(`../references/backlog-basics.md` 의 '태스크 ID 발급'). `moved=` 가 나오면 그 태스크의 ID 가 바뀐 것이니 이후 보고·의존·커밋 태그에 새 번호를 쓴다.

   필드 대응: **완료 조건 → `--ac`(1개 이상 필수)**, 의존 → `--dep`(없으면 생략 = 의존 없음),
   단독실행(병렬 비안전) → `-l solo`, 우선순위 → `--priority`. 접수일(created_date)·태스크 ID·상태는
   도구가 채우므로 지정하지 않는다.

생성한 태스크의 ID·제목을 알리고 끝낸다.
