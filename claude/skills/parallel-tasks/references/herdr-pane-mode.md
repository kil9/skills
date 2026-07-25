# herdr pane 워커 모드 (배관 상세)

`/parallel-tasks` 의 opt-in 경로 전용이다. 사용자가 명시적으로 herdr pane 을 지시했을 때만 읽는다 —
기본 경로(팀/서브에이전트)로 도는 대부분의 실행에서는 필요 없다. 트리거 조건은 SKILL.md 본문에 있다.

태스크 선별·프롬프트 내용·머지 로직은 동일하고 워커 실행 배관만 바뀐다:

- 스폰·대기는 `/herdr` 스킬의 레시피를 따른다. **herdr 0.7.5 에서 원스텝 `agent start` 가 없어져 네 스텝이다**(2026-07-25 실측, task-175). 각 스텝의 함정은 `/herdr` 쪽에 있으니 벗어나기 전에 그걸 읽을 것:

  ```bash
  PID=$(herdr pane split --current --direction right --no-focus --cwd {MAIN_PATH} \
    | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"]["pane"]["pane_id"])')
  for i in 1 2 3; do                                     # split 직후엔 실패한다 — 재시도가 답
    herdr agent start {WORKER} --kind claude --pane "$PID" \
      -- --model opus --effort {LEVEL} --dangerously-skip-permissions \
      "<프롬프트>" && break                              # 프롬프트는 argv 로 넘긴다
  done
  herdr agent wait {WORKER} --until working --timeout 60000
  herdr agent wait {WORKER} --timeout 1800000            # --until 없이 (idle·done·blocked)
  ```

  마지막 대기는 background Bash 로 돌려 폴링 없이 종료 통지를 받는다. **`--until idle` 로 좁히지 말 것** — 안 본 pane 은 `done` 에 앉아 `idle` 에 영원히 안 오고, 좁히면 `blocked`(권한 프롬프트)도 놓쳐 타임아웃까지 매달린다.
- **프롬프트를 `pane run` 으로 따로 밀어넣지 말 것.** 기동 직후엔 Enter 가 먹히지 않아 텍스트만 입력창에 남고 워커가 영원히 idle 이다(2026-07-25 실측: working 대기가 60초 통째로 타임아웃, `agent send-keys <name> Enter` 한 번에 즉시 실행됨). `pane run` 은 워커가 한 턴 돌고 난 뒤에는 정상 제출하므로 **실패 코칭 주입 전용**으로 쓴다.
- **`--effort` 를 명시한다.** 이 경로는 effort 를 실제로 고를 수 있는 몇 안 되는 자리다(Agent 도구엔 노브가 없다). 값은 글로벌 지침의 effort 정책 절 기준으로 태스크마다 고른다 — 기본 `medium`, 설계 판단·원인 불명 디버깅·보안 재검증이면 `high`, 기계적 변환이면 `low`. 안 주면 그 머신 전역값을 탄다. 먹었는지는 pane 배너(`Opus 5 with medium effort`)로 확인된다.
- 리드가 ccs 프로필로 돌고 있으면(`CLAUDE_CONFIG_DIR` 설정됨) `pane split` 에 `--env CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR"` 를 준다. herdr 서버 env 에는 프로필이 없어, 안 실으면 워커가 base 계정 쿼터를 태운다.
- RESULT 블록은 SendMessage 대신 파일로 회수한다: 프롬프트에 repo 밖 결과 파일 경로(리드 scratchpad 하위 `{TASK_SLUG}.result.md`)를 명시하고 완료 후 그 파일을 읽는다. `pane read` 는 진행 확인용으로만(최종 답변은 TUI 가 접어 못 읽는 경우가 잦다).
- 실패 코칭 주입도 `herdr pane run <pane_id> "<지시>"` 로 한다. 이후 다시 `--until working` → bare wait → 같은 결과 파일 재확인.
- 머지·보고까지 끝난 pane 은 `herdr pane close <pane_id>` 로 닫는다(`agent stop` 커맨드는 없음). 실패·블록 태스크의 pane 은 worktree 와 함께 사용자 진단용으로 남긴다.
