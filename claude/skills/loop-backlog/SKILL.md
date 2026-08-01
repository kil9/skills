---
description: backlog 태스크를 스스로 진행 가능한 것이 남지 않을 때까지 라운드 단위로 자율 드레인한다. "백로그 다 해줘 / 남은 태스크 전부 진행 / 병렬로 해줘" 라고 할 때(게이트를 통과하면 worktree 병렬로 돌린다). 한 태스크만은 /start-backlog, 추천만은 /next-backlog 다.
allowed_tools: [Bash, Read, Edit, Write, Glob, Grep, Agent, SendMessage, TaskCreate, TaskList, TaskGet, TaskOutput, TaskStop, TaskUpdate, Skill]
---

backlog 를 **스스로 진행할 수 있는 태스크가 남지 않을 때까지** 라운드 단위로 자율 드레인한다(백엔드가 PLAN 파일이면 `/loop-plan`). 각 라운드: **fresh 재조회 → ready set → 실행 → 발견분 자동 추가**. 각 태스크는 구현 → 검증 → 커밋(`/start-backlog` 규칙)으로 완결한다. **한 번 읽고 비었다고 종료하지 않고**(§5), **인터랙티브 질문으로 멈추지 않는다**(§3).

## 0. 전제 · snapshot

매 라운드 `bash ~/.claude/skills/references/backlog-context.sh`를 **한 번만** 호출해 snapshot만 읽고 목록·상세를 따로 재조회하지 않는다. exit 2면 PLAN 파일은 `/loop-plan`, 없으면 `/init-backlog`; exit 3은 CLI 설치; 다른 non-zero는 오류 보고 후 라운드 중단이다. 공통 전제는 [`../references/backlog-basics.md`](../references/backlog-basics.md)를 따른다.

## 1. 라운드 · ready set

매 라운드의 새 snapshot에서 `## tasks` 상태 그룹과 미완료 task의 `===== TASK-N =====` 원문을 읽는다. 따라서 외부 세션·사용자가 라운드 중 추가한 태스크를 흡수하면서 Dependencies·Labels·AC도 같은 snapshot에서 확인한다.

ready set = 지금 스스로 착수 가능한 태스크:

- **In Progress**(이어서 진행 — 최우선).
- **To Do** 중 의존이 모두 Done, Blocked 아님, **self-actionable**(진행에 사용자의 중대한 결정이 필수가 아님 — §3).
- **Blocked** 는 제외하되, 막힘 사유가 해소된 게 확인되면 `backlog task edit <id> -s "To Do"` 로 되돌려 포함한다.

첫 라운드의 ready set 을 확정하면 상태를 바꾸기 전에 후보 ID 전부를 공통 전제의 **착수 신선도**
가드로 한 번에 검사한다. `stale=` 후보는 이번 호출의 ready set 에서 제외하고, `unknown=` 은 경고를
한 번 남긴 뒤 유지한다.

## 2. 실행 (솔로 기본 · 병렬은 게이트 통과 시만)

**기본은 솔로 순차.** ready set 을 우선순위·의존 순으로 한 태스크씩 `/start-backlog` 루프(구현 → 검증 → 커밋, AC 기계화, 태스크 파일 변경을 같은 커밋에)로 완결하고 §3·§4 를 얹는다.

병렬은 [`../references/parallel-worktree.md`](../references/parallel-worktree.md) 의 병렬 적합성 게이트(팀원 cold-start·낮은 실효 동시성·토큰 배수의 함정)를 **인지하고도** 이득이 분명할 때만 쓴다: ready set 에 substantial 독립 태스크(다파일·신규·리팩터급이고 서로 파일이 안 겹침) ≥ 2개일 때. 애매하면 솔로. 선택 사유를 한 줄 보고한다.

- 병렬 라운드는 게이트를 통과하는 태스크만 그 문서의 절차(worktree → 순차 ff-merge, 워커 수정범위 제한)로 돌리고(리드가 직접 수행한다 — 별도 스킬로 위임하지 않는다), 나머지 사소·의존 태스크는 리드가 인라인 처리한다. 워커 프롬프트에 "발견한 선행·후속 작업을 RESULT 로 보고"를 넣고 리드가 머지 후 §4 로 태스크화한다(워커는 자기 태스크 파일 외 backlog 를 건드리지 않는다).

## 3. 하이브리드 막힘 정책 (질문으로 멈추지 않는다)

- **사소한 결정**(네이밍·에러 처리·라이브러리 세부 등 되돌리기 쉬운 것): 스스로 합리적으로 정해 진행. 영향이 크면 `backlog decision create "<제목>"` 후 생성 파일에 배경·결정·이유를 채워 커밋에 포함.
- **사용자 몫인 중대한 갈림길**(결과를 크게 바꾸거나 되돌리기 어려움): 추측으로 밀지 않는다. `backlog task edit <id> -s Blocked --notes "결정 필요: <질문 한 줄>"` 로 미뤄 두고 다음 태스크로. self-actionable 이 아니므로 종료를 막지 않는다.
- **재실행으로 풀릴 일시적 실패**(flaky·환경): Blocked 아님 — To Do 유지 + `--append-notes` 로 로그, 다음 라운드 재시도. 같은 태스크가 반복 실패하면 그때 Blocked 로 전이한다.

## 4. 발견분 자동 추가

기존 태스크 완료에 **실제로 필요한** 선행·후속 작업(누락된 마이그레이션, 선행 리팩터, AC 를 막는 버그 등)을 발견하면 즉시 태스크로 만들어 다음 라운드가 집게 한다:

```
backlog task create "<제목>" -d "loop-backlog 자동 추가: <발견 맥락·왜 필요>" --ac "<완료 조건>" [--dep task-N] [--priority high|medium|low]
```

생성 직후 ID 가드를 태스크마다 1회 돌린다(`../references/backlog-basics.md` 의 '태스크 ID 발급'). `moved=` 가 나오면 그 태스크의 ID 가 바뀐 것이니 이후 보고·의존·커밋 태그에 새 번호를 쓴다.

인터뷰(`/add-task`)는 하지 않고 완료 조건을 스스로 도출한다.

- **scope creep 경계**: "있으면 좋은" 개선은 태스크가 아니라 `backlog draft create "<제목>"` 로(draft 는 ready set 밖). ⚠ `draft create` 에는 `--ac` 가 없다(`unknown option` 으로 죽는다) — 완료 조건은 `-d` 본문에 녹여 쓴다.
- **착수 자체가 외부 조건에 막힌 후속도 태스크가 아니라 draft 다** — 아직 발표되지 않은 공시·미출시 버전·상대방 응답 대기처럼 *내가 무엇을 하든 지금은 시작할 수 없는* 일. 태스크로 만들면 라운드마다 ready 판정에 걸려 Blocked 로 밀리고 종료 보고에 계속 실려 노이즈가 된다. 조건이 풀리는 시점을 draft 본문에 적어 둔다.
- 자동 추가분의 완료 조건 자체가 사용자 결정을 요하면 만들되 §3 대로 Blocked 로 둔다(이건 *지금 착수 가능하되 답이 필요한* 경우라 위와 다르다).

## 5. 종료 (연속 2회 빈 조회 필수)

ready set 이 비어도 **즉시 종료하지 않는다** — 외부 세션·사용자가 방금 태스크를 추가했을 수 있다. 빈 라운드 뒤 §1 로 **한 번 더 재조회**해 그것도 비었을 때만 종료한다(연속 2회 빈 조회). 새 태스크가 생겼으면 라운드를 재개한다.

**수렴 안전장치**: 자동 추가(§4)가 새 태스크를 계속 만들어 backlog 가 줄지 않으면(예: 3라운드 연속 Done 0 · 신규만 증가) 무한 루프로 보고 멈추고 남은 태스크를 사용자에게 알린다.

## 6. 마무리

backlog 데이터가 파일에 영속되므로 재개 가능한 진실원본이다 — 라운드/커밋 경계에서 세션 리셋 후 이 스킬을 다시 호출해도 손실이 없다. 종료 시 보고: 완료·자동 추가·Blocked(사유·질문 포함) 태스크, 기록한 설계 결정, 종료 근거. Done 이 7개 이상이면 `Skill("cleanup-backlog")` 를 실행해 정리하고 그 결과(정책·이동 건수·커밋)를 한 줄로 덧붙인다.
