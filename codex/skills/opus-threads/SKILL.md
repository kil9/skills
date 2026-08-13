---
name: opus-threads
description: Codex가 사용자 의도와 통합을 소유한 채 어려운 bounded 실행 packet을 HERDR의 Claude Code Opus worker에 위임한다. 사용자가 `$opus-threads`를 직접 호출하거나 `$loop-backlog`이 ready set의 고난도 packet을 배분할 때만 사용하며, Claude 구독 사용량을 확인해 동시성을 제한한다.
---

# Opus Threads

Codex의 판단과 Claude Opus의 독립 실행을 분리한다. Opus는 어려운 디버깅, 넓은 refactor, 설계 검토처럼
깊은 추론이 이득인 packet에 쓴다. 기계적 수정과 짧은 반복에는 Codex가 직접 처리하거나 Luna를 쓴다.

먼저 `$herdr`를 load하고 그 명령·안전 규칙을 따른다. 이 스킬은 `HERDR_ENV=1`인 세션만 지원한다.

## 0. 사용량 gate

batch마다 worker를 만들기 전에 다음을 실행한다. 실제로 load한 `SKILL.md`의 디렉터리를 기준으로 script
절대 경로를 해석한다.

```bash
/absolute/path/to/opus-threads/scripts/check-usage.sh --cwd /absolute/trusted/cwd
```

이 script는 `claude auth status`로 과금 경로를 확인하고, 구독 로그인이면 screen-reader Claude pane에서
공식 `/usage`를 열어 current session과 current week (all models)를 읽는다. 검사 pane은 결과를 출력한 뒤
닫는다. exit code가 0이 아니거나 `status`가 `ok`가 아니면 값을 읽지 못한 것으로 취급한다.

- `auth_method=claude.ai`와 구독 종류가 확인된 때만 자동 위임한다.
- API key·Bedrock·Vertex·Foundry 등 PAYG 경로이면 명시적인 비용 승인 없이 worker를 만들지 않는다.
- 둘 중 높은 사용률이 50% 미만이면 독립 worker를 최대 3개 실행한다.
- 하나라도 50-74%이면 worker를 최대 1개 실행한다.
- 하나라도 75% 이상이거나 값을 읽지 못하면 새 worker를 만들지 않고 Codex가 회수한다.
- batch가 끝날 때마다 다시 확인한다. worker가 limit 경고를 내면 즉시 재확인한다.
- usage credit 활성화, API key fallback, 결제 설정 변경을 자동으로 승인하지 않는다.

이 50%·75% 경계는 Anthropic의 product limit이 아니라 burst와 남은 작업을 위한 이 스킬의 보수적
headroom 정책이다. Claude 웹·Desktop·Code 사용량이 같은 구독 limit을 공유하고 Opus가 Sonnet보다
quota를 더 많이 쓰므로, packet 수보다 남은 두 limit 중 작은 쪽을 우선한다.

근거:

- `/usage`와 인증별 과금: <https://support.claude.com/en/articles/14552983-models-usage-and-limits-in-claude-code>
- 공유 limit과 API key override: <https://support.claude.com/en/articles/11145838-use-claude-code-with-your-pro-or-max-plan>
- usage·context limit 구분: <https://support.claude.com/en/articles/11647753-how-do-usage-and-length-limits-work>

## 1. Codex와 Opus의 경계

Codex가 다음을 소유한다.

- 사용자 의도·비범위·권한·설계·위험 판단
- packet 분해·의존·소유 경계·동시성
- worktree 준비, rebase·merge·push·정리
- 결과 검증과 최종 답변

Opus에는 탐색·구현·테스트처럼 목표와 검증법이 닫힌 실행을 맡긴다. 외부 게시, 파괴적 작업, 권한·범위
확대, 결제 변경을 결정하게 하지 않는다. Claude worker가 자체 subagent나 `/subtask`를 만들지 못하게
packet에 명시한다. 막히면 사용자에게 묻지 말고 `RESULT`로 반환하게 한다.

## 2. 모델·effort 선택

- bounded 구현·리뷰는 `--model opus --effort medium`을 기본으로 한다.
- 원인 불명 디버깅·설계·보안 재검증은 `high` 또는 `xhigh`를 쓴다.
- `max`는 사용자가 명시하거나, xhigh로도 실패한 단일 고난도 packet을 재시도할 때만 쓴다.
- 같은 기능의 구현과 테스트를 한 worker가 완결하게 한다. unrelated packet은 새 pane으로 분리해 이전
  대화와 context를 재전송하지 않는다.

## 3. Lean packet 만들기

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
safety: <게시·파괴·권한·범위·과금 경계>
result_file: <절대 경로>
worker_rules: 사용자에게 묻지 말 것, subagent를 만들지 말 것, 아래 RESULT만 파일에 쓸 것
```

대화 전체나 파일 전문을 넘기지 말고 경로와 필요한 발췌만 준다. 모호한 요구는 Codex가 닫은 뒤 보낸다.

## 4. HERDR transport

packet마다 별도 result file과 고유한 소문자 agent name을 준비한다. worker pane은 다음 순서로 만든다.

```bash
PANE_ID=$(herdr pane split --current --direction right --no-focus --cwd /absolute/packet/cwd \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["pane"]["pane_id"])')

herdr agent start <agent-name> --kind claude --pane "$PANE_ID" -- \
  --model opus --effort medium --ax-screen-reader --dangerously-skip-permissions

herdr agent prompt <agent-name> "<PACKET text>" --wait --timeout 600000
```

`pane split` 직후 `agent start`가 `agent_pane_busy`를 반환하면 pane 화면이 shell prompt인지 확인하고
0.2초 뒤 딱 한 번만 같은 start를 재시도한다. 그 밖의 start 실패는 재시도하지 않는다. 2026-08-09
HERDR 0.8.0에서 새 shell의 readiness race로 이 오류가 한 번 재현됐다.

`--dangerously-skip-permissions`는 무인 tool 실행에 필요하므로 packet의 권한과 worktree 격리를 좁게 잡는다.
folder trust가 막히면 자동 승인하지 않는다. 화면과 `cwd`를 확인해 신뢰 가능한 repo임이 확실할 때만
승인한다. 결제, usage credit, 외부 게시, 파괴적 명령 prompt는 승인하지 않는다.

결과는 pane 화면이 아니라 `result_file`에서 읽는다. 실패 증거로 딱 한 번 코칭할 때는 같은 agent에
`herdr agent prompt ... --wait`를 다시 보내 context를 유지한다. 종료 후에는 Codex가 만든 pane만 명시적
ID로 닫는다.

## 5. 위임과 병렬화

- 사용량 gate가 허용한 수와 독립 packet 수 중 작은 값만 동시에 실행한다.
- read-only worker끼리는 같은 cwd를 공유해도 된다.
- writer 하나는 cwd를 독점한다. Git 변경은 단일 writer도 격리 worktree를 우선한다.
- writer를 병렬 실행하면 packet마다 별도 worktree·브랜치와 비겹치는 ownership을 준다.
- lockfile·migration·생성물·공유 설정을 함께 만지면 한 worker에 묶거나 직렬화한다.
- worker는 commit이 명시된 packet만 commit한다. rebase·merge·push·worktree 정리는 하지 않는다.

backlog·PLAN 작업의 worktree와 통합은 호출한 backlog 스킬의 규칙을 따른다.

## 6. RESULT와 검증

```text
RESULT
packet_id: <id>
status: success | failed
changed_files: <없음 또는 경로 목록>
commit: <없음 또는 sha>
checks: <실제로 실행한 명령과 결과>
remaining_risks: <없음 또는 위험>
failure_context: <없음 또는 실패 증거·막힌 판단>
```

실행하지 않은 검사를 통과로 적지 못하게 한다. 자기보고를 그대로 믿지 않는다.

- 저위험: scope·diff·실행 로그를 확인한다.
- 중위험: 관련 코드를 다시 읽고 핵심 검사를 Codex가 재실행한다.
- 고위험: 결정은 Codex가 소유하고 negative test까지 수행한다.
- 첫 실패: 같은 Claude pane에 증거와 교정 지시를 한 번 보낸다.
- 두 번째 실패, limit 도달, packet 밖 판단 필요: Codex가 회수한다.

## 7. 최종 보고

별도 지속 로그를 만들지 않는다. 최종 답변에 다음을 짧게 남긴다.

```text
Opus delegation: usage=session <N>%, weekly <N>%, packets=<N>, max_parallel=<N>,
effort=<levels>, retries=<N>, codex_takeovers=<N>, verification=<실제 검사>
```
