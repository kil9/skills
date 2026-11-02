# 옆 pane 에 vi 띄우기

herdr 안에서 문서를 사용자 옆 pane 의 vi 로 여는 공용 레시피다. herdr 는 둘이라 환경변수로 가른다 —
`HERDR_ENV=1` 이면 herdr TUI, `HERDR_ENV` 없이 `HC_TERMINAL_SOCKET` 만 있으면 Herdr 앱(herdr-core)이다.
둘 다 아니면 경로만 알리고 이 절차는 건너뛴다. herdr 명령 자체의 함정은 `/herdr` 스킬이 정본이다.

## herdr TUI (`HERDR_ENV=1`)

```bash
VI_PANE=$(herdr pane split --current --direction right --cwd "$(pwd)" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"]["pane"]["pane_id"])')
herdr pane run "$VI_PANE" "vi '/abs/path/doc.md'"          # 편집용: 결과를 회수한다
herdr pane run "$VI_PANE" "vi -o '/abs/1.md' '/abs/2.md'; exit"  # 보기용: :q 로 pane 이 닫힌다
```

- 닫기: `herdr pane close "$VI_PANE"`. 사용자가 이미 닫았으면(`pane_not_found`) 에러를 무시한다.
- **`--no-focus` 를 주지 않는다.** 사용자가 바로 보거나 고치라고 여는 pane 이다.
- **앵커는 `--current`.** `$HERDR_PANE_ID` 는 pane 이 옮겨지면 stale 이 된다.

## Herdr 앱 (`HC_TERMINAL_SOCKET`, `HERDR_ENV` 없음)

앱에는 pane 을 나누는 명령이 없다. `hc run` 으로 띄운 터미널에 내 탭의 `herdr.space`·`herdr.tab` 레이블을
붙이면 앱이 그 탭을 나눠 오른쪽 pane 으로 넣는다(2026-11-02 실측, hc 0.1.15).

```bash
SPACE=$(hc get "$HC_TERMINAL_ID" | jq -r '.labels["herdr.space"]')
TAB=$(hc get "$HC_TERMINAL_ID" | jq -r '.labels["herdr.tab"]')
ED=$(command -v nvim || command -v vi)
VI_PANE=$(hc run --bg --rm --no-notify --label herdr.space="$SPACE" --label herdr.tab="$TAB" --cwd "$(pwd)" \
  "sleep 1; '$ED' '/abs/path/doc.md'; exec \"\${SHELL:-sh}\" -i" | jq -r .address)  # 편집용: 결과를 회수한다
VI_PANE=$(hc run --bg --rm --no-notify --label herdr.space="$SPACE" --label herdr.tab="$TAB" --cwd "$(pwd)" \
  "sleep 1; '$ED' -o /abs/1.md /abs/2.md" | jq -r .address)                # 보기용: :q 로 pane 이 닫힌다
```

- 닫기: `hc kill "$VI_PANE"`. `--rm` 이라 앱에서 pane 도 빠진다. 이미 닫혔으면(`not_found`) 에러를 무시한다.
  `hc send "$VI_PANE" ":q"` 로 닫으려 하지 않는다 — send 는 붙여넣기라 `:q` 가 버퍼에 글자로 들어간다.
- **편집기를 `sleep 1` 뒤에 띄운다.** 앱이 pane 크기를 정하기 전에 뜬 nvim 은 크기를 잘못 잡아 줄과
  상태줄이 겹쳐 반복되는 깨진 화면이 되고, `ctrl+l` 로도 안 돌아온다(2026-11-02 실측, 두 번째 띄울 때 발생).
  확인은 `hc read <pane>` 에 본문 첫 줄이 보이는지로 한다. 화면에 비밀이 있으면 가려서 읽는다.
- **편집기는 `$ED` 절대경로로 넘긴다.** `hc run` 은 셸을 거치지 않아 `alias vi='nvim'`(kil9conf
  `rc/aliases`)이 먹지 않고 `/usr/bin/vi`(vim)가 뜬다. hc 터미널의 PATH 에는 `~/.local/bin` 도 없어
  이름만 `nvim` 으로 주면 `/usr/bin/nvim`(구버전)이 뜬다(2026-11-02 실측).
- **레이블이 `null` 이면 이 터미널은 앱 화면 밖이다.** 띄워도 어느 탭에도 안 보이니 경로만 알린다.
  레이블 없이 `hc run --bg vi` 만 하면 사용자는 그 vi 를 볼 방법이 없다.
- **`--rm` 을 뺀 채 띄우지 않는다.** 빼면 vi 가 끝난 뒤에도 끝난 터미널이 pane 을 차지한다.
- **`--no-notify` 를 뺀 채 띄우지 않는다.** 빼면 vi 가 끝날 때 hc 가 내 Claude 입력창에 알림을 친다.
- 띄운 터미널은 이 Claude 세션의 자식이라 세션이 끝나면 함께 닫힌다.

## 공통

- **경로는 절대경로.** pane 의 cwd 를 믿지 않는다. 열기 전에 파일이 있는지 본다 — 없는 경로는 vi 가
  빈 새 파일로 열어 "만든 문서"처럼 보인다.
- **`VI_PANE` 을 기억해 두고, 쓰임이 끝나면 에이전트가 닫는다.** 게시·생성을 마쳤거나 취소했을 때 위의
  '닫기'로 닫는다.
- **편집용은 vi 가 끝나도 pane 을 셸로 남긴다.** 회수 전에 pane 이 사라지면 안 되기 때문이다. TUI 는
  `; exit` 를 붙이지 않는 것으로, 앱은 `exec "${SHELL}" -i` 로 그렇게 한다. 보기용은 사용자가 `:q` 하면
  pane 까지 정리된다.
