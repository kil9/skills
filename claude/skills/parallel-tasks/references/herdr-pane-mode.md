# herdr pane 워커 모드 (배관 상세)

`/parallel-tasks` 의 opt-in 경로 전용이다. 사용자가 명시적으로 herdr pane 을 지시했을 때만 읽는다 —
기본 경로(팀/서브에이전트)로 도는 대부분의 실행에서는 필요 없다. 트리거 조건은 SKILL.md 본문에 있다.

태스크 선별·프롬프트 내용·머지 로직은 동일하고 워커 실행 배관만 바뀐다:

- 스폰·대기는 `/herdr` 스킬(auto-memory `herdr-orchestration` 검증판) 레시피를 따른다: `herdr agent start <name> --workspace "$HERDR_WORKSPACE_ID" --tab "$HERDR_TAB_ID" --split right --no-focus --cwd {MAIN_PATH} -- claude --model opus --dangerously-skip-permissions "<프롬프트>"`. 완료 대기는 background Bash 의 `herdr agent wait <name> --status idle`(done 대기 금지).
- 리드가 ccs 프로필로 돌고 있으면(`CLAUDE_CONFIG_DIR` 설정됨) `-- env CLAUDE_CONFIG_DIR="$CLAUDE_CONFIG_DIR" claude ...` 로 전파한다. herdr 서버 env 에는 프로필이 없어, 안 실으면 워커가 base 계정 쿼터를 태운다.
- RESULT 블록은 SendMessage 대신 파일로 회수한다: 프롬프트에 repo 밖 결과 파일 경로(리드 scratchpad 하위 `{TASK_SLUG}.result.md`)를 명시하고 idle 후 그 파일을 읽는다. `pane read` 는 진행 확인용으로만(최종 답변은 TUI 가 접어 못 읽는 경우가 잦다).
- 실패 코칭 주입은 `herdr pane run <pane_id> "<지시>"` 로 한다(`herdr agent send` 는 Enter 미제출). 이후 다시 idle 대기 → 같은 결과 파일 재확인.
- 머지·보고까지 끝난 pane 은 `herdr pane close <pane_id>` 로 닫는다(`agent stop` 커맨드는 없음). 실패·블록 태스크의 pane 은 worktree 와 함께 사용자 진단용으로 남긴다.
