# backlog 스킬군 공통 전제

backlog 계열 스킬(`add-draft`·`add-task`·`add-milestone`·`add-backlog`·`init-backlog`·`migrate-to-backlog`·
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

## ID 발급 (태스크 · 마일스톤)

**`backlog task create`·`draft promote` 로 태스크를, `backlog milestone add` 로 마일스톤을 만든
직후 ID 가드를 1회 돌린다** — 여러 개를 만들었으면 각각에 대해:

```bash
bash ~/.claude/skills/references/backlog-id-guard.sh fix TASK-N   # codex 는 ~/.codex/skills/…
bash ~/.claude/skills/references/backlog-id-guard.sh fix m-N      # 마일스톤 (접두사로 판별한다)
```

`ok=<ID>` 면 그대로, `moved=<옛 ID> -> <새 ID>` 면 그것의 ID 가 바뀐 것이니 **이후 명령·
커밋 태그·의존 지정에 새 번호를 쓴다**. 이어지는 `published=<ID>` 는 같은 파일이 GitHub 리모트에
있다는 뜻이다. `warning=unpublished` 는 새 ID 가 아직 다른 머신에 보이지 않는다는 뜻이므로 생성
결과에서 경고하고, 커밋·push 전에는 다른 머신이 같은 번호를 발급할 수 있다고 명시한다. 가드는
경고만 하고 임의로 커밋·push 하지 않는다. `skip=` 이면 대상 저장소가 아니니 그냥 넘어간다.
가드는 CLI 가 안 보는 두 곳(`backlog/archive/`, 아직 안 당겨온 리모트 브랜치)까지 훑는다 —
그 구멍으로 다른 머신과 같은 번호를 잡으면 sync 때 rename/rename 충돌이 나고, 그때는 이미 커밋
태그·문서가 그 번호를 참조하고 있어 수습이 비싸다(태스크 3건 + 마일스톤 m-22 두 벌이 그렇게 났다).
만들기 전에 번호를 알아야 하면 `next` / `next milestone`.

**`fix` 는 방금 만든 것에만 쓴다.** 이미 커밋된 것에 돌리면 가드가 `error=committed` 로 멈춘다
(exit 1) — 판정이 '이 번호가 max 인가' 라서, 다른 머신이 더 큰 번호를 올렸기만 해도 개명 대상이
되는데 그 개명은 커밋 태그·문서의 참조를 깨뜨린다. 그 상황에서 번호를 정말 바꿔야 하면
`backlog task edit`·`milestone rename` 과 참조 갱신을 손으로 한다(task-314).
마일스톤은 태스크 frontmatter 의 `milestone: m-N` 이 참조라, 그런 태스크가 이미 있으면
가드가 개명하지 않고 `error=refs` 로 멈춘다 — 그 경우는 `backlog milestone rename` 이 맞는 도구다.

## 착수 신선도

`start-backlog`·`loop-backlog` 는 상태를 바꾸기 전에 이번 호출의 착수 후보를 한 번에 검사한다:

```bash
bash ~/.claude/skills/references/backlog-start-guard.sh TASK-N [TASK-M ...]  # codex 는 ~/.codex/skills/…
```

가드는 현재 upstream, 없으면 `github` → `origin` 순으로 **GitHub 리모트 하나만** 고르고 3초 안에
fetch 한 뒤, 로컬 `HEAD` 에 없는 커밋이 후보의 backlog 파일을 건드렸는지만 수집한다. VPN 전용
리모트는 조회하지 않는다.

- `stale=TASK-N ref=... commits=...`: 다른 세션 변경일 수 있으므로 그 후보는 착수하지 않는다.
  `$sync` 또는 pull 로 합친 뒤 태스크 상태·AC·notes 를 다시 읽어 재판정한다.
- `fresh=TASK-N`: 이 검사 기준으로 원격 선행 변경이 없다.
- `unknown=TASK-N reason=...`: GitHub 리모트 없음·fetch 실패·remote ref 없음이다. 경고를 한 번
  남기되 로컬 상태로 계속한다. 네트워크 불확실성 때문에 착수 자체를 막거나 재시도 루프를 돌지 않는다.

스크립트는 사실만 수집한다. Blocked 해제 여부나 지정 태스크 강행 같은 판단은 각 소비 스킬의 기존
규칙이 맡는다.

## 분할은 묻지 않는다

**마일스톤·태스크를 어떻게 쪼갤지(태스크 수·경계·마일스톤으로 묶을지 여부)는 `AskUserQuestion`
대상이 아니다.** 조사한 내용을 근거로 알아서 나누고 바로 생성한 뒤, 어떻게 나눴는지 결과로
보고한다. 그 경계는 되돌리기 싼 결정이라(태스크는 언제든 추가·병합·삭제할 수 있다) 확인 왕복이
더 비싸다.

인터뷰는 **다르게 해석하면 다른 작업이 되는** 것으로 한정한다 — 목표·완료 조건·비목표, 접근
방식의 갈림길, 외부 제약. 여기서 추측하면 결과물 자체가 틀린다.

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
