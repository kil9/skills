---
name: web-show
description: 이 세션의 산출물(md·html·이미지·pdf, 또는 프론트엔드 개발 서버)을 브라우저 URL(http://<FQDN>:<port>/)로 띄워 보여준다. "브라우저로 띄워줘 / 웹으로 보여줘 / 미리보기 URL 줘 / web show" 라고 할 때, 그리고 사용자가 볼 HTML·문서 미리보기가 필요할 때(Artifact 대신). side-show 의 브라우저판이다.
argument-hint: "(선택) 띄울 파일 경로들, host=<name>"
---

원격 머신에서 개발하는 경우가 많아 localhost 가 아니라 FQDN 으로 띄운다. 사설망(tailnet·LAN) 한정이고
토큰은 없다. 실행은 `run.sh` 가 한다 — 호스트·포트 결정 로직을 여기서 다시 짜지 않는다.

## 문서·파일 (md·html·이미지·pdf …)

1. **대상 선정.** 인자 경로가 있으면 그대로. 없으면 이 세션에서 방금 만들었거나 크게 고친 산출물을 고른다.
   특정이 안 되면 후보를 대며 묻는다.
2. **띄우기.** 이 세션에 아직 서버가 없으면:
   ```
   ~/.claude/skills/web-show/run.sh start [host=<name>] FILE...
   ```
   `PID:`·`PORT:` 를 기억한다(종료할 때 쓴다). 이미 띄운 서버가 있으면 새로 띄우지 말고 등록만 더한다:
   `run.sh add <PORT> FILE...`
   - md 는 서버가 GFM·코드 하이라이트·mermaid 로 렌더링하고, 파일을 고치면 브라우저가 1초 안에 새로고침
     없이 갱신된다. 그 밖의 파일은 원본 그대로 준다.
   - 등록한 파일의 디렉터리가 그 URL 의 루트라 상대 경로 이미지·css·다른 md 도 열린다.
3. **보고.** `URL:` 줄의 URL 만 한 줄로 알린다(QR·푸시 없음). `HINT:` 가 나왔으면 그 안내도 한 줄 붙인다.

## 웹 디자인·프론트엔드

그 프로젝트의 개발 서버를 직접 0.0.0.0 bind 로 띄운다. 호스트는 `run.sh host`(→ `HOST:`), 포트는
`run.sh port`(→ `PORT:`, 18080 부터 빈 포트)로 얻어 `http://<HOST>:<PORT>/` 를 보고한다. 개발 서버는
background Bash 로 띄우고 **포트를 잡은 실제 프로세스**를 기억한다(아래 '이상할 때').

## 쓰임이 끝나면 닫는다

게시를 마쳤거나 대화 흐름상 더 필요 없으면 에이전트가 끈다 — 문서 서버는 `run.sh stop <PORT>`, 개발 서버는
그 프로세스를 kill 한 뒤 `ss -ltn`(macOS 는 `lsof -iTCP:<PORT> -sTCP:LISTEN`)으로 포트가 비었는지 본다.
세션이 끝날 때도 띄운 것을 남기지 않는다.

## 이상할 때

- **Vite 5+ 가 403 / "Blocked request. This host is not allowed"**: 모르는 Host 헤더를 막는다.
  `server.allowedHosts` 에 FQDN 을 넣는다(`vite.config` 또는 `--host 0.0.0.0` 와 함께). 다른 dev 서버도
  비슷한 Host 검사가 있다(webpack-dev-server `allowedHosts`, Next 의 `allowedDevOrigins`).
- **다른 기기에서 연결 거부**: 개발 서버가 localhost 에만 bind 했다 — `--host 0.0.0.0` 류 옵션을 준다.
  bind 가 맞는데도 안 되면 회사 머신 방화벽을 의심한다(그때는 사용자에게 알린다).
- **`npx vite` 의 PID 를 죽여도 포트가 안 빈다**: npx 는 node 자식을 남긴다. `ss -ltnp | grep :<PORT>` 로
  리스너 PID 를 찾아 죽인다.
- **URL 이 IP 로 나오고 `HINT:`**: FQDN 을 못 찾았다. 호스트 결정 순서는 `run.sh` 머리말에 있다
  (host= → `$WEB_SHOW_HOST` → `host.local` → `host.cache` → `$(hostname).$WEB_SHOW_HOST_DOMAIN` →
  tailscale DNSName). 찾은 FQDN 만 `host.cache` 에 남으니, 틀린 값이 박혔으면 그 파일을 지운다.
