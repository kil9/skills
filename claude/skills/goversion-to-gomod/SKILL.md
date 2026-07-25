---
description: 현재 repo에서 GOVERSION 파일 참조를 모두 go.mod 읽기 방식으로 교체하고, GOVERSION 파일을 삭제한다.
allowed_tools: [Bash, Read, Edit, Write, Glob, Grep]
disable-model-invocation: true
---

현재 repo에서 GOVERSION 파일 참조를 모두 go.mod 읽기 방식으로 교체하고, GOVERSION 파일을 삭제한다.

`go.mod` 에 `go` 버전 디렉티브가 없으면 작업을 중단하고 사용자에게 알린다.

## 교체 패턴

`GOVERSION` 파일을 읽는 모든 곳 — CI 워크플로·Dockerfile·Makefile·셸 스크립트 — 에서 그 읽기를
`go.mod` 의 `go` 디렉티브 읽기로 바꾼다. 값을 뽑는 표현은 `grep '^go ' go.mod | awk '{print $2}'`
를 쓴다. `go mod edit -json` 계열은 toolchain 줄까지 딸려 와 버전 문자열이 달라지므로 쓰지 않는다.

주변 코드의 형태(GITHUB_ENV 에 쓰든 셸 변수에 담든)는 원래 코드를 따라간다.

## 완료 기준

- `grep -rn 'GOVERSION' . --exclude-dir='.git'` 를 돌려 **파일을 읽는 곳이 하나도 남지 않았다** —
  `cat GOVERSION`, `$(<GOVERSION)`, `COPY GOVERSION`, `read < GOVERSION` 등. 하나라도 남았으면
  끝난 것이 아니다.
- **문자열 `GOVERSION` 자체는 남아도 된다. 변수명을 바꾸지 마라.** 환경변수·셸 변수 이름
  (`GOVERSION=`, `env.GOVERSION`)과 스텝 이름은 파일 참조가 아니다. 예전 기준은 이 grep 이
  통째로 비기를 요구했는데, 치환이 전부 옳게 끝나도 변수명 때문에 5줄이 남아 **만족이
  불가능했다.** 2026-07-26 실측에서 에이전트는 그 기준을 맞추려고 세 파일의 변수명을
  `GO_VERSION` 으로 리네임하고 CI 스텝 이름까지 고쳤다 — 아무도 요청하지 않은 변경이다.
  기준이 만족 불가능하면 모델은 멈추는 게 아니라 범위를 넓힌다.
- `GOVERSION` 파일이 삭제되었다.

변경된 파일과 교체 위치를 요약해 보고한다.
