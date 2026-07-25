# 업로드 흐름 (§9)

[`../SKILL.md`](../SKILL.md) 의 §9 다. **이슈 작성·코멘트 게시 요청이면 이 파일을 끝까지 읽고
그대로 수행한다** — 여기 담긴 draft → 승인 → 업로드 순서가 곧 승인 게이트이며, 건너뛰면
사용자 승인 없이 외부에 글이 올라간다.

## 9. 업로드 흐름 (draft → 승인 → 업로드)

### 9-1. 초안 파일 작성

§0~§8 의 kil9 스타일 원칙으로 본문을 완성하고 임시 파일에 저장한다 (`apply_patch` 또는 적절한 파일 편집 도구 사용). 경로는 `git rev-parse --git-dir` 결과 디렉터리 아래에 둔다(보통 `.git/`). git 저장소가 아니면 scratchpad 경로를 쓰고, 대상 repo 를 사용자에게 물어 §9-3 에서 `--repo owner/repo` 로 지정한다.

- **이슈 작성** → `ISSUE_DRAFT.md`. **파일 첫 라인은 `# {제목}` 형식의 H1 으로 둔다** — 이 라인이 이슈 title 로 쓰인다. 두 번째 라인은 빈 줄, 세 번째 라인부터 본문(`## 설명` 등)이 시작한다. 사용자는 같은 파일에서 title 과 본문을 동시에 수정할 수 있다.
- **코멘트 게시** → `COMMENT_DRAFT.md`. **title 라인 없이 파일 전체가 코멘트 본문이다.** 어느 이슈/PR 에 다는지 **대상(번호 또는 URL)** 을 먼저 확정한다 — 모르면 사용자에게 묻는다. 이슈 코멘트인지 PR 코멘트인지도 함께 확인한다(`gh issue comment` / `gh pr comment` 가 갈린다).

작성한 파일 경로를 사용자에게 알리고, 에디터로 직접 수정할 수 있게 안내한다(이슈는 title 도 첫 H1 라인에서 편집 가능). 본문 미리보기를 채팅에 다시 붙여 넣지 않는다 — 파일이 정본이다.

### 9-2. 사용자 확인 (request_user_input)

**request_user_input 도구로** 편집을 마쳤는지 확인한다. 질문 예: "`.git/ISSUE_DRAFT.md` 편집을 마치셨나요?" (코멘트면 `.git/COMMENT_DRAFT.md`).

선택지:
- **편집 완료** — 현재 파일 내용 그대로 업로드.
- **재생성** — 추가 수정 지시를 받아 같은 파일에 다시 작성하고 다시 §9-2 확인(승인될 때까지 반복).
- **취소** — 업로드 중단(이 경우에도 §9-4 임시 파일 정리는 수행).

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

### 9-4. 임시 파일 정리 및 보고

- 업로드 성공/취소 모두 해당 임시 파일을 삭제한다 (이슈: `rm -f "$gitdir/ISSUE_DRAFT.md" "$gitdir/ISSUE_BODY.md"`, 코멘트: `rm -f "$gitdir/COMMENT_DRAFT.md"`).
- 생성된 이슈/코멘트 URL 을 사용자에게 알린다.
