---
name: cip
description: 커밋 후 push까지 자동 실행한다. worktree에서 호출하면 대상 브랜치(기본 main/master)에 rebase merge 후 push, 그리고 worktree·브랜치까지 정리한다.
---

커밋한 뒤 push 한다. `$ARGUMENTS` 는 일반 모드에선 커밋 메시지 힌트, worktree 모드에선 대상 브랜치 override.

1. **커밋**: `/commit` 스킬 규칙(문서 갱신 판정·명시적 스테이징·메시지 형식)을 그대로 따른다.
2. **PR Summary 갱신**(worktree 모드만): 링크된 worktree 안이면 현재 브랜치에 열린 PR 이 있는지
   확인하고, 있으면 base 대비 변경으로 Summary 를 갱신한다. 일반 모드면 생략.
   판별은 `git rev-parse --git-dir` 과 `--git-common-dir` 이 **다른 디렉터리를 가리키는지**로 한다 —
   하위 디렉터리에서는 전자가 절대경로, 후자가 상대경로(`../.git`)로 나와 문자열만 비교하면 일반
   repo 를 worktree 로 오판하므로 실경로로 맞춰 비교한다.
3. **push·병합·정리**: 이 SKILL.md 와 같은 디렉터리의 `cip-push.sh` 를 **한 번의 셸 명령으로**
   실행한다. 사전 조사(리모트 나열·도달성 체크 등)를 따로 하지 않는다 — 모드 판별, 리모트 도달성
   체크(도달 불가 리모트는 100초 대기 없이 건너뜀), push(업스트림 없으면 `-u`), worktree 모드의
   rebase·`--ff-only` merge·worktree/브랜치 정리 전부 스크립트가 처리한다.

   종료코드: 0=모든 리모트 push 성공, 2=일부만 성공(도달 불가/인증 실패로 건너뜀 있음),
   1=push 전무 또는 중단(rebase 충돌, ff 불가, dirty 등).
4. **보고**: 스크립트 출력 근거로 결과를 요약한다. 실패·건너뜀은 자동 해결·재시도·자격증명 입력
   유도 없이 사실만 보고한다(rebase 충돌은 상태가 보존돼 있으니 해결 방안을 제시). worktree 모드
   성공 시 작업 디렉터리가 삭제되므로 대상 worktree 로 이동을 안내한다.
