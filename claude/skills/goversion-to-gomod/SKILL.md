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
- **문자열 `GOVERSION` 자체는 남아도 된다.** 환경변수·셸 변수 이름(`GOVERSION=`, `env.GOVERSION`)과
  스텝 이름은 파일 참조가 아니다 — 이 grep 이 비기를 기대하면 영원히 끝나지 않는다(2026-07-26
  실측: 치환이 전부 옳게 끝난 상태에서도 변수명 때문에 5줄이 남는다).
- `GOVERSION` 파일이 삭제되었다.

변경된 파일과 교체 위치를 요약해 보고한다.
