---
name: eval-codex
description: Codex 평가 하네스를 고정 데이터셋으로 반복 실행하고 solve rate·회귀·개입·시간·토큰을 비교한다. "Codex eval / 하네스 비교 / 설정·프롬프트 전후 평가" 요청에 사용한다.
---

저장소의 평가 manifest와 runner를 단일 진실 공급원으로 사용한다. 범용 benchmark를 새로 만들거나
결과가 안정되기 전에 자동화하지 않는다.

## 1. 평가 계약 확인

repo 지침과 eval README를 읽고 manifest validator를 실행한다. 각 case에 outcome, context, constraints,
verification, targeted grader, regression grader가 모두 있고 fixture가 비밀·운영 데이터를 포함하지
않아야 한다. 이 조건이 전부 확인돼야 실행으로 넘어간다.

## 2. 비교 실행

비교할 revision, model, reasoning effort, sandbox, 반복 수를 먼저 고정한다. repo runner로 같은 case를
각 조건에서 같은 횟수만큼 실행한다. runner가 detached worktree, ephemeral JSONL, 환경 정보, grader
결과를 남기지 않으면 임의 명령으로 대신하지 말고 하네스를 고친다. 모든 반복의 `result.json`이
생겨야 완료다.

## 3. targeted와 regression 판정

runner의 summarize 기능으로 solve rate, 사람 개입, median wall time, tokens, 명시적 rate가 있을 때의
cost를 비교한다. targeted가 개선돼도 regression이 깨지면 실패다. 실패 trace는 redacted JSONL과
grader 출력으로 재현 가능해야 한다. 모든 결과가 같은 dataset schema와 환경 필드를 가져야 완료다.

## 4. hill-climbing 승격

반복되고 검토된 실패만 새 eval target으로 승격한다. deterministic grader와 bounded writable fixture가
없는 사례, 판단이 모호한 사례, 1회성 noise는 자동화하지 않고 사람 검토로 돌린다. 안정된 반복 절차만
skill이나 check gate로 승격하며, 결과 요약에는 채택·기각 근거를 함께 남긴다.
