# manage-gmail-inbox 최초 설정 (계정당 1회)

`gmail.py` 가 쓸 OAuth 클라이언트를 만들고 토큰을 발급받는 절차. 한 번 해 두면 이후엔
토큰이 자동 갱신되므로 다시 볼 일이 없다. 자격증명은 전부 repo 밖
(`~/.config/gmail-cli/`, `$GMAIL_CLI_HOME` 으로 변경 가능)에 둔다.

## 1. Google Cloud 프로젝트와 OAuth 클라이언트

[console.cloud.google.com](https://console.cloud.google.com) 에서:

1. 프로젝트를 하나 만든다(이름 아무거나).
2. **API 및 서비스 → 라이브러리 → Gmail API → 사용**. 이걸 빼먹으면 인증은 통과하는데
   첫 호출에서 `Gmail API has not been used in project ... before or it is disabled` 403 이
   난다. 활성화 후 전파에 1-2분 걸린다.
3. **OAuth 동의 화면**: 사용자 유형 **외부(External)**, 앱 이름·지원 이메일만 채운다.
4. **대상(Audience) 화면에서 앱을 "게시(Publish)" 해 프로덕션으로 바꾼다.** 테스트 상태로
   두면 **refresh token 이 7일 뒤 만료**돼 매주 재인증하게 된다. 게시해도 Google 심사는
   필요 없고(본인 계정만 쓰므로), 대신 승인 화면에서 "확인되지 않은 앱" 경고가 뜬다 —
   `고급 → <앱 이름>(으)로 이동` 으로 통과한다.
5. **클라이언트 → 클라이언트 만들기 → 애플리케이션 유형: 데스크톱 앱**.
   웹 애플리케이션을 고르면 안 된다 — loopback 리다이렉트가 막혀 `redirect_uri_mismatch` 가 난다.
6. 만든 클라이언트의 **JSON 을 다운로드**한다.

## 2. 자격증명 배치

다운로드한 파일을 이 이름으로 둔다:

```bash
mkdir -p ~/.config/gmail-cli
cp ~/Downloads/client_secret_*.json ~/.config/gmail-cli/credentials.json
chmod 600 ~/.config/gmail-cli/credentials.json
```

원격 서버에서 쓸 거라면 그 서버로 옮긴다(`scp`, 또는 내용을 붙여넣기).

## 3. 인증

### 데스크톱(브라우저가 같은 머신에 있음)

```bash
./gmail.py auth
```

출력된 URL 을 브라우저에서 열고 승인하면 끝난다. 요구 범위는 `gmail.modify` —
읽기와 라벨 조작은 되지만 **영구 삭제는 불가능한** 범위다.

### 헤드리스·원격 서버 (예: SSH 로 붙은 nuc14)

승인 후 리다이렉트가 **스크립트가 도는 그 호스트의** localhost 로 돌아와야 하므로,
포트를 고정하고 터널을 뚫는다.

```bash
# 원격 서버에서 — 이 명령은 콜백을 기다리며 멈춰 있는다
./gmail.py auth --port 8765
```

```bash
# 내 PC 에서 (별도 터미널)
ssh -N -L 8765:localhost:8765 <서버>
```

터널을 띄운 채 내 PC 브라우저에서 출력된 URL 을 열어 승인하면, 리다이렉트가 터널을 타고
서버의 대기 프로세스에 도달한다.

**터널을 못 쓸 때의 폴백**: 그냥 승인하면 브라우저가 `localhost:8765/?code=...` 로 가서
"연결할 수 없음" 을 띄운다. 이때 주소창의 URL 전체를 복사해 서버에서 직접 때리면 된다.

```bash
curl -s "http://localhost:8765/?code=4/0Ab...&scope=https://www.googleapis.com/auth/gmail.modify"
```

`&` 가 들어 있으니 따옴표를 반드시 붙인다. code 는 **1회용이고 수십 초 내에 만료**되므로
실패하면 `auth` 부터 다시 한다.

## 4. 확인

```bash
./gmail.py auth      # 인증 OK: you@gmail.com (총 N통)
./gmail.py labels    # 라벨별 안읽은 수
```

## 재인증이 필요해지는 경우

`gmail.py` 가 exit 4 와 함께 재인증을 요구하면 `./gmail.py auth --reauth` 로 토큰을 다시
받는다. refresh token 이 폐기되는 조건은: 앱이 테스트 상태(7일), 계정 비밀번호 변경,
사용자가 [계정 권한](https://myaccount.google.com/permissions)에서 앱 접근을 철회한 경우,
6개월 이상 미사용.
