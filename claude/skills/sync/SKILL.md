---
description: 현재 브랜치를 리모트와 동기화한다(pull rebase 우선 + 모든 리모트 push). 워킹트리가 dirty 면 동기화 후 변경을 커밋하고 다시 push 한다.
allowed_tools: [Bash, Read, Edit, Write, Glob, Grep]
---

먼저 `git status --porcelain` 로 dirty 여부를 확인해 기억한다(2단계 진행 조건). 그다음:

1. **동기화**: `sync-repo.sh` 실행 — `pull --rebase --autostash` 후 현재 브랜치를 모든 리모트에
   push. 사전 조사 없이 stash·pull·push 를 스크립트가 처리한다.

   ```
   bash ~/.claude/skills/sync/sync-repo.sh
   ```

   - **dirty 인데 behind > 0 이면 autostash 가 안전한지 먼저 본다.** `--autostash` 는 소유권을
     안 가리고 워킹트리 dirty 파일을 통째로 stash 했다 되돌리므로, 같은 체크아웃을 쓰는 다른
     세션이 그 창 동안 파일을 쓰면 그 세션 작업이 깨진다(`/commit` 의 명시 스테이징 규칙은
     커밋만 막지 pull 은 못 막는다). `HERDR_ENV=1` 이면 `herdr pane list`(인자 없으면 **모든
     워크스페이스**를 준다)로 형제를 찾고, `agent_status` 가 working 인 형제가 있으면 **pull 을
     미루고 push 만** 한다 (`git push <remote> HEAD:<branch>`) — 그 세션이 idle 이 된 뒤 다시
     /sync. behind 가 0 이면 pull 자체가 no-op 이니 이 판단 없이 push 만 해도 된다.
   - **형제 판정은 cwd 문자열이 아니라 `git -C <그 pane 의 cwd> rev-parse --show-toplevel` 로 한다**
     (`cwd`·`foreground_cwd` 둘 다 본다). 내 toplevel 과 같으면 형제다. 경로 비교는 **심링크로
     들어간 pane 을 놓친다** — 예컨대 `~/.claude/skills/apply-kil9conf` 는 kil9conf 워킹트리
     안인데 문자열이 전혀 안 닮았다(dotfile·스킬이 죄다 그런 심링크다). toplevel 비교는 덤으로
     worktree(별개 워킹트리라 위험 아님)와 중첩 repo 를 정확히 제외하고, repo 밖 pane 은
     rev-parse 가 비정상 종료해 자연히 빠진다.
   - **형제 pane 이 없다고 안전이 증명되진 않는다** — herdr 밖 세션·cron·SSH 는 목록에 안 잡힌다.
     이 확인은 위험을 발견하면 멈추는 용도지, 없을 때 진행을 정당화하는 근거가 아니다.

   - **rebase→merge 폴백**: rebase 충돌 해결이 여러 커밋을 거슬러야 해 손이 많이 가면
     `git rebase --abort` 후 `sync-repo.sh merge`(=`pull --no-rebase`)로 전환한다. 가벼운
     충돌은 rebase 로 해결하는 편을 선호. 그 밖의 실패(push 거부 등)만 직접 개입.
   - **다중 리모트**: 도달 불가 리모트(사외망에서 사내 GHE 등)는 실패가 아니라 skip 이다 —
     닿는 머신의 /sync 가 회수하므로 그대로 진행한다. 발산 리모트는 스크립트가 경고와 해소
     명령을 출력한다. **발산 해소를 rebase 로 대신하지 말 것** — 다른 리모트에 이미 push 된
     커밋이 재작성돼 발산이 리모트 간에 핑퐁친다(그래서 기본 pull 도 `--rebase=merges` 다).
   - **추가 워킹카피**: `~/.claude/sync-extra-repos.conf` 가 있으면 스크립트가 거기 적힌
     체크아웃도 함께 pull 한다(머신 로컬 설정, 없으면 생략). 다른 체크아웃이 라이브 설정을
     물고 있을 때(예: WT junction) 그쪽이 stale 하면 repo 의 수정이 라이브에 도달하지 못하기
     때문. 그쪽이 dirty 면 스크립트가 경고만 하고 커밋하지 않으니, 경고가 뜨면 그 체크아웃에서
     `/commit` 규칙대로 커밋한 뒤 다시 실행한다.
2. **dirty 였으면 커밋·push** (clean 이면 생략): `/commit` 규칙대로 커밋한 뒤 `sync-repo.sh` 를
   다시 실행해 push 한다. worktree 안이어도 대상 브랜치 merge·정리는 하지 않는다 — 현재 브랜치
   커밋·push 까지만이며, worktree 마무리는 명시적 `/cip` 때만.
3. **보고**: 동기화만 했는지, 커밋·push 까지 했는지 한두 줄로 밝힌다. 형제 pane 때문에 pull 을
   미뤘거나 커밋을 건너뛰었으면 그 pane 의 표시 이름·id 를 함께 밝힌다("dirty 라서 건너뜀"보다
   사용자가 판단하기 쉽다).
