---
name: show-qr
description: URL·텍스트를 QR 로 띄울 때 이미지 파일 대신 유니코드 블록 문자로 만들어 응답에 그대로 보여 준다. "QR 띄워줘 / QR 코드로 보여줘 / 폰으로 찍게 QR" 이라고 하거나 `/show-qr` 를 적었을 때. 데스크탑 화면을 폰 카메라로 찍는 용도다.
allowed_tools: [Bash]
---

# /show-qr

이미지를 만들어 뷰어로 열지 않는다 — 창이 어디 떴는지 사용자가 못 찾고, 터미널 출력은 인코딩에 따라
깨진다. 텍스트로 만들어 **응답 본문의 코드블록**에 붙이면 지금 보는 화면에 바로 뜬다.

## 1. 무엇을 담을지

`$ARGUMENTS` 가 담을 텍스트다. 비었으면 대화에서 방금 다룬 URL(페어링 링크 등)을 쓴다. 후보가 둘
이상이면 묻는다. 일회용 코드가 든 URL 이면 만료됐을 수 있으니 필요하면 새로 발급한 값으로 만든다.

## 2. 생성

```bash
PY=$(command -v python3 >/dev/null && python3 -c '' 2>/dev/null && echo python3 || echo python)
"$PY" -X utf8 ~/.claude/skills/show-qr/qr.py '<text>'
```

- Windows 의 Git Bash 에서는 `~/.claude` 가 정본이 아닐 수 있다 — `"$USERPROFILE/.claude/skills/show-qr/qr.py"`.
- 기본은 어두운 터미널 배경용이다. 사용자가 밝은 테마라거나 안 찍힌다고 하면 `--light` 를 붙여 다시 만든다.
- 처음 돌 때 `segno` 가 없으면 `~/.cache/show-qr/pylib` 에 한 번 받는다. 그것도 실패하면
  `qrencode` 로 대체하고, 둘 다 없으면 `ERROR:` 를 그대로 전한다.

## 3. 보여 주기

출력을 **한 글자도 바꾸지 말고** 언어 표시 없는 ``` 코드블록에 넣어 응답에 붙인다. 그 아래에 담은
텍스트(URL)를 한 줄로 같이 적는다 — 폰에서 이 화면을 보고 있으면 찍는 대신 누르면 된다.
일회용 코드면 만료 시각도 한 줄.
