---
description: (사외용) 사용자가 준비한 정적 콘텐츠를 공개 GitHub `kil9/til` 저장소에 새 페이지로 추가하고, 루트 index.html 갤러리·README 표를 갱신해 main 으로 commit/push 한다. GitHub Pages 가 push 만으로 자동 배포하며 `https://kil9.github.io/til/{slug}/` URL 을 돌려준다.
allowed_tools: [Bash, Read, Edit, Write, Glob, Grep, AskUserQuestion, WebFetch]
---

호출: `/publish-til [<slug>]`

인자가 있으면 그 슬러그를 새 페이지 디렉터리명으로 사용한다. 없으면 §1 의 인터뷰로 받는다.

---

## 사전 지식 (저장소 사실)

- 저장소 경로: `~/work/kil9/til`. origin = github.com 의 `kil9/til` — **PUBLIC 저장소**다. push 하는 순간 전부 공개되며, 되돌려도 히스토리에 남는다.
- 기본 브랜치: `main`. 단일 브랜치.
- 호스팅: GitHub Pages 가 `main` 브랜치 루트를 그대로 서빙한다(별도 빌드 없음). **push 만으로 몇십 초 뒤 자동 반영** — 명시적 deploy 단계가 없다.
- URL: `https://kil9.github.io/til/<slug>/` (루트 갤러리: `https://kil9.github.io/til/`).
- 디렉터리 명명: 고정 규칙 없음 — 매번 자유 슬러그(kebab-case: 소문자·숫자·하이픈). 시간순 정렬이 필요한 주제면 `2026-` 처럼 연도 접두사를 권장. 슬러그는 URL 에 영구히 박힌다.
- **상세 런북은 저장소의 `AGENTS.md`(퍼블리시 런북 섹션)가 정본이다.** 콘텐츠 재조립(claude.ai artifact 의 프레임 런타임 제거, standalone 골격)·갤러리 카드 형식(`data-date`/`data-topic`, `Published · N` 카운트)·README 표 형식은 그쪽을 따른다. 이 스킬과 런북이 어긋나면 저장소 AGENTS.md 가 우선.

---

## 0. 프리플라이트 (Bash 호출 1회)

이 스킬 디렉터리의 `til-preflight.sh` 를 실행한다. 경로·origin(`kil9/til`; 구명 `kil9/docs`
리다이렉트면 set-url 자동 갱신)·`main` 브랜치·clean tree 를 일괄 검증하고, 슬러그를 인자로 주면
형식·충돌 검사까지 수행한다. 개별 git 명령으로 따로 확인하지 않는다.

```
bash ~/.claude/skills/publish-til/til-preflight.sh [<slug>]
```

- exit 1: 전제 불충족 — 출력을 근거로 중단한다(경로 없음이면 사용자에게 클론 위치를 묻는다).
- exit 3: `<slug>/` 이미 존재 — 덮어쓰기 금지 원칙대로 사용자에게 물은 뒤에만 진행한다.
- 통과 후 `cd ~/work/kil9/til`, 저장소의 `AGENTS.md` 퍼블리시 런북을 읽어 둔다 (이후 단계의 정본).

---

## 1. 슬러그 수집

- 인자가 있으면 kebab-case(소문자·숫자·하이픈) 형식을 검증하고 사용한다. 형식이 어긋나면 인터뷰로 떨어진다.
- 없으면 `AskUserQuestion` 으로 슬러그를 받는다. 콘텐츠 주제에서 후보 2-3개를 만들어 옵션으로 제시하고(시간순 주제면 연도 접두사 포함 후보), Other 자유 입력을 허용한다. 슬러그는 URL 에 영구히 박힌다는 점을 질문에 명시한다.
- 충돌 검사: §0 프리플라이트에 슬러그를 넘겼으면 이미 끝났다. 인터뷰로 새로 받은 슬러그는 `til-preflight.sh <slug>` 재실행으로 확인한다(exit 3 = 존재). 덮어쓰기는 사용자가 명시적으로 원할 때만 진행한다.

---

## 2. 콘텐츠 소스 확보

`AskUserQuestion` 으로 어떤 콘텐츠를 publish 할지 묻는다. 옵션은 다음 형태로 제시하되, Other 로 자유 입력을 허용한다.

- 단일 HTML 파일을 `index.html` 로 배치 (예: `/tmp/draft.html`)
- claude.ai artifact URL — `WebFetch` 로 가져와 저장소 런북대로 프레임 런타임 제거·standalone 재조립 (`curl` 은 SPA 셸/403 이라 쓰지 않는다)
- 디렉터리 전체를 그대로 복사 (안에 `index.html` 필수)
- 빈 템플릿만 생성하고 사용자가 이후 직접 채움

### 2-1. 보안 사전 점검 (public — 사내용보다 엄격)

게시 전에 다음 패턴을 grep 으로 점검한다. 하나라도 발견되면 해당 라인을 보여 주고 `AskUserQuestion` 으로 진행 여부를 묻는다. 사용자가 명시적으로 OK 하면 계속, 아니면 중단한다.

- `(?i)token|secret|password|api[_-]?key|bearer\s+[A-Za-z0-9]`
- **직장·내부 흔적 전부**: 회사 내부 도메인(비 github.com git 호스트 등 — 머신 로컬 `~/.claude/private-domains.txt` 가 있으면 그 패턴도 함께 grep), 내부 저장소·이슈 참조(GHE 링크, `repo#issue` 표기), 내부 호스트명, 사설 IP.
- `mailto:`·이메일 주소·개인 식별정보.
- 외부 리소스 의존(CDN `script`/`link`/`img src="http…"`) — 자체 완결 원칙 위반이므로 인라인 또는 `data:` URI 로 교체하거나 사용자 확인.
- 저작권·초상권이 걸린 콘텐츠(방송 캡처·팬아트 등)는 공개 게시 전 사용자 확인을 받는다.

---

## 2-2. 시각 자료 보강

**무엇을 어떻게 그릴지는 저장소 `AGENTS.md` §2-1(시각 자료)이 정본이다.** 표/차트/인포그래픽 우선,
인라인 SVG + CSS 변수로 다크모드 대응, 외부 차트 라이브러리 금지, 삽화는 페이지당 1-2장,
WebP(1440px·q75) base64 `data:` URI 임베드, `figure.illust`+`alt`+`figcaption` 마크업 등.
여기 옮겨 적지 않는다 — §0 에서 읽어 둔 그 문서를 따른다(중복하면 드리프트가 난다).

이 스킬이 정본인 것은 아래 둘뿐이다.

- 차트를 그리기 전에 `dataviz` 스킬을 읽는다.
- **Claude 는 래스터 이미지를 직접 생성하지 못하므로 삽화 생성은 반드시 codex 에 위임한다**(이 머신에 `codex` CLI 설치됨, `image_generation` feature stable — `codex features list` 로 확인 가능). 그 호출 레시피가 아래이며, 저장소 `AGENTS.md` §2-1 도 레시피는 이 절을 가리킨다(서로 반대 방향을 가리키지 않도록 주의).

### 삽화 생성 레시피 (codex 위임)

```bash
codex exec --dangerously-bypass-hook-trust --dangerously-bypass-approvals-and-sandbox \
  --cd <스크래치 디렉터리> \
  "이미지 생성 도구(image generation)로 <주제> 에디토리얼 삽화 1장을 생성해줘.
   구도: <가로형(1536x1024) 등 + 장면 묘사>.
   스타일: 주제에 어울리게 자유롭게 고른다(플랫 벡터, 수채, 리소그래프, 애니메이션 풍 등).
   팔레트: 자유. 사이트가 극한 미니멀(무채색+블루)이므로 삽화까지 같은 톤이면 지루하다 —
     색·그라데이션·질감을 써도 좋다. 단 다크모드 filter 와 어울리도록 라이트 톤 배경을 기본으로.
   절대 금지: 이미지 안 글자·숫자·텍스트(생성 텍스트는 깨진다), 사람 얼굴 클로즈업.
   생성한 이미지를 <절대경로>.png 로 저장하고 최종 응답으로 경로와 픽셀 크기를 알려줘."
```

- 프롬프트에 **저장 절대경로**와 **이미지 내 텍스트 금지**를 반드시 명시한다. 생성물은 `~/.codex/generated_images/` 아래에 떨어지고 codex 가 지정 경로로 복사해 준다. 1회 1-5분 소요, 결과는 Read 로 눈검사한다(텍스트 유무·구도·톤).
- 생성된 PNG 를 페이지에 넣는 방법(리사이즈·WebP 압축·base64 임베드·마크업)은 저장소 `AGENTS.md` §2-1 을 따른다.

---

## 3. 배치

`<slug>/index.html` 로 저장한다. 결과 파일이 `<!doctype html>` 로 시작하고, 외부 의존 없이 단일 파일로 열리며, `prefers-color-scheme` 다크 폴백이 있는지 확인한다. 스타일 없는 콘텐츠는 런북 §2 의 **공통 셸**(미니멀 무채색+블루 액센트)로 감싼다. 자체 스타일 artifact 페이지라도 **favicon·OG 메타 블록·Cloudflare beacon**(전부 런북 §2 템플릿에 포함)은 반드시 넣는다 — beacon 은 외부 리소스 금지 원칙의 유일한 예외.

---

## 4. 목록 갱신 (둘 다)

한 줄 제목을 `AskUserQuestion` 으로 짧게 받는다(기본값: 슬러그를 케이스 정리해 제시).

- 루트 `index.html`: 갤러리 카드를 **최신이 위로** 추가하고 `Published · N` 카운트를 증가시킨다. 카드에 `data-date="YYYY-MM-DDTHH:MM"`(퍼블리시 시각까지 포함 — `.date` 표시 텍스트는 JS 가 이 값으로 덮어쓴다)·`data-topic="<주제키>"`(영문 kebab-case) 를 반드시 넣는다. `.tag` 는 한국어 `<칩 라벨> · <세부 주제>` 형식이고, **칩 라벨은 한 단어여야 한다** — 칩은 `.tag` 를 `·` 로 split 한 첫 세그먼트라 칩 이름에 `·` 를 넣으면 잘린다. **주제 분류에 하위 호환은 없다**: 균형이 깨지면 기존 카드의 분류도 확인 없이 재조정하고 결과만 보고한다(기준값·분할 트리거는 저장소 AGENTS.md §4-1 이 정본).
- `README.md`: "퍼블리시된 페이지" 표 **맨 위**에 행을 추가한다 (날짜 · 제목 · `[/<slug>/](https://kil9.github.io/til/<slug>/)`). 갤러리와 동일한 **최신이 위** 정렬 — 갤러리는 JS 가 `data-date` 로 알아서 정렬하지만 README 는 정적이라 손으로 지켜야 한다.

---

## 5. 검증 (Bash 호출 1회)

이 스킬 디렉터리의 `til-verify.sh` 로 doctype·favicon(`rel="icon"`)·`og:title`·Cloudflare
beacon·갤러리 카드/README 행의 `<slug>/` 참조 일관성을 일괄 확인한다. FAIL 항목이 있으면 보정
후 재실행한다.

```
bash ~/.claude/skills/publish-til/til-verify.sh <slug>
```

- 빌드·테스트 없음(정적 파일). 로컬 미리보기(`python3 -m http.server`)는 사용자가 요청할 때만.

---

## 6. 커밋 · 푸시 (자동)

`AskUserQuestion` 없이 즉시 진행한다. 저장소의 PLAN.md 진행 상황 갱신이 필요하면 같은 커밋에 포함한다(저장소 커밋 규칙).

```bash
git add <slug> index.html README.md
git commit -m "[publish] <slug> 페이지 추가 — <한 줄 제목>"
git push origin main
```

- 커밋 이메일은 저장소 로컬 설정(public 프라이버시용 noreply)을 그대로 쓴다 — 별도 설정하지 않는다.
- 푸시 실패 시 즉시 중단하고 마지막 출력을 사용자에게 보여 준다.

---

## 7. 최종 보고

- 신규 디렉터리 경로와 커밋 SHA
- **URL: `https://kil9.github.io/til/<slug>/`**
- GitHub Pages 는 push 후 몇십 초 뒤 자동 반영된다는 안내(첫 빌드는 조금 더 걸릴 수 있음). 필요하면 `gh api repos/kil9/til/pages --jq '.status'` 로 상태 확인.

---

## 자율 실행 규칙

- §0(전제 불충족), §1(슬러그 인터뷰·충돌), §2(소스 선택), §2-1(보안 의심) 외에는 사용자에게 묻지 않는다. §6 커밋·푸시는 자동 진행한다.
- 이 저장소는 public 이다 — 판단이 애매하면 가장 보수적인 선택(중단·질문)을 한다.
- 본 스킬은 새 페이지 추가 전용이다. 기존 페이지 수정·삭제는 다루지 않는다.
- kil9conf 의 PLAN.md 는 수정하지 않는다. til 저장소의 PLAN.md 는 그 저장소 커밋 규칙에 따라 필요할 때만 갱신한다.
