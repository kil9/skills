---
description: 현재 repo 를 /sync 한 뒤, 다른 머신들(Herdr 앱 등록 머신 또는 all-sync-hosts.conf)에 있는 같은 repo 체크아웃도 pull 한다. "/all-sync / 다른 머신에서도 pull 해줘 / 전 머신 동기화" 라고 할 때. 사용자가 프롬프트에 `/all-sync` 를 적었거나(문장 끝 포함) 직접 요청했을 때 부른다. 자율 호출은 삼간다.
allowed_tools: [Bash, Read, Skill]
---

1. **로컬 동기화**: `Skill("sync")` 를 그대로 따른다(dirty 면 커밋·push 까지). 완료 기준: 현재 브랜치가
   리모트에 push 됐다. 실패하면 여기서 멈추고 보고한다 — 원격이 받을 커밋이 없다.
2. **원격 pull**: 같은 repo 루트에서 돌린다. 인자로 머신을 주면 그 머신만 돈다(사용자가 머신을 지목했으면 넘긴다).

   ```
   bash ~/.claude/skills/all-sync/all-sync.sh [머신 ...]
   ```

   머신 목록·체크아웃 찾는 법·상태 값은 스크립트 머리 주석이 정본이다. 원격은 `pull --ff-only` 만 한다 —
   그 머신의 세션이 쓰는 dirty 변경을 stash 하지 않으려는 것이니 **실패를 rebase·stash·reset 으로 풀지 않는다.**
   완료 기준: 모든 머신이 한 줄씩 상태를 냈다.
3. **보고**: 머신마다 상태 한 줄. ok·pulled·skip 이 아닌 것은 이유와 사용자가 할 일을 붙인다.
   - `diverged`: 그 머신에 push 안 된 커밋이 있다 — 그 머신에서 `/sync`.
   - `dirty-conflict`: 받을 변경이 그 머신의 커밋 안 된 파일과 겹친다 — 그 머신 세션이 정리한 뒤 다시.
   - `behind`: 그 머신의 upstream 리모트에 로컬 커밋이 아직 없다(다른 리모트로만 push 됨).
   - `notfound`·`unreachable`: 체크아웃이 없거나 ssh 가 안 닿았다. 그대로 알린다.
   pull 만으로 반영되지 않는 repo(그 머신에서 설치·재적용 단계가 따로 있는 dotfile·mod 등)면 그 사실을 한 줄 덧붙인다.
