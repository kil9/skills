#!/bin/bash
# /sync 스킬용 정적 스크립트: pull 후 현재 브랜치를 모든 리모트에 push.
#   인자 없음(=rebase) — git pull --rebase=merges --autostash (기본, rebase 우선)
#   merge             — git pull --no-rebase --autostash (rebase 가 손이 많이 갈 때 폴백)
set -euo pipefail

# 인증이 없는 리모트에서 git 이 사람에게 자격증명을 물어 **행** 하는 것을 막는다. 프롬프트가
# 뜨면 /sync 는 실패로도 skip 으로도 끝나지 않고 그냥 멈춘다 — 무인 실행에서 최악이다.
export GIT_TERMINAL_PROMPT=0

strategy="${1:-rebase}"
case "$strategy" in
  # plain --rebase 가 아니라 =merges 인 이유: 다중 리모트 발산을 merge 로 해소한 직후
  # upstream rebase pull 이 그 머지 커밋을 flatten 해 해소를 되돌린다(스모크에서 실측).
  # =merges 는 로컬 머지 커밋을 보존하고, 머지가 없을 땐 plain rebase 와 동일하다.
  rebase) pull_opt="--rebase=merges" ;;
  merge)  pull_opt="--no-rebase" ;;
  *) echo "usage: sync-repo.sh [rebase|merge]" >&2; exit 1 ;;
esac

branch=$(git symbolic-ref --short HEAD 2>/dev/null) || {
  echo "error: detached HEAD — 동기화할 브랜치가 없다" >&2
  exit 1
}

remotes=$(git remote)
if [ -z "$remotes" ]; then
  echo "error: 등록된 리모트가 없다" >&2
  exit 1
fi

# 커밋 안 된 수정사항은 --autostash 가 pull 전후로 stash/복원한다.
if git rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
  git pull $pull_opt --autostash
else
  echo "notice: upstream 미설정 — pull 생략" >&2
fi

# 리모트 도달성 프로브. 사외 머신에서 사내 GHE 처럼 아예 안 닿는 리모트는
# 실패가 아니라 skip 이다 — ssh 기본 타임아웃이 길어 timeout 이 있으면 감싼다.
probe_remote() { # probe_remote <리모트> [체크아웃 경로]
  local target=$1 dir=${2:-.}
  if command -v timeout >/dev/null 2>&1; then
    timeout 7 git -C "$dir" ls-remote "$target" >/dev/null 2>&1
  else
    git -C "$dir" ls-remote "$target" >/dev/null 2>&1
  fi
}

failed=()
for remote in $remotes; do
  if ! probe_remote "$remote"; then
    echo "skip: $remote — 도달 불가(사외망 등). 닿는 머신에서의 /sync 가 회수한다" >&2
    continue
  fi

  # 발산 감지: 리모트에 로컬에 없는 커밋이 있으면 push 가 어차피 거부된다 — 원인을 먼저 밝힌다.
  # (upstream 은 위 pull 이 이미 흡수했으므로 주로 upstream 아닌 리모트에서 걸린다.)
  if git fetch -q "$remote" "$branch" 2>/dev/null; then
    diverged=$(git rev-list --count "$branch..FETCH_HEAD" 2>/dev/null || echo 0)
    if [ "$diverged" -gt 0 ]; then
      echo "warn: $remote/$branch 에 로컬에 없는 커밋 ${diverged}개 — 발산 상태다." >&2
      echo "      그 커밋을 살리려면: 'git pull --no-rebase $remote $branch' 로 병합 후 다시 /sync." >&2
      echo "      (rebase 로 풀지 말 것 — 다른 리모트에 이미 push 된 커밋이 재작성돼 발산이 리모트 간에 핑퐁친다)" >&2
      echo "      버려도 되는 커밋이면(오염된 미러 등): 'git push --force-with-lease $remote $branch'." >&2
      failed+=("$remote(diverged)")
      continue
    fi
  fi

  if git push "$remote" "$branch"; then
    echo "pushed: $remote/$branch"
    pushed_remotes="${pushed_remotes:+$pushed_remotes }$remote"
  else
    failed+=("$remote")
  fi
done

if [ ${#failed[@]} -gt 0 ]; then
  echo "error: push 실패: ${failed[*]}" >&2
  exit 1
fi

# --- 다른 체크아웃 동기화 (스킬 repo + 머신 로컬 추가분) -----------------------------
#
# 한 체크아웃을 pull(+조건부 push)한다. $2 가 'skip-push-if-dirty' 면 커밋 안 된 변경이 있을 때
# push 를 건너뛴다 — 스킬 repo 처럼 '무엇을 커밋할지' 판단이 필요한 곳에 쓴다.
checkout_failed=()

sync_checkout() {
  local dir="$1" dirty_policy="${2:-}" cbranch
  echo "--- $dir"
  local dirty=""
  if [ -n "$(git -C "$dir" status --porcelain)" ]; then
    dirty=1
    # 여기서 커밋하지 않는다 — 무엇을 커밋할지는 사람/에이전트가 /commit 규칙으로 판단할 일.
    echo "warn: $dir 에 커밋 안 된 변경이 있다. 커밋 후 다시 /sync 하라:" >&2
    git -C "$dir" status --porcelain >&2
  fi

  local upstream=""
  if ! upstream=$(git -C "$dir" rev-parse --abbrev-ref '@{upstream}' 2>/dev/null); then
    echo "notice: $dir upstream 미설정 — pull 생략" >&2
    return 0
  fi

  # **도달 불가는 실패가 아니라 skip 이다.** 예전엔 pull 실패가 그대로 터져 스크립트가 거기서
  # 끝났다 — 목록 뒤쪽 체크아웃이 통째로 안 돌고도 마지막 요약 줄이 없어 아무도 못 봤다
  # (2026-08-27 맥: GHEC 인증이 없는 ~/work/kil9/workflow. task-487).
  #
  # 인증 실패와 진짜 발산·충돌을 **종료 코드나 에러 문자열로 가르지 않는다** — pull 은 둘 다
  # rc=1 로 감싸고 문자열은 git 버전·로케일·credential helper 마다 다르다. 대신 단계를 쪼갠다:
  # 프로브·fetch(네트워크·인증) 가 실패하면 skip, 그 둘이 성공한 뒤의 통합 실패만 진짜 충돌이다.
  local uremote=${upstream%%/*}
  if ! probe_remote "$uremote" "$dir"; then
    echo "skip: $dir — $uremote 에 닿지 않는다(인증 없음·사외망 등). 닿는 머신의 /sync 가 회수한다" >&2
    return 0
  fi
  if ! git -C "$dir" fetch -q "$uremote"; then
    echo "skip: $dir — $uremote fetch 실패(인증·네트워크). 다음 /sync 가 다시 시도한다" >&2
    return 0
  fi

  if ! git -C "$dir" pull $pull_opt --autostash; then
    echo "error: $dir 통합 실패 — 리모트에는 닿았으니 발산·충돌이다. 그 repo 에서 직접 해소하라." >&2
    # 충돌로 멈춘 rebase 를 그대로 두면 다음 /sync 가 'rebase in progress' 라는 다른 얼굴의
    # 실패를 낸다. 여기서 abort 해 상태를 되돌리고(autostash 도 함께 복원된다) 사람에게 넘긴다.
    if [ -d "$(git -C "$dir" rev-parse --git-path rebase-merge)" ] ||
       [ -d "$(git -C "$dir" rev-parse --git-path rebase-apply)" ]; then
      git -C "$dir" rebase --abort >/dev/null 2>&1 || true
      echo "      진행 중이던 rebase 는 abort 했다 — 워킹트리는 pull 전 상태다." >&2
    fi
    checkout_failed+=("$dir(diverged)")
    return 0
  fi

  cbranch=$(git -C "$dir" symbolic-ref --short HEAD)
  if [ -n "$(git -C "$dir" log --oneline '@{upstream}..HEAD')" ]; then
    if [ -n "$dirty" ] && [ "$dirty_policy" = "skip-push-if-dirty" ]; then
      echo "  push 건너뜀(dirty): $dir — 커밋한 뒤 다시 /sync" >&2
    elif git -C "$dir" push origin "$cbranch"; then
      echo "pushed: $dir → origin/$cbranch"
    else
      # push 거부는 발산 신호다 — 예전에는 `push && echo` 라 실패가 조용히 삼켜졌다.
      echo "error: $dir push 거부 — origin/$cbranch 가 발산했다." >&2
      checkout_failed+=("$dir(push)")
    fi
  fi
  echo "  $dir: $(git -C "$dir" log --oneline -1)"
}

# 스킬 repo 는 **기본 대상**이다. 머신 로컬 conf 에 맡기면 머신마다 수동이라 새 머신에서 또
# 누락되고, 그 누락은 증상이 없어 오래 간다 — 2026-07-29 에 nuc14 에서 스킬을 고쳐 push 했는데
# 다른 머신이 /sync 를 여러 번 돌리고도 못 받아 스킬셋이 갈라졌다(kil9conf task-242).
# 없는 경로는 조용히 넘어간다(skills-naver·workflow 는 회사 머신에만 있다).
self_top=$(git rev-parse --show-toplevel 2>/dev/null || echo "")
for skill_repo in ${SYNC_SKILL_REPOS:-"$HOME/work/skills" "$HOME/work/skills-naver" "$HOME/work/kil9/workflow"}; do
  [ -d "$skill_repo" ] || continue
  git -C "$skill_repo" rev-parse --git-dir >/dev/null 2>&1 || continue
  # 지금 그 repo 안에서 /sync 를 돌렸다면 위에서 이미 처리했다.
  [ "$(git -C "$skill_repo" rev-parse --show-toplevel)" = "$self_top" ] && continue
  sync_checkout "$skill_repo" skip-push-if-dirty
done

# 같은 repo 의 추가 워킹카피 (머신 로컬 설정, 없으면 조용히 생략).
# 다른 체크아웃이 라이브 설정을 물고 있는 경우(예: WT junction → rc/windows-terminal-preview),
# 그쪽이 stale 해지는 순간 repo 의 수정이 라이브에 도달하지 못한다. 증상은 "고쳤는데 안 고쳐짐"이라
# 원인을 찾기 어렵다. 그래서 여기서 같이 당긴다.
# 설정: ~/.claude/sync-extra-repos.conf — 한 줄에 체크아웃 경로 하나, '#' 주석 허용.
# 머신마다 다른 경로라 추적하지 않는다(기기별 로컬 규칙).
extra_conf="${SYNC_EXTRA_REPOS_CONF:-$HOME/.claude/sync-extra-repos.conf}"
if [ -f "$extra_conf" ]; then
  # fd 3 으로 읽는다 — 루프 안의 git 이 stdin 을 먹어 목록이 잘리는 것을 막는다.
  while IFS= read -r line <&3 || [ -n "$line" ]; do
    extra="${line%%#*}"
    extra="$(echo "$extra" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -z "$extra" ] && continue

    if ! git -C "$extra" rev-parse --git-dir >/dev/null 2>&1; then
      echo "notice: 추가 체크아웃 건너뜀(git repo 아님): $extra" >&2
      continue
    fi

    # 여기는 dirty 여도 push 한다 — 라이브 설정을 물고 있는 미러라 최신화가 목적이고,
    # 그 체크아웃에서 사람이 편집하는 일은 드물다.
    sync_checkout "$extra"
  done 3< "$extra_conf"
fi

echo "sync 완료($strategy): $branch → ${pushed_remotes:-'(push 된 리모트 없음)'}"

# 도달 불가로 건너뛴 것은 실패가 아니다. 닿았는데 못 합친 것만 여기 남아 종료 코드를 세운다.
if [ ${#checkout_failed[@]} -gt 0 ]; then
  echo "error: 체크아웃 동기화 실패: ${checkout_failed[*]}" >&2
  exit 1
fi
