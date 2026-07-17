---
name: paste-image
description: 원격 SSH 환경에서 브라우저 Ctrl+V / drag-and-drop 한 번으로 이미지를 Codex에게 전달한다. 일회용 HTTP 서버를 띄워 업로드 받은 뒤 view_image로 확인한다.
---

# $paste-image

실제 동작은 `run.sh` 가 전부 처리한다. Codex는 **세 단계**를 수행한다.

## 1. 서버 시작 (쉘 명령 — 즉시 반환)

```
~/.codex/skills/paste-image/run.sh start $ARGUMENTS
```

- `$ARGUMENTS` 는 그대로 넘긴다. 파싱하지 않는다 — `run.sh` 가 한다.
  - 허용 토큰: (없음) / 숫자(포트) / `host=<name>`. 조합·순서 임의. 예: `9000`, `host=10.1.2.3`, `9000 host=my-vm.example.com`.
- 이 쉘 명령 호출은 서버를 백그라운드로 기동하고 **즉시 반환**된다. 결과 stdout 에서 두 줄을 파싱한다:
  - `SESSION:<path>` — 세션 디렉토리 경로 (step 3 에서 필요)
  - `LISTEN:<url>` — 접속 URL

URL 을 파싱한 뒤 사용자에게 명시적으로 안내한다:
> 브라우저에서 아래 URL 을 열고 이미지를 Ctrl+V 또는 드롭하세요:
> `<url>`

## 2. 업로드 결과 대기 (쉘 명령 — 업로드 완료 또는 타임아웃까지 blocking)

```
~/.codex/skills/paste-image/run.sh wait <session-path>
```

`<session-path>` 는 step 1 에서 파싱한 `SESSION:` 값이다.
**중요**: 이 쉘 명령은 최대 10분 정도 걸릴 수 있다. Codex 실행 도구가 먼저 반환하면 session id를 보존하고 `write_stdin` 폴링으로 완료될 때까지 기다린다. 서버 자체 타임아웃은 600초다.

## 3. stdout 마지막 줄로 분기

쉘 명령 결과의 stdout 마지막 비어있지 않은 줄 기준:

- `SAVED:<path>` — `<path>` 를 추출해서 즉시 `view_image`로 연다. 이미지 확인이 끝나면 한 줄로 사용자에게 보고:
  > 이미지 수신 완료: `<path>`
- `TIMEOUT` — 한 줄만 보고:
  > 시간 초과로 이미지를 받지 못했습니다. 다시 시도해 주세요.
- `ERROR:…` 또는 그 외 — 내용을 그대로 사용자에게 전달하고 멈춘다.

## 금지 사항

- 사용자에게 경로를 복사해 달라고 요청하지 않는다.
- 포트·호스트 결정 로직을 skill 쪽에서 복제하지 않는다. `run.sh` 가 `host=` 인자 / `$PASTE_IMAGE_HOST` / `host.local` / 자동 검증 캐시(`host.cache`) / $PASTE_IMAGE_HOST_DOMAIN 기반 fallback 까지 전부 처리한다.
- `--timeout` / `--save-dir` 을 바꾸려는 요청이 $ARGUMENTS 로 들어와도 skill 은 받지 않는다. 사용자에게 "직접 `python3 ~/.codex/skills/paste-image/server.py --timeout N` 를 실행하라" 고 안내한다.
