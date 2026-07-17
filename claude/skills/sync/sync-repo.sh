#!/bin/bash
# /sync 스킬용 정적 스크립트: pull 후 현재 브랜치를 모든 리모트에 push.
#   인자 없음(=rebase) — git pull --rebase=merges --autostash (기본, rebase 우선)
#   merge             — git pull --no-rebase --autostash (rebase 가 손이 많이 갈 때 폴백)
set -euo pipefail

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
probe_remote() {
  if command -v timeout >/dev/null 2>&1; then
    timeout 7 git ls-remote "$1" >/dev/null 2>&1
  else
    git ls-remote "$1" >/dev/null 2>&1
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

echo "sync 완료($strategy): $branch → ${pushed_remotes:-'(push 된 리모트 없음)'}"
