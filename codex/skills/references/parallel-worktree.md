# worktree 위임·병렬 실행 절차

**이것은 스킬이 아니며 스스로 발동하지 않는다.** `$loop-backlog`이 ready set을 만들고,
`$lunamax-threads`가 worker transport·packet·재시도·검증 정책을 소유한다. 이 문서는 Git worktree,
태스크 상태, 순차 통합만 정의한다.

공통 backlog 전제는 [`backlog-basics.md`](backlog-basics.md)를 따른다.
`command -v backlog`가 실패하면 파일 손편집으로 폴백하지 말고 설치를 안내한 뒤 중단한다.

## 1. 후보와 실행 순서

1. 라운드마다 `backlog task list --plain`을 새로 읽는다.
2. In Progress를 먼저, 그다음 의존이 모두 Done인 To Do를 ready set에 넣는다. To Do마다
   `backlog task view <id> --plain`으로 Dependencies·Labels·AC를 확인하고 Blocked는 제외한다.
3. `solo` label은 worker 위임을 막지 않지만 다른 packet과 동시에 실행하지 않는다.

ready set을 우선순위와 의존 순으로 packet화한다. 한 기능의 구현과 테스트는 같은 worker가 완결한다.
관련 극소 작업은 한 packet으로 묶고, 포장이 실행보다 명백히 큰 작업만 Sol이 직접 한다.

## 2. 위임과 병렬 게이트

위임 여부와 병렬 여부를 분리한다.

- 닫힌 packet은 크기와 무관하게 `$lunamax-threads`로 위임한다.
- 상호 의존이 없고 write 소유 범위가 겹치지 않는 packet이 2개 이상이면 병렬 실행한다.
- 작업량·cold-start·예전 모델 비용은 병렬 게이트로 쓰지 않는다.
- Sol을 위한 슬롯 하나를 남기고 나머지 런타임 가용 슬롯을 모두 쓴다.
- 같은 생성물·lockfile·migration·공유 설정을 만지는 packet은 한 worker에 묶거나 직렬화한다.
- read-only packet끼리는 main cwd를 공유할 수 있다. writer packet은 아래 worktree를 사용한다.

## 3. Worktree 준비와 packet 소유권

writer packet마다 Sol이 base branch에서 별도 worktree와 branch를 만든다. 경로에는 태스크 ID를
영문·숫자·하이픈·언더스코어만 남겨 쓴다.

```text
MAIN_PATH=<base worktree 절대 경로>
BASE_BRANCH=<main 또는 master>
REPO_NAME=<저장소명>
TASK_ID=<task-2 또는 T-2>
TASK_SLUG=<경로 안전 ID>
WORKTREE=<MAIN_PATH>/../<REPO_NAME>__<TASK_SLUG>
BRANCH=task/<TASK_SLUG>_<짧은-slug>
```

생성 전에 `git -C "$MAIN_PATH" rev-parse --show-toplevel`과 현재 branch를 확인한다. packet의 cwd는
`WORKTREE`, ownership은 코드·테스트와 해당 태스크에 필요한 파일만 준다.

```bash
git -C "$MAIN_PATH" worktree add -b "$BRANCH" "$WORKTREE" "$BASE_BRANCH"
```

Luna packet에는 `$lunamax-threads`의 필수 필드와 다음 제약을 넣는다.

- 정의·참조·테스트를 먼저 읽고 구현한다.
- 허용 경로 밖 파일, AGENTS.md·README.md 같은 공용 메타 파일, 다른 태스크 파일을 수정하지 않는다.
- 관련 stack 검사와 AC를 실제 실행한다. `--no-verify` 같은 우회를 쓰지 않는다.
- 발견한 필수 선행·후속 작업은 구현 범위를 넓히지 말고 `RESULT.failure_context` 또는
  `remaining_risks`로 보고한다.
- 사용자에게 묻거나 PR·rebase·merge·push·worktree 정리를 하지 않는다.

backlog worker는 worktree에서 자기 태스크만 `In Progress`로 바꾸고, 완료 시 AC를 check하고 notes를
붙인 뒤 Done으로 바꾼다. 코드와 자기 태스크 파일을 `[{TASK_ID}] 요약` commit 하나에 담는다.

## 4. 회수와 위험 기반 검증

`$lunamax-threads`의 RESULT 형식을 회수하고 다음을 확인한다.

1. branch와 commit SHA가 실제 존재하는지 확인한다.
2. `git diff "$BASE_BRANCH"..."$BRANCH" --stat`과 전체 diff로 ownership 위반을 확인한다.
3. 저위험은 scope·diff·worker 로그, 중위험은 관련 코드 재독·핵심 검사 재실행, 고위험은 Sol 직접
   소유·negative test로 판정한다.
4. 작업 실패는 `$lunamax-threads` 규칙대로 한 번만 코칭 재시도하고, 다시 실패하면 Sol이 회수한다.

## 5. 순차 통합과 충돌

success branch만 태스크 순으로 한 건씩 통합한다. `git merge` 전에 cwd가 base branch worktree인지
반드시 확인한다.

```bash
git rev-parse --show-toplevel
git branch --show-current
```

base를 최신으로 맞춘 뒤 `merge-base --is-ancestor`로 fast-forward 가능성을 확인한다. 불가능하면 해당
worker worktree에서 base 위로 rebase한다. 충돌하면 `rebase --abort`하고 그 packet을 실패로 남긴 뒤
다음 태스크로 간다. 충돌을 Sol이 임의로 합쳐 worker 검증을 무효화하지 않는다.

가능한 branch는 base cwd에서 `git merge --ff-only`하고 설정된 remotes에 push한다. 성공 뒤에만
worktree를 제거하고 branch를 삭제한다. 실패 worktree·branch는 진단용으로 남긴다.

merge마다 main에서 `backlog task view <id> --plain`으로 Done·notes·AC를 확인한다.
worker가 빠뜨렸다면 Sol이 보정하고 해당 태스크 파일만 즉시 별도 commit·push한다.

실패 태스크는 To Do 를 유지하고 자동 실행 실패 증거를 notes·진행 로그에 남긴다. 사용자
결정이 필요한 경우에만 loop 스킬의 막힘 정책으로 Blocked 또는 `[!]`로 전이한다.

## 6. 라운드 마무리

모든 merge 뒤 ready set을 fresh 조회해 다음 라운드를 계속한다. 완료 정리는 loop 스킬의 임계치와
`$cleanup-backlog` 규칙을 따른다.

최종 보고에는 성공·실패·Blocked, merge된 태스크와 SHA, 남긴 worktree, 다음 후보를 적는다. 이어서
`$lunamax-threads`의 transport, packet 수, 최대 병렬도, Luna 재시도, Sol 회수, Terra fallback,
Sol이 실제 실행한 검증을 짧게 남긴다.
