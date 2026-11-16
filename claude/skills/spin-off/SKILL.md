---
name: spin-off
description: 지금 세션의 일과 별개인 작업을 Herdr 의 새 claude 세션(`ca`)으로 떼어 내, 사용자가 그 세션에서 직접 이어 가게 한다. 대상 저장소의 space 에 탭을 붙이고, 그런 space 가 없으면 새로 만든다. "새 탭 열어서 ca로 / 따로 시작해 / 새 세션으로 넘겨" 라고 할 때. 결과를 돌려받는 위임(Agent·pane 워커)이 아니다. 사용자가 프롬프트에 `/spin-off` 를 적었거나 직접 요청했을 때 부른다. 자율 호출은 삼간다.
argument-hint: "(선택) 넘길 작업 설명 — 생략하면 직전 대화에서 넘기라고 한 일"
---

넘기는 일은 **handoff** 다: 새 세션은 이 대화를 모르고, 끝나도 이 세션으로 보고하지 않는다. 사용자가
그 탭으로 가서 이어 간다. 그래서 프롬프트 파일 하나가 새 세션이 가진 맥락의 전부다.

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

4. **세션 이름 정하기.** 묻지 않고 넘기는 일을 드러내는 짧은 영문 kebab-case(`[A-Za-z0-9._-]`, 예: `bruno-course`)
   로 정해 `claude -n` 으로 넘긴다 — 탭·사이드바·ListAgents 에 처음부터 그 이름이 뜬다. 대가로 그 세션은 작업 요약을
   제목으로 내보내지 않아 탭 이름이 자동으로 바뀌지 않는다(kil9conf task-518). 사용자가 2026-11-16 이 교환을 골랐다.

5. **띄우기.**
   - **앱**: `~/.claude/skills/spin-off/spin-off-app.sh <repo> <prompt file> <name>`. 출력 JSON 의 `app` 이
     `claude-code` 면 성공(exit 0). `trust-prompt` 면 처음 보는 folder 의 신뢰 확인에서 멈춘 것 — 기본 선택이
     "No, exit" 라 대신 누르지 말고 사용자에게 그 탭에서 고르라고 알린다. `none` 이면 `hc read <terminal> --lines 40`
     으로 화면을 보고 원인을 보고한다.
   - **TUI**: 아래 'TUI 경로'.

6. **보고.** 세션 이름, 터미널 주소, space 이름(새로 만들었으면 그렇다고), 탭, 프롬프트 파일 경로를 한 줄씩. 포커스는
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
- 탭 이름은 앱이 claude 세션 제목으로 덮어쓴다. 띄운 지 몇 초 안에 `hc get` 의 `.status.app = claude-code` 가 뜬다.

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
```

확인은 `herdr agent list` 에 그 pane 이 claude 로 잡히는지. 새 pane 의 셸이 rc 를 읽는 중이면 `pane run` 이 먹힐지
불확실하다 — 화면(`herdr pane read <pane> --source visible`)으로 확인한다.
