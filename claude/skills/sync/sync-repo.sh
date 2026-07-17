#!/bin/bash
# /sync 스킬용 정적 스크립트: pull 후 현재 브랜치를 모든 리모트에 push.
#   인자 없음(=rebase) — git pull --rebase --autostash (기본, rebase 우선)
#   merge             — git pull --no-rebase --autostash (rebase 가 손이 많이 갈 때 폴백)
set -euo pipefail

strategy="${1:-rebase}"
case "$strategy" in
  rebase) pull_opt="--rebase" ;;
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

failed=()
for remote in $remotes; do
  if git push "$remote" "$branch"; then
    echo "pushed: $remote/$branch"
  else
    failed+=("$remote")
  fi
done

if [ ${#failed[@]} -gt 0 ]; then
  echo "error: push 실패: ${failed[*]}" >&2
  exit 1
fi

# --- 같은 repo 의 추가 워킹카피도 함께 동기화 (머신 로컬 설정, 없으면 조용히 생략) ---
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

    echo "--- 추가 체크아웃: $extra"
    if [ -n "$(git -C "$extra" status --porcelain)" ]; then
      # 여기서 커밋하지 않는다 — 무엇을 커밋할지는 사람/에이전트가 /commit 규칙으로 판단할 일.
      echo "warn: $extra 에 커밋 안 된 변경이 있다. 커밋 후 다시 /sync 하라:" >&2
      git -C "$extra" status --porcelain >&2
    fi

    if git -C "$extra" rev-parse --abbrev-ref '@{upstream}' >/dev/null 2>&1; then
      git -C "$extra" pull $pull_opt --autostash
      extra_branch=$(git -C "$extra" symbolic-ref --short HEAD)
      if [ -n "$(git -C "$extra" log --oneline '@{upstream}..HEAD')" ]; then
        git -C "$extra" push origin "$extra_branch" && echo "pushed: $extra → origin/$extra_branch"
      fi
      echo "  $extra: $(git -C "$extra" log --oneline -1)"
    else
      echo "notice: $extra upstream 미설정 — pull 생략" >&2
    fi
  done 3< "$extra_conf"
fi

echo "sync 완료($strategy): $branch → $(echo "$remotes" | tr '\n' ' ')"
