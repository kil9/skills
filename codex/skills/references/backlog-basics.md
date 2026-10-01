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

**CLI 가 주는 번호를 그대로 쓴다.** 발급 시 리모트를 훑어 번호를 피하던 ID 가드는 걷어냈다
(2026-08-22 사용자 결정) — 예방 기계가 낳은 유지보수가 그것이 막은 사고보다 많았다(가드 자체의
버그 수정이 다섯 건이었다). 만들기 전에 다음 번호를 알아야 하면 `backlog task list` 로 본다.

**충돌은 예방하지 않고 발견해서 고친다.** 두 머신이 같은 번호를 발급하면 병합 시점에 드러나고
(kil9conf 는 `bootstrap/verify.sh` 의 `=== backlog ===` 가 중복 ID 를 WARN 한다), 그때 한쪽을
개명한다:

1. 두 후보 각각의 참조 수를 센다 — `rg -n 'task-N\b'` 로 코드 주석·테스트·문서를, `git log
   --oneline --grep '\[task-N\]'` 로 커밋 태그를 본다.
2. **참조가 많은 쪽에 번호를 남기고 적은 쪽을 옮긴다.** 커밋 태그는 못 고치므로 그쪽이 기준이다.
3. 옮기는 쪽은 파일명·frontmatter 의 `id:`·backlog 안 상호참조를 함께 고치고, 무엇을 왜 옮겼는지
   그 태스크 notes 에 남긴다(옛 번호를 가리키는 커밋 메시지가 남기 때문이다).
4. **먼저 `git fetch` 한다.** 리모트에 이미 상대가 해소한 결과가 있으면 자기 배정을 만들지 말고
   그것을 따른다 — 두 머신이 서로 모르고 각자 해소하면 이중 개명이 나고 되돌리는 커밋이 하나 더
   필요하다(2026-08-11 에 실제로 났다).

`backlog doctor --fix` 는 이 판정에 쓰지 않는다 — 참조 스캔이 `backlog/` 안 마크다운만 봐서
코드·커밋 태그에서 훨씬 많이 참조되는 쪽을 개명 대상으로 고르곤 한다.

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

## 전제

- backlog 가 유일한 백엔드다. repo 루트에 `backlog/`(또는 `backlog/config.yml`)가 있어야 한다.
- 없으면 새 저장소로 보고 `/init-backlog` 으로 초기화하도록 안내한다. 옛 `PLAN.md` 만 있는
  저장소는 `/migrate-to-backlog` 으로 먼저 전환한다 — 플랜 파일을 직접 진행하지 않는다.

## 상태 4종

| backlog | 뜻 |
|---|---|
| `To Do` | 아직 착수하지 않음 |
| `In Progress` | 진행 중 — 이어서 할 일로 최우선 |
| `Done` | 완료 |
| `Blocked` | 막힘. 사유는 태스크 notes 첫 줄 |

`Blocked` 는 terminal 이 아니다 — 나이가 많아도 완료로 취급하거나 정리 대상으로 옮기지 않는다.
막힘 사유가 해소된 것이 확인되면 `backlog task edit <id> -s "To Do"` 로 되돌린다.
