---
name: spin-off
description: 지금 세션의 일과 별개인 작업을 Herdr 의 새 claude 세션(`ca`)으로 떼어 내, 사용자가 그 세션에서 직접 이어 가게 한다. 대상 저장소의 space 에 탭을 붙이고, 그런 space 가 없으면 새로 만든다. "새 탭 열어서 ca로 / 따로 시작해 / 새 세션으로 넘겨" 라고 할 때, 그리고 `/spin-off m-20` 처럼 backlog id 를 넘겨 그 태스크를 새 세션의 /sb 로 돌리게 할 때. 결과를 돌려받는 위임(Agent·pane 워커)이 아니다. 사용자가 프롬프트에 `/spin-off` 를 적었거나 직접 요청했을 때 부른다. 자율 호출은 삼간다.
argument-hint: "(선택) 넘길 작업 설명 | backlog id(m-20, task-12) | 슬래시 명령(/grill ...) — 생략하면 직전 대화에서 넘기라고 한 일"
---

넘기는 일은 **handoff** 다: 새 세션은 이 대화를 모르고, 끝나도 이 세션으로 보고하지 않는다. 사용자가
그 탭으로 가서 이어 간다. 그래서 프롬프트 파일 하나가 새 세션이 가진 맥락의 전부다.

## 인자 모드

| 인자 | 모드 | 새 세션의 첫 프롬프트 |
|---|---|---|
| 없음·작업 설명 | 일반 | 프롬프트 파일(절차 3) |
| `m-N`·`task-N`(`TASK-N`, 쉼표 목록 포함)만 | **backlog** | `/sb <id>` 한 줄 |
| `/` 로 시작 | 명령 전달 | 그 문자열 그대로(예: `/grill ...`) |

backlog 모드에서는 프롬프트 파일이 맥락을 담지 않는다 — **태스크 파일이 정본**이고, 이 대화에서 알게 된 것은
태스크 notes 로 옮긴다(아래 절). 명령 전달 모드는 절차 3 을 건너뛰고 그 문자열을 그대로 프롬프트 파일에 쓴다.
첫 프롬프트의 슬래시 명령은 새 세션에서 스킬로 확장된다(2026-11-25 실측, `claude -p "/show-qr hello"` 가 첫 턴에
Skill 호출 없이 스킬 본문을 따랐다). 단 **Git Bash 에서 인자로 직접 넘기면** MSYS 가 `/show-qr` 를
`C:/Program Files/Git/show-qr` 로 바꾼다 — 앱 경로는 pwsh 가 파일에서 읽어 넘기므로 해당 없지만, 시험할 때는
`MSYS_NO_PATHCONV=1` 을 붙인다.

## backlog 모드

절차 1·2·5·6 은 그대로이고, 3·4 를 아래로 바꾼다.

1. **어느 backlog 의 id 인가.** cwd 의 backlog 를 먼저 본다(`backlog milestone list --plain` / `backlog task view <id> --plain`).
   거기 없거나 대화상 다른 저장소의 일이면 그 저장소에서 찾고, 둘 이상에서 보이면 AskUserQuestion 으로 묻는다.
   그 backlog 가 있는 저장소가 대상 저장소다(절차 2 를 갈음).
2. **인계 기록 — 범위를 그 id 로 좁힌 wrap.** 이 대화에서 그 태스크(마일스톤이면 소속 태스크)에 관련해 알게 된 것 —
   실측·에러 원문, 반박된 가설, 사용자 결정과 근거, 이미 해 둔 부분 — 을 해당 태스크 notes 에 `backlog task edit <id> --append-notes "…"` 로 덧붙인다(`--notes` 는 덮어쓴다). 판정 기준은
   `/wrap` §2 와 같고(`Skill("wrap", args: "<id> 관련만, 목적지는 <id> 태스크 notes")` 로 불러도 된다), 세션 전체 wrap 은
   하지 않는다 — 이 세션은 계속 일한다. 태스크 파일만으로 이미 이어 갈 수 있으면 건너뛴다. 대화에서 처음 나온 일이라
   태스크가 아직 없다면 backlog 모드가 아니다 — 먼저 `/add-backlog` 를 권한다.
3. **선점.** 대상 태스크를 `backlog task edit <id> -s "In Progress" -a @<세션 이름>` 으로 잡아 둔다(마일스톤이면 하지
   않는다 — /sb 가 고른다). 지금 세션이나 옆 세션이 같은 태스크를 다시 잡는 것을 막는다(kil9conf doc-29 §14).
4. **커밋·push.** 2·3 의 변경을 그 저장소에 `[<task id>]` 태그로 커밋하고 push 한다. 새 세션이 worktree 로 갈라져도
   리모트에서 보게 하려는 것이다.
5. **세션 이름**은 id 와 태스크(마일스톤) 제목에서 짓는다(예: `m20-ghub-sync`, `t636-spin-off-sb`).
6. **프롬프트 파일**에는 `/sb <id>` 한 줄만 쓴다(경로 규칙은 절차 3 과 같다). 그다음 절차 5 로 띄운다.

보고(절차 6)에 인계 기록을 남겼는지·건너뛰었는지와 선점한 태스크를 한 줄 덧붙인다.

## 절차

1. **환경 판정.** `HC_TERMINAL_SOCKET` 이 있고 `HERDR_ENV` 가 없으면 Herdr 앱 경로(기본), `HERDR_ENV=1` 이면
   TUI 경로, 둘 다 아니면 "Herdr 안이 아니라 새 세션을 띄울 수 없다"고 알리고 프롬프트 파일만 써 준 뒤 멈춘다.

2. **대상 저장소 정하기.** 그 작업이 손댈 저장소(폴더)를 대화에서 정한다. 지금 세션의 cwd 가 기본값이 아니다
   — 넘기는 일은 대개 다른 저장소다. 둘 이상이 그럴듯하거나 하나도 안 보이면 AskUserQuestion 으로 묻는다.
   완료 기준: 실재하는 디렉터리 절대경로 하나.

3. **프롬프트 파일 쓰기.** `~/.cache/spin-off/<YYYYMMDD-HHMM>-<slug>.md` 에 쓴다 — 세션 scratchpad(`/tmp/claude-…`)는
   재부팅 때 지워져 새 세션이 다시 읽을 수 없다. 이 대화 없이 읽혀도 되게 다음을 담는다:
   - 무슨 일인가(한두 문장), 근거가 된 증상·관찰(실제 에러 문구·명령 출력·URL 그대로),
   - 대상 경로, 할 일과 완료 조건, 이 세션에서 이미 확인했거나 배제한 것.
   "위에서 말한", "아까 그" 처럼 이 대화를 가리키는 말이 남아 있으면 미완료다.

4. **이름 둘 정하기.** 묻지 않고 정한다.
   - **탭 제목**: 사용자가 사이드바에서 보는 이름. 넘기는 일을 한국어로 요약한 한 구(15자 안팎, 예: `s2z 대시보드 한국어 다듬기`,
     `m25 1차 16개 시험`). kebab-case 영문 slug 를 그대로 보여 주지 않는다(사용자 지적 2026-11-26).
   - **세션 이름**: `claude -n` 으로 넘기는 영문 kebab-case(`[A-Za-z0-9._-]`, 예: `dash-korean-polish`). ListAgents·SendMessage
     주소로 쓰인다. `-n` 을 주면 그 세션은 작업 요약을 제목으로 내보내지 않아(kil9conf task-518) 앱이 탭에 이 slug 를 띄우므로,
     스크립트가 claude 가 뜬 뒤 탭 이름을 탭 제목으로 덮어쓴다.

5. **띄우기.**
   - **앱**: `~/.claude/skills/spin-off/spin-off-app.sh <repo> <prompt file> <name> '<탭 제목>'`. 출력 JSON 의 `app` 이
     `claude-code` 이고 `tab_name` 이 탭 제목이면 성공(exit 0). `trust-prompt` 면 처음 보는 folder 의 신뢰 확인에서 멈춘 것 — 기본 선택이
     "No, exit" 라 대신 누르지 말고 사용자에게 그 탭에서 고르라고 알린다. `none` 이면 `hc read <terminal> --lines 40`
     으로 화면을 보고 원인을 보고한다.
   - **TUI**: 아래 'TUI 경로'.

6. **보고.** 탭 제목, 세션 이름, 터미널 주소, space 이름(새로 만들었으면 그렇다고), 탭, 프롬프트 파일 경로를 한 줄씩. 포커스는
   옮기지 않았으니 사용자가 그 space·탭으로 직접 가야 한다고 덧붙인다. 띄운 세션을 닫는 것은 사용자 몫이다.

## 앱 경로의 근거 (스크립트가 하는 일)

`spin-off-app.sh` 가 정본이다. 바꿀 때 지켜야 할 실측(2026-11-16, hc 0.1.17, 이 머신):

- space 는 레이아웃 문서(`herdr-app` doc, `hc connect` 로 `doc.get`)의 `spaces[].folder` 로 찾는다. **양쪽을
  realpath 로 비교한다** — `~/work/kil9/ha.kil9.dev` 는 `home.kil9.dev` 의 심링크라, 그 경로로 띄운 세션 상태줄에
  `home.kil9.dev` 가 뜬 것은 cwd 오류가 아니었다.
- 처음 보는 `herdr.space`/`herdr.tab` label 로 `hc run` 하면 앱이 space·탭을 만든다. 새 space 의 `folder` 는 그
  터미널 cwd 로 채워지지만 `name` 은 빈 문자열로 남아 `doc.set` 으로 채운다(버전 충돌이면 다시 읽어 재시도).
  label 로 만든 space·탭은 포커스를 가져가지 않는다.
- `hc run` 은 호출자 환경이 아니라 core 의 환경을 준다: `ca` 는 login zsh 의 alias(`cld auto`)라
  `env K9_RUN='ca "$(< file)"' zsh -l` 로 띄우고, `CLAUDE_CONFIG_DIR`(ccs 프로필)를 env 로 직접 싣는다. `HC_TERMINAL_ID`·
  `HC_SCOPE` 를 빼고 `--no-parent` — 안 그러면 이 세션이 끝날 때 같이 죽는다.
- **Windows core**(Git Bash 에서 호출)에는 `env`·`zsh` 가 없어 위 형태가 `spawn_failed: env: not found on PATH` 로
  죽는다. 앱이 직접 띄운 세션과 같은 꼴 `pwsh -NoLogo -NoExit -Command "$env:CLAUDE_CONFIG_DIR='…'; claude -n <name>
  (Get-Content -Raw '<prompt>')"` 로 띄우고, 레이아웃 문서의 folder(`D:\work\x`)는 `cygpath -u` 로 바꿔 비교한다(2026-11-16).
- 탭 이름은 앱이 claude 세션 제목으로 덮어쓴다. 띄운 지 몇 초 안에 `hc get` 의 `.status.app = claude-code` 가 뜬다.
  그 뒤 `doc.set` 으로 `spaces[].tabs[].name` 을 바꾸면 세션이 일하는 중에도 유지된다(2026-11-26 실측). 스크립트는
  덮인 경우를 대비해 2초 간격으로 세 번 확인한다.

## TUI 경로 (실측 안 됨)

이 머신은 앱만 쓰고 있어 아래는 `herdr --help`·herdr 스킬의 명령 형태로 조립만 했다. 처음 쓸 때 결과를 확인해
이 절을 고친다.

```sh
# 대상 workspace: herdr api snapshot 에서 cwd(realpath)가 <repo> 인 workspace id. 없으면
#   herdr workspace create --cwd <repo> --label <repo 이름> --no-focus  → .result.workspace / .result.root_pane
out=$(herdr tab create --workspace <wid> --cwd <repo> --no-focus \
  ${CLAUDE_CONFIG_DIR:+--env "CLAUDE_CONFIG_DIR=$CLAUDE_CONFIG_DIR"})
pane=$(jq -r '.result.root_pane.pane_id' <<<"$out")
herdr pane run "$pane" 'ca -n <name> "$(< <prompt file>)"'     # 쌍따옴표째 넘겨 pane 의 zsh 가 펼치게 한다
herdr tab rename <tab id> '<탭 제목>'                            # 명령 형태 미확인 — herdr tab --help 로 확인
```

확인은 `herdr agent list` 에 그 pane 이 claude 로 잡히는지. 새 pane 의 셸이 rc 를 읽는 중이면 `pane run` 이 먹힐지
불확실하다 — 화면(`herdr pane read <pane> --source visible`)으로 확인한다.
