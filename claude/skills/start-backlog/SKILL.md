---
description: 저장소의 backlog 태스크를 구현·검증·커밋한다 — 하나든, 지정한 것만이든, 남은 것 전부든. "태스크 시작 / 이거 구현해줘 / 백로그 진행해줘 / 백로그 다 해줘 / 남은 태스크 전부 / all / 병렬로 돌려줘" 라고 할 때. 후보만 추리는 것은 /next-backlog 다.
allowed_tools: [Bash, Read, Edit, Write, Glob, Grep, AskUserQuestion, Agent, SendMessage, TaskCreate, TaskList, TaskGet, TaskOutput, TaskStop, TaskUpdate, Skill]
---

backlog 를 작업 목록이자 진행 기록으로 삼아 태스크를 끝낸다. **어떻게 할지는 판단에 맡긴다** — 몇 개를
잡을지, 순차로 할지 병렬로 할지, 서브에이전트·worktree 를 쓸지, 어디까지 조사하고 무엇을 물을지.
이 문서는 절차가 아니라 지켜야 할 불변식과 쓸 수 있는 도구 목록이다. 공통 전제(CLI 전용·`--plain`·
상태 4종·ID 충돌)는 [`../references/backlog-basics.md`](../references/backlog-basics.md).

## 범위

호출 인자와 사용자 말에서 읽는다.

- **인자 없음 / "진행해줘"**: In Progress 가 있으면 그것부터, 없으면 의존이 풀린 To Do 중 가장 급한 것.
- **번호 지정**: 그 태스크만. Done 이면 알리고, 의존 미해소·Blocked 면 사정을 말하고 어떻게 할지 묻는다.
- **작업 서술**: `backlog task create` 로 등록한 뒤 바로 진행한다(AC 는 검증 가능한 문장으로).
- **`all` / "다 해줘 / 남은 것 전부"**: 스스로 진행할 수 있는 것이 없을 때까지 드레인한다(아래 '드레인').

## 불변식

- **현황은 `bash ~/.claude/skills/references/backlog-context.sh [TASK-N ...]` 로 읽는다.** 목록·마일스톤·
  미완료 상세를 한 번에 주고, `backlog task list` 가 조용히 감춘 태스크를 `## hidden tasks` 로 되살린다 —
  목록만 보면 남은 일을 없는 일로 읽는다. exit 2 는 backlog 없음(`/init-backlog`, 옛 PLAN 이면
  `/migrate-to-backlog`), exit 3 은 CLI 없음.
- **착수 신선도**: 상태를 바꾸기 전에 `bash ~/.claude/skills/references/backlog-start-guard.sh TASK-N [...]`
  로 다른 세션이 그 태스크를 이미 건드렸는지 본다. `stale=` 이면 pull 후 다시 읽고, `unknown=` 이면
  경고만 하고 진행한다.
- 착수하면 `-s "In Progress"`. **AC 를 실제로 확인한 항목만 `--check-ac N`** 하고, 전부 체크되기 전엔
  Done 으로 바꾸지 않는다. Done 전이 때 `--notes` 에 무엇을·왜·검증 결과를 남긴다.
- **코드 변경과 그 태스크 파일 변경을 같은 커밋에** 담고 메시지에 `[task-N]` 을 넣는다(`/commit` 규칙).
  태스크마다 커밋을 나눈다.
- **Blocked 는 사람 개입 없이 못 나아갈 때만**이고 notes 첫 줄이 사유다. 재시도로 풀릴 실패는 To Do 에
  두고 `--append-notes` 로 로그만 남긴다.
- 되돌리기 어렵거나 결과를 크게 바꾸는 갈림길은 추측으로 밀지 않는다. 사용자가 있으면 묻고, 없거나
  드레인 중이면 `-s Blocked --notes "결정 필요: <질문>"` 으로 미루고 다음으로 간다.
- 여러 태스크에 걸치는 설계 결정은 `backlog decision create "<제목>"` 후 파일 본문(Context·Decision·
  Consequences)을 채워 관련 커밋에 넣는다.

## 드레인

- 하다가 발견한 **실제로 필요한** 선행·후속은 `backlog task create ... -d "<발견 맥락>" --ac ...` 로 만들어
  이어서 집는다. "있으면 좋은" 개선과 외부 조건(미출시·상대 응답 대기)에 막힌 후속은 draft 다
  (`backlog draft create` 에는 `--ac` 가 없다 — 완료 조건은 `-d` 에 녹인다).
- **빈 조회 한 번으로 끝내지 않는다.** 할 것이 없어 보이면 현황을 한 번 더 읽고, 그래도 없을 때 끝낸다 —
  옆 세션이 방금 추가했거나 목록이 감췄을 수 있다.
- 새 태스크만 늘고 Done 이 몇 라운드째 0 이면 수렴하지 않는 것이니 멈추고 보고한다.

## 병렬로 갈 때

판단해서 쓴다. 쓰기로 했다면 worktree 배관(워커 수정 범위·RESULT 회수·ff-merge 순서)은
[`../references/parallel-worktree.md`](../references/parallel-worktree.md) 를 따른다. 머지 전 검증에는
블랙박스 검증자 서브에이전트와 `review-logic`·`review-security`·`review-performance`·`review-cleancode`
에이전트를 쓸 수 있다. 사용자가 herdr pane 을 지시했으면 `/herdr` 스킬의 `references/backlog-pane-worker.md`.

## 끝맺음

완료·Blocked(사유)·새로 만든 태스크·draft·결정을 보고한다. Done 이 많이 쌓였으면
`Skill("cleanup-backlog")` 로 정리해도 된다. 태스크 파일이 진행 기록이라 커밋 경계에서 세션을 끊고
다시 불러도 이어진다.
