# worktree 병렬 배관 (참조 문서)

**이것은 스킬이 아니다.** 병렬로 갈지는 `/start-backlog` 가 판단하고, 가기로 했을 때의 기계적 절차만
여기 있다. 공통 전제는 [`backlog-basics.md`](backlog-basics.md).

## 워커에게 줄 것

`MAIN_PATH`·`BASE_BRANCH`·`REPO_NAME`·`TASK_ID`·`backlog task view <TASK_ID> --plain` 발췌·경로안전
`TASK_SLUG`(영문/숫자/`-`/`_` 외는 `_`)를 넣고 다음을 지시한다.

- worktree: `git -C {MAIN_PATH} worktree add -b task/{TASK_SLUG}_{slug} {MAIN_PATH}/../{REPO_NAME}__{TASK_SLUG} {BASE_BRANCH}`,
  이후 모든 git 은 `git -C <worktree>`.
- **수정 범위는 코드 + 자기 태스크 파일(`backlog/tasks/task-<id>*.md`)뿐.** 상태·AC·notes 는 worktree
  안에서 CLI 로 바꾸고 같은 커밋에 넣는다. 다른 태스크 파일·AGENTS.md 같은 메타 파일은 건드리지 않는다
  (리드가 머지 때 처리) — 그래야 머지 때 태스크 파일 충돌이 구조적으로 없다.
- 커밋은 `[{TASK_ID}] 요약`. `--no-verify` 금지, PR 금지, worktree 를 스스로 정리하지 않는다.
- 막히면 사용자가 아니라 리드에게 묻는다.
- **끝나면 RESULT 블록**(`task`/`status`(success|failed)/`branch`/`worktree`/`commit`/`checks`/
  `failure_context`)을 `SendMessage(to: "main")` 으로 보낸다. `checks` 에는 실제로 돌린 명령과 결과만
  적는다. **이 지시를 빼면 named 팀원의 최종 텍스트가 리드에 도달하지 않는다**(task-167 실사고).

`solo` label 태스크는 워커에게 주지 않고 머지가 끝난 뒤 리드가 처리한다. 같은 파일을 건드릴 태스크들은
한 워커에 묶어 직렬화한다.

## 머지 (리드 단독 · 순차)

1. 브랜치·커밋 SHA 가 실제로 있는지 확인한다(자기보고를 믿지 않는다).
2. base ff-pull → `merge-base --is-ancestor` 로 ff 가능 확인, 불가면 worktree 에서 rebase. 태스크 파일 외
   충돌이면 `rebase --abort` 하고 그 태스크는 보류.
3. cwd 가 base 브랜치 디렉터리인지 확인 후 `merge --ff-only` → push → worktree remove + 브랜치 삭제.
4. 메인에서 `backlog task view <id> --plain` 으로 Done·AC·notes 를 확인하고, 빠졌으면 보정해 바로 커밋·push.

실패 태스크는 머지하지 않고 worktree·브랜치를 진단용으로 남긴다. 상태는 To Do 로 두고 사유를
`--append-notes` 로 적는다.
