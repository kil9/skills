---
description: backlog 태스크를 서브에이전트 다중 병렬(정찰·구현·검증 팬아웃 + 진행 중 코칭)로 구현·검증·커밋한다. "병렬로 전부 돌려줘 / 최대한 빨리 / 사람 많이 붙여서" 라고 할 때. 순차 단일은 /start-backlog, 자율 드레인은 /loop-backlog 다.
allowed_tools: [Bash, Read, Edit, Write, Glob, Grep, AskUserQuestion, Agent, SendMessage, TaskCreate, TaskList, TaskGet, TaskOutput, TaskStop, TaskUpdate, Skill]
---

`/start-backlog` 와 같은 일(구현 → 검증 → 커밋)을 하되, **가능한 모든 곳을 서브에이전트로 병렬화한다.**
정찰·구현·검증 세 국면을 각각 팬아웃하고, 구현 중에는 리드가 워커와 `SendMessage` 로 대화하며 코칭한다.
검증을 통과하지 않으면 머지하지 않고, 머지하지 않은 태스크는 Done 이 아니다.

## 0. 이 스킬의 전제 — 병렬 게이트를 적용하지 않는다

[`../references/parallel-worktree.md`](../references/parallel-worktree.md) 는 **배관**(worktree 생성·
워커 프롬프트·수정 허용 범위·ff-merge·실패 처리)만 이 스킬에 빌려준다. 그 문서의 **"병렬 적합성 게이트"·
"기본은 병렬이 아니다"·"substantial 태스크 ≥ 2개" 문턱은 이 스킬에 적용하지 않는다** — 사용자가 병렬을
지목해 부른 호출이고, 토큰 비용은 판단 근거에서 뺀다(2026-09-09 사용자 결정). 게이트를 다시 세워
솔로로 폴백하지 않는다. 태스크가 하나뿐이어도 §3 의 태스크 내부 팬아웃으로 병렬화한다.

**동시 서브에이전트 상한도 없다.** 글로벌 규칙의 "동시 5명" 상한은 이 스킬 호출에 한해 사용자가
명시적으로 해제했다. 필요한 만큼 동시에 띄우고, 배치로 쪼개 회수하지 않는다.

솔로로 돌아가는 경우는 하나뿐이다: **팀 도구를 못 쓸 때**(전제:
`CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` + `teammateMode`). 그때는 named 팀원 대신 일회성
서브에이전트 fire-and-collect 로 폴백하고(§4 의 중간 대화는 못 하므로 그 사실을 한 줄 보고),
그마저 불가하면 `/start-backlog` 를 안내하고 멈춘다.

공통 전제(CLI·`--plain`·상태 4종·ID·착수 신선도)는 [`../references/backlog-basics.md`](../references/backlog-basics.md).

## 1. snapshot · 대상 선정

`bash ~/.claude/skills/references/backlog-context.sh` 를 **한 번만** 호출한다. exit 2 는 backlog 없음
(`/init-backlog`, 옛 `PLAN.md` 만 있으면 `/migrate-to-backlog` 안내 후 중단), exit 3 은 CLI 설치 안내,
다른 non-zero 는 오류 보고 후 중단이다.

대상 선정은 `/start-backlog` §1 과 같되 **하나가 아니라 착수 가능한 전부**를 잡는다:

- **인자 없음**: In Progress 전부 + To Do 중 의존이 모두 Done 이고 Blocked 아닌 것 전부. 우선순위·
  생성순은 배분 순서에만 쓰고, 낮은 우선순위라고 이번 웨이브에서 빼지 않는다.
- **태스크 번호 지정**: 지정된 것만. Done 이면 알리고 제외, 의존 미해소·Blocked 면 `AskUserQuestion`.
- **작업 내용 서술**: `backlog task create` 로 등록한 뒤 그 태스크를 대상으로 삼는다(AC 는 검증 가능한
  문장으로 채운다). ID 확정 후 `backlog-context.sh TASK-N` 으로 상세 snapshot 을 갱신한다.
- `## hidden tasks` 가 0 이 아니면 그 목록도 후보다 — CLI 가 태스크를 조용히 감출 수 있다.

상태를 바꾸기 전에 후보 ID **전부**를 한 번에 신선도 검사한다:
`bash ~/.claude/skills/references/backlog-start-guard.sh TASK-N [...]`. `stale=` 은 이번 호출에서 제외,
`unknown=` 은 경고 한 번 남기고 유지.

## 2. 정찰 팬아웃 (구현 전, 읽기 전용)

대상 태스크 **하나당 하나씩** `Explore` 서브에이전트(`model: "sonnet"`)를 **동시에** 띄운다. 이름을
주지 않는다(일회성 위임 — 이름을 주면 최종 텍스트가 리드에 도달하지 않는다). 각 정찰에 태스크의
Description·AC 발췌를 주고 다음만 요구한다:

- 이 태스크가 **건드릴 파일 경로 목록**(추정 포함)과 그 근거.
- 이미 있는 유사 구현·컨벤션·재사용 지점, 관련 테스트 파일과 실행 명령.
- 이 태스크와 **다른 태스크가 겹칠 만한 지점**(공유 모듈·설정·마이그레이션).
- 구현하지 말 것. 파일을 고치지 말 것. 보고는 200줄 이내.

정찰 결과를 모아 **파일 터치 그래프**를 만든다. 이것이 다음 절의 배분 근거이고, 워커 프롬프트에
그대로 접어 넣어 워커의 cold-start 를 줄인다(정찰이 값을 하는 지점이 여기다).

## 3. 배분 — 태스크 간 병렬 + 태스크 내부 팬아웃

**태스크 간**: 1태스크=1워커가 기본. 파일 터치가 겹치는 태스크들은 **같은 워커에 묶어 직렬화**한다
(각각 별도 worktree·브랜치·커밋). `solo` label 은 이번 웨이브에서 빼고 모든 머지가 끝난 뒤 리드가
인라인으로 처리한다.

**태스크 내부**: 워커에게 자기 태스크 안에서 **읽기 전용 팬아웃을 쓰라고 명시적으로 허용**한다 —
넓은 탐색, 대안 조사, 테스트 목록 수집 같은 조사는 서브에이전트로 동시에 돌리고, 쓰기(구현·커밋)는
워커 자신이 한 손으로 한다. 태스크 하나만 잡은 호출에서도 이 팬아웃 때문에 병렬이 성립한다.

워커는 named 백그라운드 팀원(`Agent` + `name` + `run_in_background: true`), 모델은 지정이 없으면
`model: "opus"`, 기계적·단문맥 태스크만 `sonnet`/`haiku` 로 내린다. 디스패치 전 `TaskCreate` 로
태스크보드에 등록한다.

워커 프롬프트의 내용·수정 허용 범위·RESULT 블록 형식은 **`parallel-worktree.md` 의 "디스패치" 절이
정본**이다. 거기에 이 스킬이 더 얹는 것은 셋뿐이다:

- §2 정찰 보고 발췌(파일 목록·컨벤션·테스트 실행법)를 프롬프트에 넣는다.
- **중간보고 의무**: 착수 직후 계획 한 문단, 그리고 구현 방향이 정찰과 달라지거나 다른 태스크의
  파일을 건드리게 되면 **즉시** `SendMessage(to: "main")` 으로 알린다. 막히면 사용자가 아니라 리드에게.
- 읽기 전용 팬아웃 허용(위).

## 4. 중간 대화 (리드 ↔ 워커)

리드는 디스패치 후 손을 놓지 않는다. `SendMessage` 로 다음을 주고받는다:

- **교차 주입**: 한 워커가 보고한 사실(바뀐 인터페이스, 공유 모듈 수정, 새로 발견한 컨벤션)이 다른
  워커에게 필요하면 즉시 그 워커들에게 전달한다. 같은 것을 두 번 만들거나 서로의 가정을 깨뜨리는
  사고가 여기서 잡힌다.
- **범위 교정**: 중간보고가 태스크 밖으로 번지면 되돌린다.
- **실패 코칭**: `failed` RESULT 는 1-2회 진단·재시도를 코칭하고, 그래도 실패하면 블록 처리한다.
- **정체 확인**: 오래 무응답이면 `TaskGet`/`TaskOutput` 으로 보고, 필요하면 `TaskStop`.

워커끼리 직접 대화시키지 않는다 — 모든 교차 정보는 리드를 거친다. 워커가 자기 상태를 잘못 알고 있을
때 고칠 수 있는 곳이 리드 하나뿐이어야 한다.

## 5. 검증 팬아웃 (머지 전)

워커 자기보고를 그대로 믿지 않는다. 브랜치·커밋 SHA 의 실존을 확인한 뒤, **success 태스크마다
동시에** 검증자를 띄운다(전부 일회성, 이름 없음):

- **검증자 1**(`model: "opus"`): 블랙박스. worktree 경로·diff·AC·검증 실행법만 주고 워커의 구현
  서사와 `failure_context` 는 **넘기지 않는다**. 전체 검증 스위트를 **실제로 실행한 결과만** 판정
  근거로 인정하고, 가능하면 negative 확인(AC 를 위반하는 입력이 실제로 실패하는지) 1개 이상.
- **리뷰어**: diff 성격에 맞는 것을 골라 동시에 — `review-logic`, `review-security`,
  `review-performance`, `review-cleancode`. 보안 표면이 있으면 `review-security` 는 필수다.

CRITICAL/HIGH 지적은 머지 전에 해당 워커에게 `SendMessage` 로 돌려보내 고치게 하고(워커가 이미
끝났으면 리드가 그 worktree 에서 직접 고친다), 나머지는 §7 의 발견분으로 돌린다.

## 6. 머지 (리드 단독 · 순차)

병렬은 여기서 끝난다. 머지는 리드가 한 건씩 순차로 한다 — `parallel-worktree.md` 의 "머지 · 보고" 절
그대로: base ff-pull → `merge-base --is-ancestor` 확인 → 불가하면 worktree 에서 rebase → cwd 가 base
브랜치 디렉터리인지 확인 후 `merge --ff-only` → push → worktree remove + 브랜치 삭제.

머지마다 **메인에서** `backlog task view <id> --plain` 으로 상태·AC 체크·notes 를 확인하고, 워커가
빠뜨렸으면 리드가 `backlog task edit <id> -s Done --append-notes "<머지 요약>"` 으로 보정해 즉시
커밋·푸시한다(다음 rebase 충돌 면적을 줄인다).

`git add -A` 를 쓰지 않는다. 옆 세션이 같은 워킹트리에 붙어 있을 수 있으니 경로로 명시해 add 하고,
커밋 직전 `git status --porcelain` 으로 낯선 변경이 섞였는지 본다.

실패·블록 태스크는 머지하지 않고 worktree·브랜치를 진단용으로 남긴다. 상태는 To Do 로 두고(Blocked 로
강등하지 않음) 사유를 `--append-notes` 로 남긴다. 사람 개입 없이는 진행 불가일 때만 Blocked 다.

## 7. 발견분 · 설계 결정

머지 중 드러난 선행·후속 작업(누락된 마이그레이션, AC 를 막는 버그, 리뷰의 non-blocking 지적)은
리드가 태스크로 만든다: `backlog task create "<제목>" -d "parallel-backlog 발견: <맥락>" --ac "<완료 조건>"`.
"있으면 좋은" 개선은 태스크가 아니라 `backlog draft create` 다(`draft create` 에 `--ac` 는 없다 —
완료 조건은 `-d` 본문에 녹인다).

중요한 설계 결정은 `backlog decision create "<제목>"` 후 생성 파일에 배경·결정·이유를 채워 관련 커밋에
포함한다. 워커가 내린 결정도 리드가 머지 시점에 회수해 기록한다.

## 8. 다음 웨이브 · 완료 보고

이번 머지로 의존이 풀린 태스크가 생겼으면 **웨이브를 한 번 더 돈다**(§1 재조회 → §2 → §6). 새로
착수 가능한 것이 없을 때 멈춘다. 자율 드레인이 아니므로 §7 로 새로 만든 태스크까지 자동으로
집어 들지는 않는다 — 남은 것은 보고에 싣고 `/loop-backlog` 를 안내한다.

최종 보고: 웨이브별 성공/실패/블록 수, 머지된 태스크(ID·제목·SHA), 실패 태스크와 진단, 검증·리뷰에서
잡아 고친 것, 기록한 설계 결정, 새로 만든 태스크·draft, 남은 후보. Done 이 7개 이상이면
`Skill("cleanup-backlog")` 를 실행하고 그 결과를 한 줄로 덧붙인다(워커에게 시키지 않는다).
