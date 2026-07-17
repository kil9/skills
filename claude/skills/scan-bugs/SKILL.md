---
description: 코드베이스 전체(또는 지정 범위)에 잠재된 버그를 4개 차원 병렬 서브에이전트로 탐색하고, Critical/High를 직접 코드로 재검증해 BUG_REPORT.html을 생성한다.
allowed_tools: [Bash, Read, Glob, Grep, Write, Edit, Agent, TaskCreate, TaskUpdate, TaskList]
---

전체 코드베이스(`$ARGUMENTS` 가 디렉토리/파일 경로면 그 범위로 제한)에 잠재된 버그를 찾아 `BUG_REPORT.html` 로 정리한다. 아래 단계들을 `TaskCreate` 로 등록해 진행 상태를 갱신한다.

## 1. 코드베이스 파악

`README.md`/`AGENTS.md`/`CLAUDE.md` 가 있으면 먼저 읽어 도메인·아키텍처를 파악한다. 핵심 코드 약 5,000 라인 이하면 핵심 파일 전부를 `Read` 로 직접 정독하고, 그 이상이면 진입점·인증·라우팅·핵심 도메인 모듈만 정독하고 나머지는 `Agent(Explore)` 요약으로 대체한다. 약 10,000 라인을 넘으면 사용자에게 알리고 핵심 영역부터 진행한다. 정독 중 의심스러운 패턴은 메모해 뒀다가 서브에이전트 프롬프트의 "특별히 봐달라" 항목으로 전달한다.

**솔로 게이트**: 범위가 사소하면(파일 1\~2개·수백 라인 수준) 서브에이전트를 띄우지 않는다. 멀티에이전트는 토큰을 단일 대비 3\~10배 쓰는데, 이 규모면 메인이 이미 전체를 정독한 상태라 이득이 없다. 메인이 아래 4개 차원 관점을 직접 적용해 발견을 뽑고, 그 사실을 한 줄 보고한 뒤 3단계부터 동일하게 진행한다.

## 2. 4개 차원 병렬 스폰

**한 메시지에 4개 Agent 를 동시 호출**한다 (병렬 실행).

- `review-security` — 인증 우회, 시크릿 노출, SQLi/XSS/CSRF, timing attack, 헤더 스푸핑, CORS, 로그 민감정보, 하드코딩
- `review-logic` — NPE, race, 에러 처리 누락, off-by-one, 리소스 누수, defer 생명주기, 응답 미발송, 타입 단언
- `review-performance` — 메모리 적재, blocking I/O, 메트릭 카디널리티, 정규식 매번 컴파일, goroutine leak, lock contention, 타임아웃
- `review-cleancode` — SRP 위반, 중복, 네이밍, 매직 넘버, 깊은 중첩 (잠재 버그로 이어질 수 있는 것만)

각 프롬프트에 포함할 것: "PR diff 리뷰가 아니라 코드베이스 전체 리뷰다. 모든 파일을 새 PR 이라 가정하고 검토하라" + 저장소 경로, 서비스 목적(1\~2문장), 운영 환경(nginx 뒤/K8s 등), 검토 대상 파일 목록, "특별히 봐달라" 항목(5\~15개), 발견 형식(파일:라인 / severity(Critical\~Info) / 트리거 시나리오 / 권장 수정안 / 짧은 코드 인용), "false positive 두려워 말고 의심나는 것 다 보고하라".

## 3. 통합 · 라이브러리 사실 확인

- **재검증 전에 먼저 통합한다**: 4개 차원 결과에서 같은 파일:라인·같은 원인 항목을 하나로 합치고 severity 는 최고치를 취한다. 재검증은 항목당 코드 재독이 필요한 비싼 단계라, 중복 제거를 먼저 해야 같은 결함을 두 번 검증하지 않는다.
- 외부 라이브러리 동작에 의존하는 항목은 기억으로 판정하지 말고 **라이브러리 소스를 직접 읽어** 확인한다(`go env GOMODCACHE`/`GOPATH` 등으로 소스 위치 파악). 예: defer/Close 생명주기, `gin.Context` 타입 단언, 헤더 Set/Add 시맨틱, multipart Open 의 메모리 vs tmpfile.
- 운영 환경 가정(nginx 뒤? K8s?)에서 실제로 reachable 한 경로인지도 코드로 확인한다.

## 4. Critical/High 재검증 — 이 스킬의 핵심

방법론(인플레 현상·유지/격하/제거 기준·진행 표시 형식)은 같은 디렉터리의
**[`severity-reverify.md`](severity-reverify.md) 가 정본이다.** 읽고 그대로 따른다 —
diff·PR 딥리뷰 스킬과 공유하므로 여기 옮겨 적지 않는다.

이 스킬 고유: 격하·제거 항목은 §5 의 BUG_REPORT.html 재검증 매트릭스에 사유와 함께 보존한다.

## 5. BUG_REPORT.html 작성 · 최종 보고

`Write` 로 저장소 루트(범위가 디렉토리면 그 안)에 생성한다. **재검증된 severity 기준**으로 정리하되 1차 발견과의 변화를 보여준다. 한국어로 작성.

섹션 순서: ① severity 카운트 헤더(Critical/High/Medium/Low/제거) ② Critical 즉시 수정 목록(최대 5개) ③ 재검증 매트릭스 표(ID·1차·재검증·요약·사유, 격하·제거 포함) ④ severity 순 ToC ⑤ 항목 카드(코드 인용 5\~15줄, 영향/시나리오/수정안, 유지=초록·격하=노랑·제거=빨강 재검증 박스, 격하 시 `was Critical` 칩) ⑥ 제거 항목과 사유 ⑦ 직접 검증한 라이브러리 사실(파일:라인 인용) ⑧ 최종 우선순위.

스타일: 시스템 폰트, 단일 컬럼 `max-width: 1080px`, severity 색 Critical `#d70015` / High `#ff6a00` / Medium `#b88600` / Low `#1f6feb` / 제거 `#007a33`, 코드 블록은 옅은 회색 배경.

사용자 보고는 짧게: 보고서 경로, 재검증 후 severity 카운트, Critical 전부 한 줄씩(제목+파일:라인), 격하·제거 카운트. HTML 보고서 외 PR/이슈/코멘트는 만들지 않는다(명시 요청 시에만).
