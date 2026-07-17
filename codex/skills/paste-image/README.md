# $paste-image

원격 SSH 세션의 Codex에 **브라우저 Ctrl+V 한 번으로** 로컬 스크린샷/이미지를 넘겨준다.

## 이런 적 없으셨나요

원격 서버에 SSH로 붙어서 Codex로 작업 중이다.

- UI 버그를 보여주려고 **스크린샷을 찍었는데**, 클립보드는 로컬이라 원격 터미널에 붙여넣을 수가 없다.
- 매번 로컬에 저장 → `scp user@remote:/tmp/...` → Codex에게 경로 말해주기 — 4단계를 반복한다.
- 결국 귀찮아서 이미지 대신 텍스트로 대충 설명하고 넘어간다.

이 스킬 디렉토리는 두 가지 경로를 제공한다.

- **빠른 경로 (`pimg`, 권장)** — 상시 업로드 서버 + 고정 URL 북마크. LLM 왕복 없이 즉시.
- **스킬 경로 (`$paste-image`)** — Codex 가 일회용 서버를 띄우고 업로드를 기다렸다가 알아서 확인.

## 빠른 경로: `pimg` (상시 서버)

```
사용자: (셸에서) pimg
 └─ 상시 HTTP 서버 보장 기동, 고정 토큰 URL 출력 (이미 떠 있으면 URL 만 재출력)
     └─ 사용자: 북마크해 둔 URL 열고 Ctrl+V
         └─ 업로드 완료 → 페이지가 원격 저장 경로를 로컬 클립보드에 자동 복사
             └─ 사용자: 챗창에 그 경로를 붙여넣기 → Codex 가 `view_image` 로 확인
```

- 토큰이 `tmp/persist/token` 에 영속화되므로 **재시작해도 URL 이 유지**된다. 브라우저에 북마크해 두면 `pimg` 조차 생략하고 탭만 열면 된다 (서버가 떠 있는 한).
- 서버는 여러 업로드를 계속 받는다. 연속으로 이미지 여러 장을 넘길 때 그대로 계속 Ctrl+V.
- `pimg stop` 중지 / `pimg last` 마지막 업로드 경로 출력 / `pimg <port>`·`pimg host=<name>` 오버라이드.
- 경로 자동 복사는 http(비보안 컨텍스트)에선 `execCommand` 폴백을 쓰는데, 브라우저에 따라 사용자 제스처 만료로 실패할 수 있다. 그 경우 페이지의 "경로 복사" 버튼을 누르면 된다.
- 설치: `bootstrap/link-dotfiles.sh` 가 `rc/bin/pimg` 를 `~/.local/bin/pimg` 로 링크한다.

## 스킬 경로: `$paste-image` (일회용)

```
사용자: $paste-image
 └─ Codex: 원격 서버에 임시 HTTP 서버 기동 (랜덤 토큰 URL)
     └─ 사용자: 안내된 URL을 로컬 브라우저에서 열고 Ctrl+V (또는 파일 드롭)
         └─ 업로드 완료 → 서버가 경로를 Codex에 전달하며 스스로 종료
             └─ Codex: 그 경로를 `view_image`로 확인
```

경로 복사/붙여넣기가 아예 필요 없는 대신 LLM 왕복(스킬 기동·대기·확인)이 끼어 빠른 경로보다 느리다. 원격 서버가 로컬 클립보드에 접근할 필요가 없다는 점은 두 경로 모두 같다 — **브라우저를 중간 다리**로 쓴다.

## 설치

이 스킬은 [kil9/skills](https://github.com/kil9/skills) 저장소의 `codex/skills/paste-image/` 에 포함돼 있다. kil9conf 부트스트랩을 거치면 `bootstrap/link-dotfiles.sh` 가 `~/.codex/skills/paste-image` 와 `~/.agents/skills/paste-image` 를 심링크하고, `~/.local/bin/pimg` 를 `rc/bin/pimg` 로 링크한다. Codex 재시작 후 `$paste-image` 사용 가능.

첫 실행 시 `run.sh` 가 $PASTE_IMAGE_HOST_DOMAIN 이 설정돼 있으면 `$(hostname).$PASTE_IMAGE_HOST_DOMAIN` 의 DNS 조회를 시도해 풀리면 그 값을, 안 풀리거나 미설정이면(WSL·개인 머신·로컬 macOS 등) `localhost` 를 골라 `host.cache` 에 기록한다. 다음부터는 캐시 값을 그대로 쓴다. 환경이 바뀌어 재검증이 필요하면 `host.cache` 를 지우면 된다. 캐시 결과를 무시하고 강제로 못 박고 싶으면 `host.local.example` 을 `host.local` 로 복사해 `HOST=` 를 직접 지정한다 (`host.local`, `host.cache` 모두 gitignored).

## 사용법

### 빠른 경로

```
pimg                  # 아무 셸에서
pimg 9000             # 포트 지정
pimg host=10.1.2.3    # 호스트 지정
pimg stop             # 상시 서버 중지
pimg last             # 마지막 업로드 경로
```

### 스킬 경로

```
$paste-image
$paste-image 9000
$paste-image host=my-vm.example.com
$paste-image 9000 host=10.1.2.3
```

- 포트 기본값 `13000`. 점유 시 `+1` 씩 최대 10회 linear probe.
- 호스트 결정 우선순위(높은 것이 이김):
  0. `host.local` 의 `FUNNEL_BASE_URL` (Tailscale Funnel 전용). **설정돼 있으면 아래 1\~5 를 전부 무시한다**
     — `host=` 인자를 줘도 조용히 무시되므로, Funnel 을 안 쓸 땐 `host.local` 에서 이 값을 지운다.
  1. `host=<name>` 인자
  2. `PASTE_IMAGE_HOST` 환경변수
  3. `host.local` 의 `HOST` (사용자 수동 override, gitignored)
  4. `host.cache` 의 `HOST` (run.sh 가 첫 실행 시 자동 생성, gitignored)
  5. `host.cache` 가 없으면: $PASTE_IMAGE_HOST_DOMAIN 설정 시 `$(hostname).$PASTE_IMAGE_HOST_DOMAIN` 을 DNS 로 조회 → 성공이면 그 값, 실패·미설정이면 `localhost`. 결과를 `host.cache` 에 기록.

### skill 없이 서버만 돌리기

Codex 없이 업로드 서버만 써도 된다.

```sh
python3 server.py [--port N] [--save-dir DIR] [--timeout SECONDS] [--persist] [--token-file PATH]
```

기본값: `--port 13000`, `--timeout 600`(일회용 전용, `--persist` 에선 무시). 저장 경로는 `--save-dir` 지정 시 그 경로, 아니면 OS 임시 디렉토리 (Linux/macOS `/tmp`, Windows `%TEMP%`). 둘 다 쓰기 불가면 `<cwd>/tmp` 로 폴백.

출력 규약:

- **stderr**: `LISTEN:<url>` — 서버 시작 시 한 줄
- **stdout**: `SAVED:<abs_path>` (성공. 일회용은 1회 후 exit 0, `--persist` 는 업로드마다 1줄) / `TIMEOUT` (일회용 타임아웃, exit 2)

## 보안 모델

`0.0.0.0` 으로 바인드되므로 사내망 전체에 노출된다. 노출을 줄이기 위해 다음을 강제한다.

- **랜덤 URL 토큰** — URL을 모르면 접근 불가. 일회용은 `secrets.token_urlsafe(8)` 을 매 실행마다 재생성, 상시 모드는 `token_urlsafe(16)` 을 `tmp/persist/token` 에 영속화.
- **일회용: 1회 성공 → 자동 shutdown** — 최대 노출 시간은 600초(기본 타임아웃).
- **상시 모드의 트레이드오프** — 서버가 상주하고 토큰이 고정되므로 노출 창이 넓다. 편의(북마크·즉시성)와 맞바꾼 것. 토큰 로테이트는 `pimg stop && rm tmp/persist/token && pimg`.
- **Content-Type 화이트리스트** — `png`, `jpeg`, `gif`, `webp`, `bmp`, `heic`, `heif` 만 받는다. **SVG는 의도적으로 제외** — XML 안에 `<script>` 를 넣을 수 있어 XSS 벡터로 간주.
- **크기 상한 20 MB** — 초과 시 413.
- **파일명은 서버가 생성** — `paste-<timestamp>-<rand>.<ext>` 포맷. 클라이언트 제공 이름을 쓰지 않아 path traversal 차단.
- **실패는 종료시키지 않음** — 415/413 등은 브라우저에서 바로 재시도 가능.

## 요구사항

- Python 3.9+ (표준 라이브러리만 사용. 외부 의존성 없음.)
- Codex — `$paste-image` skill 을 쓰려면 필요. 서버 단독 실행에는 불필요.

## 파일 구조

```
paste-image/
├── SKILL.md              # $paste-image skill 본문
├── run.sh                # 얇은 래퍼. start/wait(일회용) + ensure/stop/last(상시) + 호스트 검증/캐시
├── server.py             # paste 업로드 HTTP 서버 (일회용 기본, --persist 로 상주)
├── host.local.example    # 머신별 기본 호스트 override 템플릿
├── host.local            # (선택, gitignored) 사용자가 명시적으로 만든 머신별 override
├── host.cache            # (자동, gitignored) 첫 실행 시 hostname 검증 결과 캐시
├── tmp/persist/          # (자동, gitignored) 상시 서버 상태: pid·listen·token·uploads.log
└── README.md             # 이 문서
```

`pimg` 진입점은 `rc/bin/pimg` (→ `~/.local/bin/pimg`).

## 범위 외

군더더기를 빼기 위해 다음은 의도적으로 포함하지 않았다.

- 업로드 파일 자동 정리 — OS 임시 디렉토리에 그대로 쌓인다. 필요시 본인이 지운다.
- HTTPS / Basic auth — 토큰 URL 로 대체.
- 부팅 시 자동 기동(systemd 등) — `pimg` 가 없으면 띄우는 보장 기동이라 필요성이 낮다.
