---
name: lunamax-threads
description: Sol이 사용자 의도와 통합을 소유한 채 bounded 실행 packet을 Luna max thread에 위임한다. 사용자가 `$lunamax-threads`를 직접 호출하거나 `$loop-backlog`·`$loop-plan`이 ready set 실행 packet을 배분할 때만 사용한다.
---

# Luna Max Threads

Sol의 비싼 판단과 Luna max의 값싼 실행을 분리한다. 가능하면 오케스트레이터를 Sol xhigh로 두되,
현재 세션의 모델·effort가 다르다는 이유로 중단하거나 재시작하지 않는다.

OpenAI는 `gpt-5.6-luna`를 효율적인 고용량 작업용으로 안내한다. 현재 native V2 `spawn_agent`는
Luna를 거부하는 upstream 이슈가 열려 있으므로 catalog·바이너리를 패치하거나 native spawn을 probe하지
않는다. 공식 지원 발표 뒤에만 이 스킬을 수동 개정한다.

- 모델 근거: <https://developers.openai.com/api/docs/guides/latest-model>
- native spawn 상태: <https://github.com/openai/codex/issues/35097>

## 1. Sol과 Luna의 경계

Sol이 다음을 끝까지 소유한다.

- 사용자 의도·비범위·권한·설계·위험 판단
- packet 분해·의존 관계·소유 경계·동시성
- worktree 통합, rebase·merge·push·정리
- 위험 기반 재검증과 최종 답변

Luna에는 탐색·구현·테스트처럼 목표와 검증법이 닫힌 실행을 맡긴다. 고위험 변경의 결정과 최종
판정은 위임하지 않는다. Luna가 외부 게시, 파괴적 작업, 권한 확대, 범위 확대를 결정하게 하지 않는다.
막히면 사용자에게 직접 묻지 말고 `RESULT`에 반환하게 한다.

## 2. Lean packet 만들기

각 packet을 작고 자급자족하게 만든다. 다음 필드를 빠뜨리지 않는다.

```text
PACKET
id: <stable-id>
goal: <한 문장 목표>
non_goals: <하지 않을 일>
cwd: <절대 경로>
ownership: <수정 가능 파일·모듈 또는 read-only>
pointers: <먼저 읽을 파일·관련 정의·테스트>
acceptance: <완료 조건>
validation: <실제로 실행할 검사>
safety: <게시·파괴·권한·범위 경계>
result: 아래 RESULT 형식으로만 보고
```

관련 파일 전문이나 대화 전체를 넘기지 말고 포인터와 필요한 발췌만 준다. Luna가 다시 판단해야 할
모호한 요구는 보내기 전에 Sol이 닫는다.

packet이 작아도 포장이 명백히 실행보다 큰 극소 작업이 아니면 Luna에 우선 위임한다. 관련된 극소
작업은 한 packet으로 묶는다. 한 기능의 구현과 테스트를 쪼개지 말고 한 Luna가 완결하게 한다.

## 3. Transport 선택

아래 순서로 선택한다.

1. 현재 도구 목록에 모델과 effort를 지정해 Codex App의 최상위 thread 또는 task를 만드는 기능이
   이미 있으면 packet마다 `gpt-5.6-luna` + `max`로 만든다. native `spawn_agent`는 이 경로가 아니며
   Luna 지원 여부를 시험 호출하지 않는다. 작업 thread는 결과와 재시도까지 유지하고, 완료 뒤
   지원되는 완료·닫기 상태로 정리한다.
2. 그런 App 기능이 없거나 Luna thread 생성이 인프라 오류로 실패하면
   `scripts/run-worker.sh --model luna`로 ephemeral CLI worker를 띄운다. packet은 반드시 stdin으로
   전달한다. 스크립트는 `gpt-5.6-luna`·`max`를 고정하고 `multi_agent`·`multi_agent_v2`를 꺼 중첩
   위임과 V2 충돌을 막는다.
3. App과 CLI Luna 경로가 모두 모델 미지원·인증·서비스 장애 같은 인프라 오류로 불가능할 때만
   `scripts/run-worker.sh --model terra`로 `gpt-5.6-terra` + `high`를 사용한다. 테스트 실패나 packet
   자체의 실패는 인프라 오류가 아니므로 Terra로 바꾸지 않는다.

CLI 예시:

```bash
/absolute/path/to/lunamax-threads/scripts/run-worker.sh \
  --model luna \
  --cwd /absolute/packet/worktree \
  --sandbox workspace-write \
  --output /absolute/temp/result.txt \
  < /absolute/temp/packet.txt
```

실제로 load한 `SKILL.md`의 디렉터리를 기준으로 script 절대 경로를 해석한다.

read-only packet에는 `--sandbox read-only`, writer에는 `--sandbox workspace-write`를 쓴다. CLI worker는
항상 ephemeral이며 resume하지 않는다.

## 4. 위임과 병렬화를 따로 판단하기

위임 여부는 packet의 닫힘 정도로, 병렬 여부는 독립성과 write 안전성으로 판단한다.

- 독립 packet이 2개 이상이고 write 충돌이 없으면 크기와 무관하게 병렬 실행한다.
- Sol을 남겨 두고 런타임의 나머지 가용 슬롯을 모두 사용한다.
- read-only worker끼리는 같은 cwd를 공유해도 된다.
- writer 하나만 실행하면 그 cwd를 독점시킨다. Git 태스크처럼 worker commit이 필요한 작업은 단일
  writer여도 격리 worktree를 우선한다.
- writer를 병렬 실행하면 packet마다 별도 worktree·브랜치를 Sol이 준비해 cwd와 소유 범위로 준다.
- 생성물·lockfile·migration·공유 설정을 함께 만지는 packet은 한 worker에 묶거나 직렬화한다.
- `solo` label 또는 `단독실행: 필요`는 위임 금지가 아니라 동시 실행 금지다. 해당 packet만 단독으로
  실행한다.

backlog·PLAN worktree 생성, 태스크별 commit, 순차 통합 규칙은
[`../references/parallel-worktree.md`](../references/parallel-worktree.md)를 따른다.

## 5. RESULT 회수

모든 worker에 다음 형식을 강제한다.

```text
RESULT
packet_id: <id>
status: success | failed
changed_files: <없음 또는 경로 목록>
commit: <없음 또는 sha>
checks: <이번 worker가 실제 실행한 명령과 결과>
remaining_risks: <없음 또는 위험>
failure_context: <없음 또는 실패 증거·막힌 판단>
```

실행하지 않은 검사를 통과로 적지 못하게 한다. writer는 허용 범위만 수정하고 검증한 뒤, 격리
worktree를 쓴 Git 태스크라면 태스크 단위 commit까지 만든다. rebase·merge·push·worktree 정리는
하지 못하게 한다.

## 6. 실패와 검증

작업 실패에는 증거를 붙여 딱 한 번 코칭 재시도한다.

- App thread: 같은 thread에 실패 증거와 교정 지시를 보낸다.
- CLI: 원 packet과 실패 증거를 포함한 새 ephemeral worker를 띄운다.
- 두 번째 실패 또는 packet 밖 판단 필요: Sol이 회수한다.

Luna의 자기보고를 그대로 믿지 말고 위험에 맞춰 검증한다.

- 저위험: scope·diff·실행 로그를 확인한다.
- 중위험: 관련 코드를 다시 읽고 핵심 검사를 Sol이 재실행한다.
- 고위험: 결정과 구현을 Sol이 직접 소유하고 negative test까지 수행한다.

## 7. 최종 보고

별도 지속 로그를 만들지 않는다. 매 실행의 최종 답변에 다음을 한 줄 또는 짧은 목록으로 남긴다.

```text
Luna delegation: transport=<app-thread|cli-ephemeral|mixed|terra-fallback>, packets=<N>,
max_parallel=<N>, retries=<N>, sol_takeovers=<N>, terra_fallbacks=<N>, verification=<실제 검사>
```
