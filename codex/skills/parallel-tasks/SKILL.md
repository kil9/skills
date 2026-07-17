---
name: parallel-tasks
description: 상호 의존이 없는 태스크를 worker agent 들로 worktree에서 구현·커밋하고, 검증을 통과한 브랜치를 순차 ff-merge해 main에 직접 반영한다. backlog/ 가 있으면 backlog CLI 백엔드, 없으면 레거시 PLAN.md 로 동작한다. 병렬 이득이 작으면(독립·substantial 태스크 부족) 팀을 띄우지 않고 솔로로 폴백한다. 사용자가 명시적으로 herdr pane 을 지시한 경우에만(opt-in) 팀 대신 herdr pane 워커로 돌린다.
---

미완료 태스크 중 상호 의존이 없는 것들을 named 백그라운드 worker agent(필요하면 먼저 `tool_search` 로 multi-agent 도구를 노출한다)에게 배분해 각자 worktree 에서 구현·검증·커밋시키고, 성공한 브랜치를 base(보통 main)에 순차 fast-forward 머지한다. **PR 은 만들지 않고**, 태스크 사이에 사용자 확인도 묻지 않는다. multi-agent 도구가 없으면 worker agent fire-and-collect 로 폴백한다. 사용자가 명시적으로 herdr pane 사용을 지시한 경우에만 "herdr pane 모드"로 워커를 돌린다. `HERDR_ENV=1` 이라는 이유만으로 자동 전환하지 않는다.

**모드 감지**: repo 루트에 `backlog/`(또는 `backlog/config.yml`)가 있으면 **backlog 모드**(기본 서술), 없으면 **레거시 PLAN.md 모드**(맨 아래 절). backlog 조회는 전부 `--plain` 으로 하고 board/browser 는 실행하지 않는다.

**CLI 없으면 중단**: backlog 모드면 `command -v backlog` 로 확인한다. 없으면 태스크 파일 손편집으로 폴백하지 말고(`SECTION:` 마커·ordinal·AC 포맷이 조용히 어긋나고, 팀원마다 제각각 깨진다) `bash "${K9HOME:-$HOME/kil9conf}/bootstrap/install-backlog-md.sh"` 설치를 안내한 뒤 멈춘다. 팀원 worktree 도 같은 PATH 를 쓰므로 리드에서 없으면 팀원에게도 없다.

## 태스크 추출 (backlog 모드)

1. `backlog task list --plain` 으로 상태별 목록을 얻는다. list 출력에는 dep·label 이 안 나오므로 To Do 태스크마다 `backlog task view <id> --plain` 으로 **Dependencies·Labels** 를 확인한다.
2. 이번 라운드 후보 = **To Do 이면서** Dependencies 가 비었거나 나열된 dep 이 **모두 Done** 인 태스크. `Blocked` 상태는 제외한다.
3. `solo` label 태스크는 워커 병렬 배분에서 제외하고, 이번 라운드 머지가 모두 끝난 뒤 리드가 인라인으로 순차 처리한다.

## 병렬 적합성 게이트

병렬은 공짜가 아니다. 실측(이 머신 전사 분석): 워커는 리드 대화를 상속받지 못해 컨텍스트를 cold 로 재구성하고, 3\~5명을 띄워도 실효 동시성은 약 1.8x(최악 0.73x, 직렬보다 느림), 토큰은 단일 에이전트 대비 3\~10배다. 따라서:

- **substantial 독립 태스크 ≥ 2개**(워커 cold-start 를 상쇄할 만큼 큰 것. 다파일·신규 구현·리팩터급)일 때만 팀을 띄운다. 사소한 태스크(단일 파일·기계적 수정)는 워커에 끼우지 말고 리드가 인라인 처리한다.
- 아니면 솔로 폴백(직접 순차 처리 또는 `$start-task`). 폴백 이유를 한 줄 보고하고 진행한다.
- 위 수치는 opus/sonnet 워커 실측이라 보수적이다. 워커가 상위 모델(Fable 등)로 돌 때는 cold-start 페널티가 낮으므로 문턱을 한 단계 낮춰 병렬을 더 적극 채택해도 된다.

## 디스패치

1태스크=1워커 기본, 팀 규모는 `min(태스크 수, 5)`. 많으면 워커당 여러 태스크를 순차(각각 별도 worktree·브랜치)로 처리시킨다. 같은 파일을 건드릴 가능성이 큰 태스크들은 같은 워커에게 묶어 직렬화한다. 분해는 항상 컨텍스트 경계 기준. 한 태스크의 구현/테스트/리뷰를 여러 워커에 나누면 핸드오프마다 컨텍스트가 유실되므로 한 워커가 완결한다. 디스패치 전 `update_plan` 으로 태스크보드에 등록한다.

**워커 모델**: 호출 시 지정이 없으면 `model: "opus"` 를 기본으로 명시한다(가벼운 태스크는 sonnet). 리드가 상위 모델(Fable 등)로 돌아도 워커에게 상속시키지 않기 위함. 특별히 무거운 태스크만 리드 재량으로 그 태스크에 한해 올린다.

워커 프롬프트에는 `MAIN_PATH`·`BASE_BRANCH`·`REPO_NAME`·`TASK_ID`(예: `task-2`)·`backlog task view <TASK_ID> --plain` 발췌·경로안전 `TASK_SLUG`(영문/숫자/하이픈/언더스코어 외 `_` 치환)를 넣고 다음을 지시한다:

- worktree 생성: `git -C {MAIN_PATH} worktree add -b task/{TASK_SLUG}_{slug} {MAIN_PATH}/../{REPO_NAME}__{TASK_SLUG} {BASE_BRANCH}`, 이후 모든 git 은 `git -C <worktree>` 로.
- 정의·참조·테스트를 먼저 읽고 구현. 한국어 커밋 `[{TASK_ID}] 요약`(규칙은 `$commit`).
- **수정 허용 범위**: 코드 + 자기 태스크의 `backlog/tasks/task-<id>*.md` 파일만. 착수 시 worktree 안에서 `backlog task edit <TASK_ID> -s "In Progress"`, 완료 시 AC 항목별 `--check-ac N` 과 `--append-notes "<요약>"`, `-s Done` 을 CLI 로 수행하고 그 태스크 파일 변경을 **같은 커밋**에 포함한다. **AGENTS.md/README.md 등 메타 파일·다른 태스크 파일 수정 금지**. 메타 파일은 리드가 머지 단계에서 일괄 처리한다.
- 스택에 맞는 검증(typecheck/lint/build/test)을 모두 통과시킨다. `--no-verify` 등 안전 우회 금지.
- RESULT 블록(`task`/`status`(success|failed)/`branch`/`worktree`/`commit`/`checks`/`failure_context`)을 최종 메시지로 리드에게 보고. `checks` 에는 **이번 세션에서 실제 실행한 명령과 결과만** 적고, 못 돌린 검증은 그렇다고 명시한다. 안 돌린 검증을 통과로 적지 말 것.
- 사용자에게 묻지 말고(막히면 리드에게), worktree·브랜치를 직접 정리하지 말고, 실패해도 부분 커밋을 그대로 두고, PR 생성 금지.

`failed` 보고는 1\~2회 진단·재시도를 코칭하고, 그래도 실패하면 블록 처리한다. 무응답 워커는 출력을 확인 후 필요시 중단시킨다.

## herdr pane 모드 (opt-in)

기본값은 pane 미사용(위 팀/worker agent 경로)이다. 사용자가 호출 시 명시적으로 herdr pane 을 지시했을 때만 전환한다. 그 지시는 단점(skip-permissions 전권 실행, 조율 왕복 증가)을 감수하고 워커 작업을 실시간으로 지켜보겠다는 뜻이므로 재판단 없이 pane 을 쓴다. 적합성 게이트의 팀/솔로 판단과 무관하게 substantial 태스크가 1개뿐이어도 pane 워커로 스폰한다(사소한 태스크의 리드 인라인 처리 규칙은 유지). `HERDR_ENV` 가 `1` 이 아니면 pane 불가 사유를 한 줄 보고하고 기본 경로로 진행한다.

태스크 선별·프롬프트 내용·머지 로직은 동일하고 워커 실행 배관만 바뀐다. 그 배관 상세(스폰 명령·
ccs 프로필 전파·결과 파일 회수·코칭 주입·pane 정리)는
**[`references/herdr-pane-mode.md`](references/herdr-pane-mode.md)** 에 있다 — pane 모드로 갈 때만 읽는다.

## 머지 · 보고

워커 자기보고를 그대로 믿지 않는다: 브랜치·커밋 SHA 가 실제 존재하는지 확인하고, 위험이 큰 태스크는 머지 전에 fresh-context 검증자 워커를 띄울 수 있다(선택). 검증자는 블랙박스로. worktree 경로·diff·태스크의 체크 가능한 성공 기준(AC)·검증 실행법만 주고, 워커의 구현 서사·failure_context 는 넘기지 않는다. 전체 검증 스위트를 실제 실행한 결과만 판정 근거로 인정하고, 가능하면 negative 확인(기준을 위반하는 입력이 실제로 실패하는지) 1개 이상.

success 브랜치만 태스크 순으로 한 건씩: base ff-pull → `merge-base --is-ancestor` 로 ff 가능성 확인, 불가면 worktree 에서 rebase. **태스크 파일이 태스크별로 분리돼 있어 태스크 파일 충돌은 구조적으로 없다.** 그 외 파일 충돌은 `rebase --abort` 후 블록 처리하고 다음으로. 머지는 cwd 가 base 브랜치 디렉터리인지 확인 후 `merge --ff-only` → `push origin {BASE_BRANCH}` → `push github {BASE_BRANCH} 2>/dev/null || true` → worktree remove + 브랜치 삭제.

머지마다 리드가 **메인에서** 해당 태스크의 상태·notes 를 `backlog task view <id> --plain` 으로 확인한다. 워커가 Done 전이·notes 갱신을 안 했으면 리드가 `backlog task edit <id> -s Done --append-notes "<머지 요약>"` 으로 보정하고, 그 태스크 파일 변경을 즉시 커밋·푸시한다(다음 rebase 충돌 면적 축소).

실패·블록 태스크는 머지하지 않고, worktree·브랜치를 사용자 진단용으로 남긴다. 상태는 To Do 로 두되(Blocked 로 강등하지 않음), 사유를 `backlog task edit <id> --append-notes "자동 실행 실패: <한 줄>"` 로 남긴다.

최종 보고 전에 Done 태스크가 7개 이상 쌓여 있으면 리드가 `$cleanup-tasks` 를 실행해 정리한다(완료 태스크를 completed 폴더로 이동). 팀원에게 시키지 않는다 — 모든 머지가 끝난 뒤 리드에서 한 번만 돈다.

최종 보고: 성공/실패/블록 수, 머지된 태스크(ID·제목·SHA), 실패 태스크와 진단, cleanup 결과(해당 시 정책·이동 건수·커밋), 이번 머지로 dep 이 풀린 다음 라운드 후보(위 "태스크 추출" 기준으로 재산출). 후보가 있으면 "다시 `$parallel-tasks` 를 실행하면 처리됩니다" 로 안내한다(자동 재실행 금지).

## 레거시 모드 (PLAN.md)

repo 에 `backlog/` 가 없으면 `PLAN.md`(없으면 `PLAN_*.md`, 여러 개면 최근 수정본)를 진실원본으로 쓴다. PLAN 이 없으면 `$init-backlog` 을 안내하고 중단한다. 위 병렬 적합성 게이트·디스패치·herdr pane 모드·머지 절차를 그대로 쓰되 아래만 다르다:

- **태스크 추출**: PLAN 에 실제 쓰인 ID 체계를 그대로 쓴다. 의존 판단. 표준 필드 `의존:` 이 있으면 그 값만(`의존: 없음` 이면 없음 확정), 없는 구식 플랜은 본문의 `Depends on:`·`선행:` 등을 쓰되 명시가 없어도 절차상 직전 태스크 산출물을 명백히 전제로 하면 의존으로 본다. dependencies 가 비었거나 모두 DONE 인 미완료 태스크가 대상, `[!] BLOCKED` 는 제외, `단독실행: 필요` 는 워커 배분에서 빼고 라운드 머지 후 리드 인라인 처리.
- **워커 수정 범위**: 코드만. **PLAN.md/AGENTS.md/README.md 수정 금지**(메타 파일은 리드가 머지 단계에서 일괄 처리). RESULT 블록은 최종 메시지로 보고, 커밋은 `[{TASK_ID}] 요약`.
- **머지 시 PLAN 충돌 해소**: 충돌이 `PLAN.md` 뿐이면 append-only 로 해소한다(양쪽 진행 로그 시간순 보존, 같은 태스크 상태 라인은 완료>진행>TODO 로 통합). 그 외 파일 충돌은 `rebase --abort` 후 블록. 머지마다 메인의 PLAN.md 에 완료·머지 SHA 를 기록하고 즉시 커밋·푸시한다.
- 실패·블록 태스크는 PLAN.md 진행 로그에 `자동 실행 실패: <한 줄>` 을 append(상태 TODO 유지).
- 최종 보고 전 완료(`[x]`) 태스크가 5개 이상이면 리드가 완료 태스크를 작업 ID·한 줄 요약만 남기도록 압축하고 별도 커밋·푸시한다(머지 반영이 모두 끝난 뒤에만). 다음 라운드 후보가 있으면 "다시 `$parallel-tasks` 를 실행하면 처리됩니다" 안내.
