---
name: add-backlog
description: 마일스톤·태스크 구성을 재량으로 정해 작업을 backlog 에 등록한다. "알아서 나눠서 백로그에 넣어줘 / 이거 계획으로 정리해줘" 처럼 구성이 미정일 때. 구성이 이미 정해졌으면 $add-task·$add-milestone 다. 작업은 시작하지 않는다.
---

등록할 작업: `$ARGUMENTS`

공통 전제(설치 명령·`--plain` 규칙·상태 4종)는
[`../references/backlog-basics.md`](../references/backlog-basics.md). 구현·커밋은 하지
않는다 — 구성을 정해 등록만 한다. `backlog/` 가 없는 새 저장소면 `$init-backlog`
으로 먼저 초기화하도록 안내한다.

## 절차

1. **조사·인터뷰.** 항목을 서술할 만큼만 가볍게 조사한다(`backlog milestone list --plain`·
   `backlog task list --plain` 으로 이름 중복·선행 태스크 확인). 남은 애매함은 `request_user_input`
   으로 해소하되 줄글 자유 입력은 쓰지 않는다. 무엇을 묻고 무엇을 묻지 않는지는
   `../references/backlog-basics.md` 의 '분할은 묻지 않는다'.
2. **구성 판정(재량).** 네 형태 중 하나를 고른다 — 태스크 1개 / 마일스톤 1개 + 태스크 N /
   마일스톤 N개 + 태스크 / 마일스톤만 N개(드묾 — 구획은 확정됐지만 태스크로 굳힐 세부가 아직
   없을 때. 태스크는 나중에 `$add-task`·`$add-milestone` 으로 채운다). 마일스톤 자체엔 의존
   필드가 없으므로 구획 간 순서 제약은 태스크 `--dep` 로 표현한다.
3. **생성.**
   - 태스크 1개면 `$add-task` 로 위임하고 종료한다(위임 사실을 보고에 남긴다).
   - 그 외에는 [`../add-milestone/SKILL.md`](../add-milestone/SKILL.md) 의 생성
     절차(생성 명령)를 마일스톤마다 적용한다. 태스크 없는 마일스톤은
     `backlog milestone add` 만 실행한다.
4. **보고.** 고른 형태와 그 근거 한 줄, 생성된 마일스톤 이름·태스크 ID·제목 목록을 알리고 끝낸다.
