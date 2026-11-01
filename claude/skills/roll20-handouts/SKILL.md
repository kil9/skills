---
name: roll20-handouts
description: 저장소의 핸드아웃 원본(마크다운)을 Roll20 게임의 핸드아웃으로 만들고 고친다(동기화). "롤20 핸드아웃 만들어줘 / 고쳐줘 / 올려줘 / 롤20에 반영해줘", 또는 롤20 핸드아웃 목록·본문을 읽어 와야 할 때.
---

# roll20-handouts

Claude in Chrome 으로 **로그인된 Roll20 게임 화면**을 열고, 페이지 컨텍스트에서 JS(`r20h.js`)를
실행해 핸드아웃을 만들고 고친다. 화면 클릭이 아니라 롤20 클라이언트 객체(`window.Campaign`)를
직접 쓰므로 수십 장도 한 번에 끝난다. 비공식 경로라 롤20 업데이트로 깨질 수 있다 — 깨지면
`R20H.ready()` 오류나 되읽기 불일치로 드러난다.

## 원본 디렉터리

```
<dir>/roll20.json   {"campaign_id": 12345678, "handouts": {"<key>": "<roll20 handout id>"}}
<dir>/<key>.md      핸드아웃 하나. 파일 이름(확장자 뺀 것)이 key
```

`<key>.md` 형식:

```markdown
---
name: 아드릭의 비밀
visible_to: gm            # gm | all | 플레이어 표시 이름을 쉼표로(예: 앨리스, 밥)
avatar: https://…         # 선택. 공개로 받을 수 있는 URL 이어야 한다
archived: false           # 선택
---
플레이어가 보는 본문(마크다운 → HTML)

<!-- gm -->
GM 메모(gmnotes). 이 줄이 없으면 GM 메모는 비운다
```

- 롤20 쪽 핸드아웃은 **`roll20.json` 의 id 로만** 짝짓는다. 롤20은 이름 중복이 흔해서(복제하면
  같은 이름이 생긴다) 이름으로 짝지으면 엉뚱한 것을 덮는다. id 가 없는 key 는 새로 만들되, 같은 이름이
  이미 있으면 만들지 않고 오류로 돌려준다 — 그때는 사용자에게 어느 것을 쓸지 물어 id 를 적는다.
- 게임 ID 는 게임 화면 URL(`/editor/setcampaign/<id>`)이나 페이지의 `window.campaign_id` 로 안다.

## 단계

1. **대상 확인** — 원본 디렉터리와 `roll20.json` 을 찾는다(없으면 만든다). 이번에 반영할 key 를 정한다.
   완료 기준: 반영할 `.md` 목록과 게임 ID 가 정해졌다.
2. **페이로드 생성** — `uv run ~/.claude/skills/roll20-handouts/r20h.py build <dir> [key ...]`.
   `<dir>/.r20h-payload.js` 가 생긴다(저장소에 커밋하지 않는다 — `.gitignore` 에 넣는다).
   완료 기준: 출력에 반영 대상 key 가 빠짐없이 나온다.
3. **공개 범위 확인** — 플레이어에게 새로 보이게 되는 핸드아웃(`visible_to` 가 gm 이 아니고, 신규이거나
   지금 롤20에서 GM 전용인 것)이 있으면 실행 전에 AskUserQuestion 으로 한 번 묻는다. 비밀 카드처럼
   남이 보면 안 되는 글이 엉뚱한 사람에게 열리는 사고를 막는다.
4. **실행** — Chrome 도구로:
   - `tabs_context_mcp(createIfEmpty: true)` → `navigate` 로 `https://app.roll20.net/editor/setcampaign/<게임 ID>`.
     사용자가 열어 둔 탭은 이 세션의 탭 그룹 밖이라 조작할 수 없다. 내 탭을 따로 열면 된다(같은 계정으로
     두 탭을 열어도 문제없었다).
   - `.r20h-payload.js` 내용을 그대로 `javascript_tool` 로 실행한다. 반환값이 upsert 결과 배열이다.
   - 결과를 스크래치패드에 JSON 으로 저장한다.
   완료 기준: 모든 key 의 action 이 `created`/`updated` 이거나, 오류가 있으면 그 이유를 알고 있다.
5. **기록** — `uv run …/r20h.py record <dir> <result.json>` 으로 새 id 를 `roll20.json` 에 적고,
   `roll20.json` 과 바뀐 `.md` 를 커밋한다. 다 쓴 탭은 닫는다.
   완료 기준: 신규 key 가 전부 `roll20.json` 에 id 로 들어가 커밋됐다.

## 읽기·삭제

- 읽기: `r20h.js` 를 실행한 뒤 `R20H.list()`(목록), `await R20H.read(id)`(본문·GM 메모, escape 해독),
  `R20H.players()`(플레이어 id·표시 이름).
- 삭제: 사용자가 그 핸드아웃을 지우라고 했을 때만, 이름과 id 를 보여 확인받은 뒤 `R20H.remove(id)` 하고
  `roll20.json` 에서도 뺀다. 원본 `.md` 를 지웠다고 롤20 쪽을 자동으로 지우지 않는다.

## 알아낸 것(2026-11-02 실측)

- **외부에서 부를 수 있는 API 가 없다.** HAR 을 떠 보면 핸드아웃 저장은 HTTP 요청으로 남지 않고 페이지
  로드 때 맺은 실시간 연결로 간다. Pro 의 Mod(API) 스크립트는 롤20 서버 샌드박스에서 돌고 외부 네트워크가
  막혀 저장소 데이터를 직접 못 가져간다. 그래서 이 경로를 쓴다.
- 핸드아웃 본문(`notes`·`gmnotes`)은 속성이 아니라 blob 이다. `h.get('notes')` 는 타임스탬프만 준다.
  쓰기는 `h.updateBlobs({notes, gmnotes})`, 읽기는 `h._getLatestBlob(field, cb)`. 이름·공개 범위는
  `h.save({...})`. 새로고침 뒤 되읽어 서버 반영을 확인했다.
- 롤20 편집기로 저장한 본문은 `escape()` 인코딩(`%3Cp%3E%uD55C…`)으로, 우리가 쓴 것은 평문 HTML 로
  남는다. 둘 다 화면에 정상으로 렌더링된다. `R20H.read` 가 해독해 준다.
- `inplayerjournals` 는 `''`(GM 만), `'all'`, 또는 플레이어 id 쉼표 목록이다.
- 이미지(`avatar`, 본문 `<img>`)는 플레이어 브라우저가 직접 받으므로 **공개 URL** 이어야 한다. private
  GitHub 저장소의 raw URL 은 안 보인다.
