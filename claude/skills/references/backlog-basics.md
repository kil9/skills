# backlog 스킬군 공통 전제

backlog 계열 스킬(`add-draft`·`add-task`·`add-milestone`·`init-backlog`·`migrate-to-backlog`·
`next-backlog`·`start-backlog`·`loop-backlog`)이 공유하는 전제다. 각 스킬 본문은
자기 고유 절차만 담고 여기를 가리킨다.

## CLI 전제

`backlog` CLI(backlog.md)가 진실원본을 다룬다. 없으면 설치를 안내한 뒤 멈춘다:

```bash
bash "${K9HOME:-$HOME/kil9conf}/bootstrap/install-backlog-md.sh"
```

**태스크 파일 손편집으로 폴백하지 않는다.** `SECTION:` 마커·ordinal·AC 포맷이 조용히 어긋나고,
에러 없이 진행되다 나중에 CLI 가 그 파일을 읽지 못하는 형태로 드러난다. 무인 루프나 팀 워커에서는
그 어긋남이 태스크마다 번진다. 팀원 worktree 도 리드와 같은 PATH 를 쓰므로 리드에 없으면 팀원에게도
없다.

## 태스크 ID 발급

**`backlog task create`·`draft promote` 로 태스크를 만든 직후 ID 가드를 1회 돌린다** — 여러 개를
만들었으면 각각에 대해:

```bash
bash ~/.claude/skills/references/backlog-id-guard.sh fix TASK-N   # codex 는 ~/.codex/skills/…
```

`ok=TASK-N` 이면 그대로, `moved=TASK-N -> TASK-M` 이면 그 태스크의 ID 가 바뀐 것이니 **이후 명령·
커밋 태그·의존 지정에 새 번호를 쓴다**. `skip=` 이면 대상 저장소가 아니니 그냥 넘어간다.
가드는 CLI 가 안 보는 두 곳(`backlog/archive/`, 아직 안 당겨온 리모트 브랜치의 태스크)까지 훑는다 —
그 구멍으로 다른 머신과 같은 번호를 잡으면 sync 때 rename/rename 충돌이 나고, 그때는 이미 커밋
태그·문서가 그 번호를 참조하고 있어 수습이 비싸다. 만들기 전에 번호를 알아야 하면 `next`.

## 조회 규칙

- 조회 명령에는 **항상 `--plain`** 을 붙인다.
- `board`·`browser` 등 인터랙티브 명령은 실행하지 않는다 — TUI 가 떠서 세션이 붙잡힌다.
- CLI 옵션이 낯설면 `backlog <command> --help` 로 확인한다.
- `task list --plain` 출력은 상태별 그룹으로 나오고 각 줄은 `[PRIORITY] TASK-N - 제목` 형식이다
  (priority 미설정이면 앞의 대괄호가 없다). draft·milestone 은 여기 안 나온다.
- `task view --plain` 의 `Status:` 값에는 글리프가 붙는다(`○ To Do` / `◒ In Progress` /
  `● Blocked` / `✔ Done`). 문자열 동등 비교하면 전부 어긋나므로 글리프를 떼고 본다.

## 모드 판별

- repo 루트에 `backlog/`(또는 `backlog/config.yml`)가 있으면 **backlog 모드**. 기본이다.
- 없고 `PLAN.md`(또는 최근 `PLAN_*.md`)만 있으면 **레거시 모드**.
- 둘 다 없으면 새 저장소다 — `/init-backlog` 으로 초기화하도록 안내한다.

## 상태 4종

| backlog | 레거시 PLAN | 뜻 |
|---|---|---|
| `To Do` | `[ ]` TODO | 아직 착수하지 않음 |
| `In Progress` | `[→]` IN_PROGRESS | 진행 중 — 이어서 할 일로 최우선 |
| `Done` | `[x]` DONE | 완료 |
| `Blocked` | `[!]` BLOCKED | 막힘. 사유는 태스크 notes 첫 줄(레거시는 항목 옆) |

`Blocked` 는 terminal 이 아니다 — 나이가 많아도 완료로 취급하거나 정리 대상으로 옮기지 않는다.
막힘 사유가 해소된 것이 확인되면 `backlog task edit <id> -s "To Do"` 로 되돌린다.

레거시 모드에서 실행 단위는 `T-N` 이며 `M-N`(마일스톤 묶음)·`I-N`(아이디어)은 진행 대상이 아니다.
비표준 ID 표기(`T1`, `NU-3` 등)는 존중한다 — 근거는 플랜 본문뿐이다.
