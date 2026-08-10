---
name: show-it-side
description: 이 세션에서 방금 만들거나 크게 고친 문서를 herdr 옆 pane 에 vi 로 열어 보여준다. "옆에 띄워줘 / 방금 만든 거 보여줘 / show it side" 라고 할 때. herdr 안(HERDR_ENV=1)에서만 동작한다.
argument-hint: "(선택) 열어 볼 파일 경로들 — 생략하면 이 세션에서 방금 만든 문서를 자동 선정"
---

방금 만든 산출물을 사용자가 경로를 복사해 여는 왕복 없이 옆 pane 의 vi 로 바로 보여준다.
읽기용 뷰어다 — 열어 주고 끝이며, 닫는 것은 사용자다(편집 승인 플로우가 아니다).

## 절차

1. **herdr 확인.** `HERDR_ENV` 가 `1` 이 아니면 pane 을 열 수 없다 — 파일 경로 목록만 보고하고 끝낸다.

2. **대상 선정.** 인자 경로가 있으면 그대로. 없으면 이 세션에서 방금 만들었거나 실질적으로 고친
   **문서**(md·텍스트·초안·리포트)를 최근 것부터 고른다. 코드 파일은 사용자가 명시했을 때만.
   대화에서 특정이 안 되면 추측으로 열지 말고 후보를 대며 묻는다(AskUserQuestion).
   열기 전에 파일 존재를 확인한다 — 없는 경로는 vi 가 빈 새 파일로 열어 "만든 문서"라는 인상을 준다.

3. **pane 하나에 vi 하나가 기본.** 파일이 여러 개여도 한 vi 에 모두 넘긴다: 2개는 `vi -o`(오른쪽
   pane 은 세로로 길어 `-O` 보다 낫다), 3개 이상은 `vi -p` 탭. pane 을 여러 개 여는 것은 사용자가
   "나란히 비교"를 명시했을 때만, 그때도 2개까지 — pane 이 늘수록 좁아져 문서가 안 읽힌다.

4. **스폰.** 사용자가 바로 볼 pane 이므로 `--no-focus` 를 주지 않는다. `; exit` 를 붙여 vi 를
   끝내면(`:q`) pane 이 스스로 닫히게 한다 — 별도 정리가 필요 없다.

   ```bash
   VIEW_PANE=$(herdr pane split --current --direction right --cwd "$(pwd)" \
     | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"]["pane"]["pane_id"])')
   herdr pane run "$VIEW_PANE" "vi -o '/abs/path/1.md' '/abs/path/2.md'; exit"
   ```

   경로는 절대경로로 넘긴다(pane 의 cwd 를 믿지 않는다). 앵커는 `--current` — `$HERDR_PANE_ID` 는
   pane 이동 시 stale(`/herdr` 스킬 첫 함정).

5. **보고.** 무엇을 어떤 배치(분할/탭)로 열었는지 한 줄로 알리고 끝낸다. 탭이면 `gt` 로 넘긴다고
   덧붙인다. pane 을 기다리거나 닫지 않는다.

## 유의

- 편집을 요청하고 결과를 회수하는 초안 플로우(draft-issue·scopic-pr 류)는 각 스킬 본문의 vi pane
  규칙을 따른다 — 그쪽은 승인 후 pane 을 에이전트가 닫는다.
