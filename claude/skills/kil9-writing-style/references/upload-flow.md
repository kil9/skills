# 초안 파일 · 업로드 흐름 (§9)

[`../SKILL.md`](../SKILL.md) 의 §9 다. **초안 파일을 만들기 전에 이 파일을 끝까지 읽고 그대로
수행한다.** §9-1 은 게시하지 않는 글에도 적용되고, 게시 요청이면 여기 담긴 draft → 승인 →
업로드 순서가 곧 승인 게이트여서 건너뛰면 사용자 승인 없이 외부에 글이 올라간다.

## 9. 초안 파일 · 업로드 흐름 (draft → 승인 → 업로드)

### 9-1. 초안 파일 작성 (게시 여부와 무관하게 항상)

§0~§8 의 kil9 스타일 원칙으로 본문을 완성하고 임시 파일에 저장한다 (Write 도구 사용). 경로는 `git rev-parse --git-dir` 결과 디렉터리 아래에 둔다(보통 `.git/`). git 저장소가 아니면 scratchpad 경로를 쓰고, 대상 repo 를 사용자에게 물어 §9-3 에서 `--repo owner/repo` 로 지정한다.

- **이슈 작성** → `ISSUE_DRAFT.md`. **파일 첫 라인은 `# {제목}` 형식의 H1 으로 둔다** — 이 라인이 이슈 title 로 쓰인다. 두 번째 라인은 빈 줄, 세 번째 라인부터 본문(`## 설명` 등)이 시작한다. 사용자는 같은 파일에서 title 과 본문을 동시에 수정할 수 있다.
- **코멘트 게시** → `COMMENT_DRAFT.md`. **title 라인 없이 파일 전체가 코멘트 본문이다.** 어느 이슈/PR 에 다는지 **대상(번호 또는 URL)** 을 먼저 확정한다 — 모르면 사용자에게 묻는다. 이슈 코멘트인지 PR 코멘트인지도 함께 확인한다(`gh issue comment` / `gh pr comment` 가 갈린다).
- **PR 본문** → `PR_DRAFT.md`, 그 밖의 글 → `WRITING_DRAFT.md`. 게시하지 않으므로 §9-2 확인과 §9-3 업로드는 건너뛰고, §9-4 의 편집 회수(§10)로 간다.

저장 직후 **원본 스냅샷을 뜬다** — `cp "{초안}" "{초안}.orig"`. §10 에서 사용자가 무엇을 고쳤는지 이 파일과 diff 로 뽑는다.

작성한 파일 경로를 사용자에게 알리고, 에디터로 직접 수정할 수 있게 안내한다(이슈는 title 도 첫 H1 라인에서 편집 가능). 본문 미리보기를 채팅에 다시 붙여 넣지 않는다 — 파일이 정본이다.

**herdr 안이면(`HERDR_ENV=1`) 경로 안내에 그치지 말고 옆 pane 에 vi 를 바로 열어 준다**(밖이면 생략):

```bash
VI_PANE=$(herdr pane split --current --direction right --cwd "$(pwd)" \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"]["pane"]["pane_id"])')
herdr pane run "$VI_PANE" "vi '{초안 절대경로}'"
```

일부러 `--no-focus` 를 주지 않는다 — 사용자가 바로 편집하라고 여는 pane 이다. §9-4 정리 때(업로드·취소 모두) `herdr pane close "$VI_PANE"` 로 닫는다(사용자가 이미 닫았으면 에러 무시).

### 9-2. 사용자 확인 (AskUserQuestion)

**AskUserQuestion 도구로** 편집을 마쳤는지 확인한다. 질문 예: "`.git/ISSUE_DRAFT.md` 편집을 마치셨나요?" (코멘트면 `.git/COMMENT_DRAFT.md`).

선택지:
- **편집 완료** — 현재 파일 내용 그대로 업로드.
- **재생성** — 추가 수정 지시를 받아 같은 파일에 다시 작성하고 다시 §9-2 확인(승인될 때까지 반복). 이때 `.orig` 스냅샷도 새 초안으로 다시 뜬다 — 내가 다시 쓴 것은 사용자 수정이 아니다.
- **취소** — 업로드 중단(이 경우에도 §9-4 편집 회수·임시 파일 정리는 수행).

게시하지 않는 글(PR 본문 등)도 같은 질문을 한 번 한다 — 업로드가 아니라 §10 편집 회수의 시작 신호다. 선택지는 **편집 완료** / **재생성** 두 개면 된다.

### 9-3. 업로드

§9-2 에서 "편집 완료" 승인을 받은 뒤에만 실행한다. **파일의 현재 내용을 정본으로 사용한다** — 직전에 메모리에 들고 있던 본문이 아니라 사용자가 마지막으로 편집한 파일 내용을 올린다.

**이슈 작성:**
```bash
gitdir=$(git rev-parse --git-dir)
title=$(awk 'NR==1 {sub(/^# /,""); print; exit}' "$gitdir/ISSUE_DRAFT.md")
awk 'NR==1{next} NR==2 && /^$/{next} {print}' "$gitdir/ISSUE_DRAFT.md" > "$gitdir/ISSUE_BODY.md"
gh issue create --title "$title" --body-file "$gitdir/ISSUE_BODY.md"
```
- 첫 H1 라인이 비어 있거나 형식이 어긋나면 업로드하지 말고 사용자에게 보고 후 재생성을 권한다.
- 라벨·담당자는 **사용자가 명시한 경우에만** `--label` / `--assignee` 로 추가한다.

**코멘트 게시** (`<대상>` 은 이슈/PR 번호 또는 URL):
```bash
gitdir=$(git rev-parse --git-dir)
gh issue comment <대상> --body-file "$gitdir/COMMENT_DRAFT.md"   # 이슈 코멘트
gh pr comment   <대상> --body-file "$gitdir/COMMENT_DRAFT.md"    # PR 코멘트
```

- 두 경우 모두 외부 저장소면 `--repo owner/repo` 를 붙인다.

### 9-4. 편집 회수 · 임시 파일 정리 및 보고

- **지우기 전에 `diff -u "{초안}.orig" "{초안}"` 을 먼저 뜬다** — 이 diff 가 SKILL.md §10 의 입력이다. 파일을 지우고 나면 사용자가 뭘 고쳤는지 되찾을 수 없으니 순서를 지킨다.
- 그 다음 임시 파일을 삭제한다 (이슈: `rm -f "$gitdir/ISSUE_DRAFT.md" "$gitdir/ISSUE_DRAFT.md.orig" "$gitdir/ISSUE_BODY.md"`, 코멘트: `rm -f "$gitdir/COMMENT_DRAFT.md" "$gitdir/COMMENT_DRAFT.md.orig"`). 업로드 성공·취소 모두 수행한다.
- 게시하지 않는 글(`PR_DRAFT.md` 등)은 **초안 본체를 지우지 않는다** — 사용자가 그 파일을 그대로 쓴다. `.orig` 스냅샷만 지운다.
- vi pane 을 열었으면 `herdr pane close "$VI_PANE"` (이미 닫혔으면 에러 무시).
- 생성된 이슈/코멘트 URL 을 사용자에게 알린다.
- 마지막으로 SKILL.md §10 을 수행한다(diff 가 비었으면 생략).
