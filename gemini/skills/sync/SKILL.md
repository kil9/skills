---
name: sync
description: 현재 브랜치를 리모트와 동기화한다(pull rebase 우선 + 모든 리모트 push). 워킹트리가 dirty 면 동기화 후 변경을 커밋하고 다시 push 한다.
---

먼저 `git status --porcelain` 로 dirty 여부를 확인해 기억한다(2단계 진행 조건). 그다음:

1. **동기화**: 같은 디렉터리의 `sync-repo.sh` 실행 — `pull --rebase --autostash` 후 현재 브랜치를
   모든 리모트에 push. 사전 조사 없이 stash·pull·push 를 스크립트가 처리한다.

   - **rebase→merge 폴백**: rebase 충돌 해결이 여러 커밋을 거슬러야 해 손이 많이 가면
     `git rebase --abort` 후 `sync-repo.sh merge`(=`pull --no-rebase`)로 전환한다. 가벼운
     충돌은 rebase 로 해결하는 편을 선호. 그 밖의 실패(push 거부 등)만 직접 개입.
   - **추가 워킹카피**: `~/.claude/sync-extra-repos.conf` 가 있으면 스크립트가 거기 적힌
     체크아웃도 함께 pull 한다(머신 로컬 설정, 없으면 생략). 다른 체크아웃이 라이브 설정을
     물고 있을 때(예: WT junction) 그쪽이 stale 하면 repo 의 수정이 라이브에 도달하지 못하기
     때문. 그쪽이 dirty 면 스크립트가 경고만 하고 커밋하지 않으니, 경고가 뜨면 그 체크아웃에서
     `/commit` 규칙대로 커밋한 뒤 다시 실행한다.
2. **dirty 였으면 커밋·push** (clean 이면 생략): `/commit` 규칙대로 커밋한 뒤 `sync-repo.sh` 를
   다시 실행해 push 한다. worktree 안이어도 대상 브랜치 merge·정리는 하지 않는다 — 현재 브랜치
   커밋·push 까지만이며, worktree 마무리는 명시적 `/cip` 때만.
3. **보고**: 동기화만 했는지, 커밋·push 까지 했는지 한두 줄로 밝힌다.
