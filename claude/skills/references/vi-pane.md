# 옆 pane 에 vi 띄우기

herdr 안(`HERDR_ENV=1`)에서 문서를 사용자 옆 pane 의 vi 로 여는 공용 레시피다. 밖이면 경로만 알리고
이 절차는 건너뛴다. herdr 명령 자체의 함정은 `/herdr` 스킬이 정본이다.

```bash
VI_PANE=$(herdr pane split --current --direction right --cwd "$(pwd)" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"]["pane"]["pane_id"])')
herdr pane run "$VI_PANE" "vi '/abs/path/doc.md'"          # 편집용: 결과를 회수한다
herdr pane run "$VI_PANE" "vi -o '/abs/1.md' '/abs/2.md'; exit"  # 보기용: :q 로 pane 이 닫힌다
```

- **`--no-focus` 를 주지 않는다.** 사용자가 바로 보거나 고치라고 여는 pane 이다.
- **앵커는 `--current`.** `$HERDR_PANE_ID` 는 pane 이 옮겨지면 stale 이 된다.
- **경로는 절대경로.** pane 의 cwd 를 믿지 않는다. 열기 전에 파일이 있는지 본다 — 없는 경로는 vi 가
  빈 새 파일로 열어 "만든 문서"처럼 보인다.
- **pane id 를 기억해 두고, 쓰임이 끝나면 에이전트가 닫는다.** 게시·생성을 마쳤거나 취소했을 때
  `herdr pane close "$VI_PANE"`. 사용자가 이미 닫았으면(`pane_not_found`) 에러를 무시한다.
- **편집용과 보기용의 차이는 `; exit` 하나다.** 편집용은 회수 전에 pane 이 사라지면 안 되므로 붙이지
  않고, 보기용은 붙여서 사용자가 `:q` 하면 정리가 끝나게 한다.
