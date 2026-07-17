---
name: goversion-to-gomod
description: 현재 repo에서 GOVERSION 파일 참조를 모두 go.mod 읽기 방식으로 교체하고, GOVERSION 파일을 삭제한다.
---

현재 repo에서 GOVERSION 파일 참조를 모두 go.mod 읽기 방식으로 교체하고, GOVERSION 파일을 삭제한다.

`go.mod` 에 `go` 버전 디렉티브가 없으면 작업을 중단하고 사용자에게 알린다.

## 교체 패턴

CI 워크플로·Dockerfile·Makefile·셸 스크립트 등 `GOVERSION` 파일을 읽는 모든 곳에 적용한다.

### 패턴 A — GITHUB_ENV에 쓰는 경우
```yaml
# Before
- name: Read GOVERSION from repo
  run: |
    echo "GOVERSION=$( cat GOVERSION )" >> $GITHUB_ENV

# After
- name: Read Go version from go.mod
  run: |
    echo "GOVERSION=$(grep '^go ' go.mod | awk '{print $2}')" >> $GITHUB_ENV
```

### 패턴 B — 셸 변수에 할당하는 경우
```bash
# Before
GOVERSION=$(cat GOVERSION)

# After
GOVERSION=$(grep '^go ' go.mod | awk '{print $2}')
```

## 완료 기준

- `grep -r GOVERSION . --exclude-dir='.git'` 결과가 비어 있다 — 참조가 하나라도 남았으면 끝난 것이 아니다.
- `GOVERSION` 파일이 삭제되었다.

변경된 파일과 교체 위치를 요약해 보고한다.
