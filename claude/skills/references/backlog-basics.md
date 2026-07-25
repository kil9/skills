# backlog 스킬군 공통 전제

backlog 계열 스킬(`add-draft`·`add-task`·`add-milestone`·`init-backlog`·`migrate-to-backlog`·
`next-backlog`·`start-backlog`·`loop-backlog`·`parallel-tasks`)이 공유하는 전제다. 각 스킬 본문은
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
