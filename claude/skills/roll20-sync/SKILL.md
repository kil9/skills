---
name: roll20-sync
description: 저장소의 마크다운 원본을 Roll20 게임의 핸드아웃·캐릭터(소개·GM 메모·시트 값·반복 줄)·맵 페이지(맵 그림·토큰·시트 연결)로 만들고 고친다(동기화). "롤20 핸드아웃/캐릭터/맵 만들어줘 / 토큰 놓아줘 / 고쳐줘 / 롤20에 반영해줘", 또는 롤20 쪽 내용을 읽어 와야 할 때.
---

# roll20-sync

Claude in Chrome 으로 **로그인된 Roll20 게임 화면**을 열고, 페이지 컨텍스트에서 JS(`r20h.js`)를
실행해 핸드아웃과 캐릭터를 만들고 고친다. 화면 클릭이 아니라 롤20 클라이언트 객체(`window.Campaign`)를
직접 쓰므로 수십 개도 한 번에 끝난다. 비공식 경로라 롤20 업데이트로 깨질 수 있다. 깨지면
`R20H.ready()` 오류나 되읽기 불일치로 드러난다.

## 원본 디렉터리

```
<dir>/roll20.json          {"campaign_id": 12345678, "handouts": {"<key>": "<id>"}, "characters": {"<key>": "<id>"}}
<dir>/handouts/<key>.md    핸드아웃 하나. 파일 이름(확장자 뺀 것)이 key
<dir>/characters/<key>.md  캐릭터 하나
<dir>/pages/<key>.md       맵 페이지 하나(아래 '페이지')
```

frontmatter 는 YAML 이다. 본문은 마크다운이고 HTML 로 바뀌어 핸드아웃 `notes`, 캐릭터 `bio` 가 된다.
`<!-- gm -->` 줄 아래는 GM 메모(`gmnotes`)다. 이 줄이 없으면 GM 메모는 비운다.

```markdown
---
name: 아드릭
visible_to: all              # gm | all | [플레이어 표시 이름, …]  — 저널에서 보이는 사람
controlled_by: [앨리스]      # 캐릭터만. 같은 형식 — 시트를 고칠 수 있는 사람
avatar: ../../assets/x.jpg   # 선택. 이 파일 기준 상대 경로(아래 '그림') 또는 공개 URL
token: auto                  # 선택. 캐릭터만. 토큰 그림(아래 '토큰 그림'). 없으면 avatar 를 쓴다
archived: false              # 선택
sheet:                       # 캐릭터만. 시트 속성 이름: 값
  alias: 그림자
  heritage: 아크로스
  hunt: 2
  repeating_ability:         # 반복 섹션: 줄마다 필드 맵, name 필드로 짝짓는다
    - name: 특수능력 이름
      description: 설명
---
소개(bio) 본문

<!-- gm -->
GM 메모
```

- 롤20 쪽 대상은 **`roll20.json` 의 id 로만** 짝짓는다. 롤20은 이름 중복이 흔해서(복제하면 같은 이름이
  생긴다) 이름으로 짝지으면 엉뚱한 것을 덮는다. id 가 없는 key 는 새로 만들되, 같은 이름이 이미 있으면
  만들지 않고 오류로 돌려준다. 그때는 사용자에게 어느 것을 쓸지 물어 id 를 적는다.
- `sheet` 에 적은 속성만 덮어쓴다. 적지 않은 속성(스트레스·XP·물품 체크처럼 플레이 중에 바뀌는 값)은
  건드리지 않는다. 플레이 중에 바뀌는 값을 `sheet` 에 적으면 동기화할 때마다 원본 값으로 되돌아간다.
- 반복 줄은 같은 섹션 안에서 `name` 필드가 같은 줄을 고치고, 없으면 새로 만든다. 원본에 없는 줄은 지우지
  않는다. 줄 이름을 바꾸면 새 줄이 생기고 옛 줄은 남는다.
- 시트 속성 이름은 시트마다 다르다. 모르면 기존 캐릭터를 `R20H.read(id, 'character')` 로 읽어
  `attribs` 의 키를 본다.
- 게임 ID 는 게임 화면 URL(`/editor/setcampaign/<id>`)이나 페이지의 `window.campaign_id` 로 안다.

## 페이지

```markdown
---
name: 하틀리 연구소 정문
width: 20                    # 칸 수(1칸 = 70px)
height: 15
showgrid: true
map: ../../assets/x.jpg      # 페이지 전체를 덮는 맵 레이어 그림
tokens:
  - character: seresi-sample # characters/ 의 key. 먼저 반영돼 roll20.json 에 id 가 있어야 한다
    at: [5, 5]               # 왼쪽 위 칸 좌표(0부터)
    size: 1                  # 칸 수, 기본 1
    bar1: stress             # 선택. 막대 1에 연결할 시트 속성
    bar1_max: 9
  - name: 리피터              # 캐릭터 없는 소품은 name 과 image 가 필요하다
    image: ../../assets/y.jpg
    at: [12, 6]
    size: 2
    layer: gmlayer           # objects(기본) | gmlayer | map
---
```

- 캐릭터 토큰 그림은 토큰의 `image` → 캐릭터의 `token` → 캐릭터의 `avatar` 순으로 고른다. 토큰은 `represents` 로 캐릭터와 이어지고 이름이 보인다.
- 캐릭터 토큰은 반영할 때마다 캐릭터의 기본 토큰(저널에서 끌어다 놓을 때 쓰이는 것)으로도 저장한다. 그래서 토큰 그림을 바꾸면 기본 토큰도 따라 바뀐다.
- **위치는 처음 놓을 때만 쓴다.** 플레이 중에 옮긴 토큰을 동기화가 되돌리지 않는다. 그림·크기·레이어·연결은 매번 맞춘다.
- `roll20.json` 의 `pages` 는 `{key: {"id": 페이지 id, "graphics": {map | 캐릭터 key | 소품 name: 그래픽 id}}}` 다.
  원본에서 토큰을 빼도 롤20 쪽 토큰은 지우지 않는다.
- 페이지 그래픽은 그 페이지를 GM 화면에 띄워야 불러와진다. `upsertPages` 가 GM 화면만 옮겼다가 원래 페이지로 돌아온다.
  플레이어 리본(`playerpageid`, 플레이어가 보는 페이지)은 바꾸지 않는다 — 플레이어를 옮기는 일은 사용자가 할 때만 한다.

## 그림

`avatar` 나 본문의 `![](경로)` 에 저장소 안 그림 경로를 적으면, `build` 가 그 파일을 공개 그림 저장소에 내용 해시 이름
(`i/<sha256 앞 20자>.jpg`)으로 넣고 커밋·push 한 뒤 공개 주소가 열릴 때까지 기다렸다가 그 주소로 바꿔 넣는다.
같은 그림은 같은 주소, 그림을 고치면 새 주소가 된다. 설정은 `roll20.json` 의
`"assets": {"dir": "<그림 저장소 로컬 클론>", "base_url": "<공개 주소>"}`. 플레이어 브라우저가 그림을 직접 받으므로
private 저장소 주소는 못 쓴다. 공개 저장소에 올라간 그림은 누구나 볼 수 있다 — 공개되면 안 되는 그림(공개 전
비밀 카드)은 공개할 때 원본에 넣는다.

## 토큰 그림

롤20 캐릭터는 아바타(초상)와 기본 토큰 그림을 따로 가진다. 캐릭터 frontmatter 의 `token` 으로 토큰 그림만 따로 정한다.

- `token: <경로 또는 URL>` — 그 그림을 쓴다(`avatar` 와 같은 규칙).
- `token: auto` — `build` 가 `avatar` 에서 얼굴을 찾아 원형 토큰(투명 배경 PNG, 금색 테두리)을 만들어 쓴다.
  `auto-square` 는 테두리 없는 정사각형 크롭(JPG 품질 90). 원형은 투명 배경이 있어야 해서 PNG 다. 결과는 `~/.cache/roll20-sync/tokens/` 에 생기는 파생물이라
  저장소에 넣지 않는다. 초상을 고치면 다음 `build` 가 다시 만든다.
- 직접 만들어 보기: `uv run ~/.claude/skills/roll20-sync/make_token.py <초상...> --out <디렉터리>`
  (`--style square|round|both`, `--zoom` 토큰 한 변/얼굴 너비, 기본 1.9).

`make_token.py` 가 하는 일: 일러스트용 얼굴 검출기(lbpcascade_animeface)로 먼저 찾고, 못 찾으면 YuNet, 둘 다
못 찾으면 위쪽 가운데를 쓴다. 얼굴 중심 정사각형을 잘라 축소만 하므로 종횡비가 깨지지 않는다. 검출 모델은
`~/.cache/token-face/` 에 받아 둔다. 그림체 초상 7장(2026-11-02)에서 두 검출기를 합쳐 모두 얼굴을 잡았다 —
실사풍은 YuNet, 일러스트풍은 일러스트 검출기 쪽이 잡는 경향이었다. 일러스트 검출기 박스는 머리카락까지 잡아
더 커서 같은 `--zoom` 에서 조금 덜 당겨진다. **OpenCV 5 에는 `CascadeClassifier` 가 없어** 4.x 로 고정했다.

## 단계

1. **대상 확인** — 원본 디렉터리와 `roll20.json` 을 찾는다(없으면 만든다). 이번에 반영할 key 를 정한다.
   완료 기준: 반영할 `.md` 목록과 게임 ID 가 정해졌다.
2. **페이로드 생성** — `uv run ~/.claude/skills/roll20-sync/r20h.py build <dir> [key ...]`.
   `<dir>/.r20h-payload.js` 가 생긴다. 저장소에 커밋하지 않도록 `.gitignore` 에 넣는다.
   완료 기준: 출력에 반영 대상이 빠짐없이 나온다.
3. **공개 범위 확인** — 플레이어에게 새로 보이게 되거나 조종권이 넘어가는 것(`visible_to`·`controlled_by`
   가 gm 이 아니고, 신규이거나 지금 롤20에서 GM 전용인 것)이 있으면 실행 전에 AskUserQuestion 으로 한 번
   묻는다. 비밀 카드처럼 남이 보면 안 되는 글이 엉뚱한 사람에게 열리는 사고를 막는다.
4. **실행** — Chrome 도구로:
   - `navigate` 로 `https://app.roll20.net/editor/setcampaign/<게임 ID>` 를 연다(탭 그룹이 없으면 만들어 준다).
     사용자가 열어 둔 탭은 이 세션의 탭 그룹 밖이라 조작할 수 없다. 내 탭을 따로 열면 된다(같은 계정으로
     두 탭을 열어도 문제없었다).
   - `.r20h-payload.js` 내용을 그대로 `javascript_tool` 로 실행한다. 반환값은
     `{handouts: [...], characters: [...], pages: [...]}` 결과다.
   - 결과를 스크래치패드에 JSON 으로 저장한다.
   완료 기준: 모든 key 의 action 이 `created`/`updated` 이거나, 오류가 있으면 그 이유를 알고 있다.
5. **기록** — `uv run …/r20h.py record <dir> <result.json>` 으로 새 id 를 `roll20.json` 에 적고,
   `roll20.json` 과 바뀐 `.md` 를 커밋한다. 다 쓴 탭은 닫는다.
   완료 기준: 신규 key 가 전부 `roll20.json` 에 id 로 들어가 커밋됐다.

## 읽기·삭제

- 읽기: `r20h.js` 를 실행한 뒤 `R20H.list(kind)`(목록), `await R20H.read(id, kind)`(본문·GM 메모 해독,
  캐릭터는 `attribs` 까지), `R20H.players()`(플레이어 id·표시 이름). `kind` 는 `'handout'`(기본) 또는
  `'character'`.
- 삭제: 사용자가 그 대상을 지우라고 했을 때만, 이름과 id 를 보여 확인받은 뒤 `R20H.remove(id, kind)` 하고
  `roll20.json` 에서도 뺀다. 원본 `.md` 를 지웠다고 롤20 쪽을 자동으로 지우지 않는다.

## 알아낸 것(2026-11-02 실측)

- **외부에서 부를 수 있는 API 가 없다.** HAR 을 떠 보면 저장은 HTTP 요청으로 남지 않고 페이지 로드 때 맺은
  실시간 연결로 간다. Pro 의 Mod(API) 스크립트는 롤20 서버 샌드박스에서 돌고 외부 네트워크가 막혀 저장소
  데이터를 직접 못 가져간다. 그래서 이 경로를 쓴다.
- 핸드아웃 `notes`·`gmnotes`, 캐릭터 `bio`·`gmnotes` 는 속성이 아니라 blob 이다. `m.get('notes')` 는
  타임스탬프만 준다. 쓰기는 `m.updateBlobs({...})`, 읽기는 `m._getLatestBlob(field, cb)`. 이름·공개 범위는
  `m.save({...})`. 새로고침 뒤 되읽어 서버 반영을 확인했다.
- 롤20 편집기로 저장한 본문은 `escape()` 인코딩(`%3Cp%3E%uD55C…`)으로, 우리가 쓴 것은 평문 HTML 로
  남는다. 둘 다 화면에 정상으로 렌더링된다. `R20H.read` 가 해독해 준다.
- `inplayerjournals`·`controlledby` 는 `''`(GM 만), `'all'`, 또는 플레이어 id 쉼표 목록이다.
- 캐릭터 시트 속성(`c.attribs`)은 처음엔 비어 있다. `c.attribs.fetch(c.attribs)` 로 불러와야 보인다.
- **시트 창은 반드시 `c.attribs.fetch()` 로 속성을 다 불러온 뒤에 연다.** 새 탭에서 불러오기 전에
  `c.view.showDialog()` 하면 시트가 빈 캐릭터로 여겨 초기화를 다시 돌린다 — 기본 물품 16줄과 빈 자동 표시 줄이
  한 벌 더 생기고 행동 점수가 플레이북 초기값으로 돌아갔다(복구: 같은 이름 줄 중 하나만 남기고 원본 재반영).
  `applySheet` 가 이 순서를 지킨다. 사용자가 롤20 화면에서 시트를 여는 것은 문제없다.
- **시트 워커(파생값 계산)는 시트 창이 열려 있을 때만 돈다.** 그래서 `applySheet` 가 먼저
  `c.view.showDialog()` 로 시트를 연다. 열린 채로 `hunt`·`study` 를 쓰면 `insight` 가 따라 바뀌는 것을
  확인했다(Blades in the Dark 시트 v3.11).
- **자동 채움은 `playbook` 이 바뀔 때마다 다시 돈다.** 이때 `changed_attributes`(시트 화면에서 사람이 바꾼
  속성 이름의 쉼표 목록)에 없는 값은 초기값으로 덮고, `<줄>_autogen` 이 1 인 줄은 지운 뒤 새로 만든다. 스크립트로
  쓴 값은 이 목록에 안 올라가서, 다른 탭에서 시트를 다시 열었을 때 행동 점수·설명이 초기값으로 돌아간 적이
  있다. 그래서 `applySheet` 는 쓴 속성 이름을 `changed_attributes` 에 더하고, 손댄 자동 생성 줄의 `autogen` 을
  비운다(시트 워커 `handlePlaybookFill`·`updateChangedAttrs`·`watchAutogen` 이 하는 일을 흉내 낸다).
- 플레이북을 바꿨다 되돌리는 시험은 하지 않는다. 자동 채움 두 번이 겹쳐 기본 줄이 지워지고 다른 플레이북 줄이
  남았다. 스크립트 변경에는 자동 채움이 돌다 말다 해서 다시 돌려 복구할 수도 없었다(손으로 정리했다).
- 반복 줄은 `repeating_<섹션>_<rowid>_<필드>` 속성이다. rowid 는 20자 push-id 형식으로 새로 만들어
  쓰면 시트에 줄로 나타난다.
- **`playbook` 에 시트가 아는 이름(한국어 시트면 '유령사'·'칼잡이' 같은 한국어 이름)을 쓰면 시트 워커가
  그 플레이북의 특수 능력·물품·지인을 반복 줄로 채우고, 행동 점수·`playbook_description`·`trauma` 를
  초기값으로 덮는다.** 'Cutter' 처럼 시트가 모르는 이름이면 아무 일도 없다. 그래서 `applySheet` 는
  플레이북을 먼저 쓰고 5초 기다린 뒤 나머지를 쓴다. 자동으로 채워지는 줄과 원본의 줄 이름이 다르면 같은
  사람이 두 줄로 생기니(예: '니릭스, 빙의 유령'), 원본에는 시트가 채운 이름을 그대로 쓴다. 자동으로
  채워진 능력 줄은 `check` 가 꺼진 채 남는다. 고른 능력만 `check: 1` 로 켠다.
- 이미지(`avatar`, 본문 `<img>`)는 플레이어 브라우저가 직접 받으므로 **공개 URL** 이어야 한다. private
  GitHub 저장소의 raw URL 은 안 보인다.
