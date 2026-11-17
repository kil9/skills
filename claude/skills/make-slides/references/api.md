# make-slides 부품 API

정본은 `scripts/deck.py` 다. 여기는 덱을 쓰는 사람(서브에이전트 포함)이 원본을 열지 않고 쓸 수 있게 시그니처와
함정만 모았다. 장표 규칙(무엇을 써야 하나)은 SKILL.md §3 이 정본이다.

## 프로젝트 구조

```
<프로젝트>/
  course.py          # 덱 설정
  content/
    __init__.py
    d01.py           # 덱 1 의 build(D)
    d02.py ...
  OUTLINE.md         # 착수 결정 + 덱별 목표·장 제목 (build.py --outline 이 '빌드된 슬라이드' 절을 쓴다)
  out/               # 빌드 결과(gitignore). dNN.html, index.html
```

덱 파일 이름은 `d{번호:02d}.py`. `DECKS` 에 있는데 파일이 없으면 목차에 "(준비 중)" 으로 뜬다.

## course.py

| 이름 | 필수 | 뜻 |
|---|---|---|
| `TITLE` | 예 | 강좌 이름. 표지 머리 글씨·상단 막대·목차 제목 |
| `DECKS` | 예 | `{번호: 제목}`. 0 번은 오리엔테이션처럼 "강의 N" 표기 없이 나온다 |
| `LECTURE` | 아니오(기본 `True`) | 강의형이면 덱마다 요약·확인 문제·정답이 있어야 check 통과. 발표형은 `False` |
| `TOTAL` | check 에서 예 | `(최소, 최대)` 총 장수. 벗어나면 FAIL |
| `EXTRA_BANNED` | 아니오 | 덱에 나오면 FAIL 인 낱말 목록(기본: `—`, `TODO`, `TBD`, `lorem`) |
| `EXTRA_WARN` | 아니오 | `{낱말: 권하는 말}`. 나오면 WARN 만 |
| `cover_figure(no)` | 아니오 | 표지 오른쪽 SVG HTML 을 돌려준다. `no=None` 이면 목차 페이지용 |
| `head_extra(no)` | 아니오 | 덱 `<head>` 에 더할 HTML |

## Deck (build(D) 의 D)

```python
def build(D):
    D.set_goals("...할 수 있다", "...")   # 표지 목표 2-4개
    D.section("왜 필요한가")              # 이후 장의 머리 글씨
    D.slide("결론 한 문장이다", 부품, 부품, ...)
    D.summary([(핵심, 기억할 것), ...])   # 요약 1장
    D.quiz([(질문, 정답, 풀이), ...])      # 문제 1장 + 정답 1장
```

| 메서드 | 인자 | 비고 |
|---|---|---|
| `set_goals(*goals)` | 문자열 여럿 | 표지 표("이 강의를 마치면" / 발표형은 "이 발표에서") |
| `section(name)` | 문자열 | 다음 `section` 까지 모든 장의 eyebrow |
| `slide(title, *body, eyebrow=None, kind="")` | 제목, 부품 HTML 들 | `eyebrow` 를 주면 그 장만 머리 글씨를 바꾼다 |
| `summary(rows)` | `[(핵심, 기억할 것)]` | 강의형 필수 |
| `quiz(items)` | `[(질문, 정답, 풀이)]` | 강의형 필수. 풀이에 숫자의 출처까지 |

표지는 `build.py` 가 `D.cover()` 로 자동으로 맨 앞에 붙인다. 직접 만들지 않는다.

## 본문 부품 (HTML 문자열을 돌려준다)

| 부품 | 시그니처 | 쓰는 곳 |
|---|---|---|
| `say` | `say(*lines)` | 문장. 인자 하나 = 한 줄. **장 전체 4줄, 한 줄 110자까지**. HTML(`<b>`, `<code>`) 허용 |
| `src` | `src(text)` | 출처 한 줄(작은 글씨, "출처 · " 가 앞에 붙는다). 문장 줄 수에 안 센다. 실측값엔 필수 |
| `table` | `table(head, rows, align="", cls="", hl=(), widths=None)` | `align` 은 열마다 `l`/`r`/`c`(예: `"lrr"`). `hl` 은 강조 행 번호(0부터). `widths` 예: `["30%", None]`. 행이 많으면 `cls="sm"` |
| `terms` | `terms([(용어, 뜻, 빗대면)])` | 새 용어 풀이 표. 빗댄 말은 셋째 열에만 |
| `aside` | `aside(title, *lines, ref="")` | 본문과 출처가 다른 정보 패널. 3줄까지. `ref` 는 제목 옆 작은 글씨 |
| `cols` | `cols(*parts, ratio="")` | 가로로 나란히. `ratio` 예: `"3fr 2fr"`. 기본은 같은 너비 |
| `kpis` | `kpis([(값, 설명)])` | 큰 숫자 띠. 곁들임이지 표·그림을 대신하지 않는다(check 에서 표·SVG 로 안 센다) |
| `code` | `code(text)` | 설정·명령 원문. 자동 escape. 줄마다 풀이가 필요하면 `table` |
| `esc` | `esc(s)` | HTML escape. 사용자 문자열을 셀에 넣을 때 |

## SVG 부품

좌표는 `svg()` 에 준 viewBox 기준이다. 색은 `cls` 로만 준다(인라인 색 금지).

| 부품 | 시그니처 | 비고 |
|---|---|---|
| `svg` | `svg(w, h, *parts, label="그림", maxh=None)` | 그림 하나. `label` 은 aria-label. 제목과 겹치면 `maxh`(px)로 줄인다 |
| `box` | `box(x, y, w, h, title="", sub=None, cls="", rx=8, size=None)` | 굵은 제목 + 보조 줄(문자열 또는 목록), 가운데 정렬. 줄 간격 20 |
| `txt` | `txt(x, y, s, cls="", anchor="start", size=None)` | `anchor` 는 `start`/`middle`/`end` |
| `arrow` | `arrow(x1, y1, x2, y2, label="", cls="", dash=False, lx=None, ly=None)` | 직선 화살표. `cls="acc"` 면 강조색 화살촉. 라벨은 중간 위(위치는 `lx`/`ly`) |
| `path` | `path(d, cls="", arrowhead=False, dash=False)` | 꺾인 선. `d` 는 SVG path 문법 |
| `line` | `line(x1, y1, x2, y2, cls="grid")` | 화살촉 없는 선. 눈금·구분선 |
| `rect` | `rect(x, y, w, h, cls="", rx=3)` | 글자 없는 상자. 막대·띠 |
| `hbars` | `hbars(items, w=1100, unit="", maxv=None, label=..., bar_h=26, lw=260)` | 가로 막대 그래프 **완성품**(내부에서 `svg()` 를 부른다 — 다시 감싸지 않는다). `items = [(이름, 값, cls)]`, cls 생략 시 `acc`. 높이 = 항목 수 × (bar_h + 12) |

### 클래스

| 대상 | 클래스 |
|---|---|
| 상자(`box`·`rect`) | `""` 기본 · `acc` 강조 · `warn` 주의 · `bad` 나쁨 · `ok` 좋음 · `mute` 흐림 · `plain` 테두리만 · `ghost` 점선 · `solid` 채운 강조 |
| 글자(`txt`) | `sm` 작게·보조색 · `b` 굵게 · `mono` 고정폭 · `mut` 흐림 · `acct` 강조색 · `badt` 나쁨색 · `okt` 좋음색. 공백으로 겹쳐 쓴다(`"sm b"`) |
| 선(`arrow`·`path`) | `""` 기본 · `acc` 강조 · `bad` 나쁨 |
| 선(`line`) | `grid` |

### 함정

- 화살촉 marker 를 손으로 정의하지 않는다. `svg()` 가 그림마다 유일한 id 를 붙인다.
- `txt` 의 y 는 글자 **기준선**이다. 상자 안에 넣을 땐 상자 위쪽 + 글자 크기만큼 내려야 안 겹친다.
- 글자가 viewBox 밖으로 나가면 잘린다. `check.py --render` 가 잡지만 캡처로도 본다.
- `hbars` 값이 숫자면 천 단위 쉼표가 붙는다. 문자열이면 그대로 쓴다.

## 스크립트

`$S = ~/.claude/skills/make-slides/scripts`

| 명령 | 하는 일 |
|---|---|
| `python3 $S/build.py <dir> [N...] [--outline]` | `out/dNN.html`·`out/index.html` 생성. `--outline` 은 `OUTLINE.md` '빌드된 슬라이드' 절 갱신 |
| `python3 $S/check.py <dir> [N...] [--render]` | 규칙 검사(표·SVG 유무, 문장 줄 수·길이, 금지어, 강의형 필수 장, 총 장수). `--render` 는 headless 브라우저로 넘침·제목 겹침·SVG 글자 잘림까지 |
| `python3 $S/shot.py <dir> N [장...]` | `~/.cache/make-slides/shots/<dir이름>/dNN-MM.png` 캡처 |

## 결과물에서 쓸 수 있는 것

- 주소 `dNN.html#7` 은 7번째 장, `#last` 는 마지막 장.
- 키: →·Space·Enter·PgDn 다음, ←·Backspace·PgUp 이전, Home·End 처음·끝. 덱 끝에서 넘기면 다음 덱으로 간다.
- 인쇄(PDF 저장)하면 장마다 한 쪽.
- `?check` 를 붙여 열면 넘침·잘림을 재서 `#__check` 에 JSON 으로 쓴다(`check.py --render` 가 쓴다).
