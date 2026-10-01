# herdr pane 워커 모드 (배관 상세)

`parallel-worktree.md` 의 opt-in 경로 전용이다. 사용자가 명시적으로 herdr pane 을 지시했을 때만 읽는다 —
기본 경로(팀/서브에이전트)로 도는 대부분의 실행에서는 필요 없다. 트리거 조건은 `parallel-worktree.md` 본문에 있다.

태스크 선별·프롬프트 내용·머지 로직은 동일하고 워커 실행 배관만 바뀐다:

- 스폰·대기는 `/herdr` 스킬의 레시피를 따른다. **herdr 0.7.5 에서 원스텝 `agent start` 가 없어져 세 스텝이다**(2026-08-04 herdr 0.8.0 재실측, task-175). 각 스텝의 함정은 `/herdr` 쪽에 있으니 벗어나기 전에 그걸 읽을 것:

  ```bash
  PID=$(herdr pane split --current --direction right --no-focus --cwd {MAIN_PATH} \
    | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"]["pane"]["pane_id"])')
  herdr agent start {WORKER} --kind claude --pane "$PID" \
    -- --model opus --effort {LEVEL} --dangerously-skip-permissions
  herdr agent prompt {WORKER} "<프롬프트>" --wait --timeout 1800000   # 원자적 제출 + 대기
  ```

  `agent prompt --wait` 는 background Bash 로 돌려 폴링 없이 종료 통지를 받는다. **`--until` 로 좁히지 말 것** — 무인자 `--wait` 가 이미 idle·done·blocked 를 다 잡는다. `idle` 로 좁히면 안 본 pane 은 `done` 에 앉아 영영 안 맞고, `blocked`(권한 프롬프트)도 놓쳐 타임아웃까지 매달린다.

  0.8.0 에서 네 스텝이 세 스텝이 됐다. **재시도 루프**는 `agent start` 가 pane 의 인터랙티브 준비를 스스로 기다리게 되어(`--timeout`, 기본 30초) 불필요해졌고, **`--until working` 선대기**는 해로워졌다(`agent start` 가 준비 완료 시점에 반환해 짧은 태스크는 그 전에 끝나 있으므로 working 전이가 영영 안 온다 — 실측 60초 통째 타임아웃). 그리고 **프롬프트 제출과 대기가 `agent prompt --wait` 한 줄로 합쳐졌다**.
- **프롬프트는 `agent prompt` 로 넣는다 — `pane run` 이 아니다.** 0.8.0 의 `agent prompt` 는 텍스트와 Enter 를 원자적으로(bracketed-paste 인지) 제출한다(2026-08-04 실측: `--wait` 가 11초 만에 결과 파일까지 확인됨). 반면 `pane run` 은 claude TUI 에 넣을 때 Enter 를 삼켜 텍스트만 입력창에 남기는 것이 관측됐고(같은 날 1회, 이후 동일 시도에서는 재현 안 됨 — 확률적이다), 그때 워커는 영원히 idle 이다. argv 로 첫 프롬프트를 넘기는 옛 방식도 여전히 유효하다.
- **`--effort` 를 명시한다.** 이 경로는 effort 를 실제로 고를 수 있는 몇 안 되는 자리다(Agent 도구엔 노브가 없다). 값은 글로벌 지침의 effort 정책 절 기준으로 태스크마다 고른다 — 기본 `medium`, 설계 판단·원인 불명 디버깅·보안 재검증이면 `high`, 기계적 변환이면 `low`. 안 주면 그 머신 전역값을 탄다. 먹었는지는 pane 배너(`Opus 5 with medium effort`)로 확인된다.
- 리드가 ccs 프로필로 돌고 있으면(`CLAUDE_CONFIG_DIR` 설정됨) `pane split` 에 `--env CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR"` 를 준다. herdr 서버 env 에는 프로필이 없어, 안 실으면 워커가 base 계정 쿼터를 태운다.
- RESULT 블록은 SendMessage 대신 파일로 회수한다: 프롬프트에 repo 밖 결과 파일 경로(리드 scratchpad 하위 `{TASK_SLUG}.result.md`)를 명시하고 완료 후 그 파일을 읽는다. `pane read` 는 진행 확인용으로만(최종 답변은 TUI 가 접어 못 읽는 경우가 잦다).
- 실패 코칭 주입도 같은 경로다: `herdr agent prompt {WORKER} "<지시>" --wait --timeout <MS>` 후 같은 결과 파일을 재확인한다. 제출에서 5초 안에 상태 변화가 없으면 `agent_prompt_stalled` 가 나므로 무응답을 조용히 기다리는 일이 없다.
- 머지·보고까지 끝난 pane 은 `herdr pane close <pane_id>` 로 닫는다(`agent stop` 커맨드는 없음). 실패·블록 태스크의 pane 은 worktree 와 함께 사용자 진단용으로 남긴다.
