#!/bin/bash
# /cip 스킬용 정적 스크립트: 커밋 이후 단계를 처리한다.
#   일반 모드   — 현재 브랜치를 모든 리모트에 push (도달성 사전 체크, 업스트림 없으면 -u).
#   worktree 모드 — 대상 브랜치에 rebase → 대상 worktree 에서 --ff-only merge → push →
#                  자기 worktree·브랜치 정리. 충돌·dirty 등은 자동 해결 없이 중단.
# 사용법: cip-push.sh [대상브랜치]   (인자는 worktree 모드의 대상 브랜치 override)
# 종료코드: 0=모든 리모트 push 성공, 2=일부 push 성공(건너뜀/실패 있음), 1=push 전무 또는 중단.
set -euo pipefail
export GIT_TERMINAL_PROMPT=0

# 도달 불가 리모트에 push 를 시도해 100초씩 멈추지 않기 위한 사전 체크.
remote_reachable() {
  local url=$1 scheme hostport host port
  case "$url" in
    http://* | https://*)
      scheme=${url%%://*}
      hostport=${url#*://}; hostport=${hostport%%/*}; hostport=${hostport#*@}
      curl -s -o /dev/null --connect-timeout 4 "$scheme://$hostport/"
      ;;
    ssh://*)
      hostport=${url#ssh://}; hostport=${hostport%%/*}; hostport=${hostport#*@}
      host=${hostport%%:*}; port=${hostport##*:}
      [ "$port" = "$host" ] && port=22
      nc -z -w4 "$host" "$port" >/dev/null 2>&1
      ;;
    *:*)
      host=${url%%:*}; host=${host#*@}
      nc -z -w4 "$host" 22 >/dev/null 2>&1
      ;;
    *)
      return 0  # 로컬 경로 등은 체크 생략
      ;;
  esac
}

# push_all <dir> <branch> : 모든 리모트에 push. 도달 불가·인증 실패는 건너뛰고 계속.
push_all() {
  local dir=$1 branch=$2 remote url upstream_opt="" ok=0 bad=0
  local remotes
  remotes=$(git -C "$dir" remote)
  if [ -z "$remotes" ]; then
    echo "error: 등록된 리모트가 없다" >&2
    return 1
  fi
  # -u 가 origin 에 붙도록 origin 을 앞으로
  if echo "$remotes" | grep -qx origin; then
    remotes="origin
$(echo "$remotes" | grep -vx origin || true)"
  fi
  git -C "$dir" rev-parse --abbrev-ref "$branch@{upstream}" >/dev/null 2>&1 || upstream_opt="-u"
  for remote in $remotes; do
    url=$(git -C "$dir" remote get-url --push "$remote")
    if ! remote_reachable "$url"; then
      echo "skip: $remote ($url) 도달 불가 — push 건너뜀"
      bad=$((bad + 1)); continue
    fi
    if git -C "$dir" push $upstream_opt "$remote" "$branch"; then
      echo "pushed: $remote/$branch"
      upstream_opt=""; ok=$((ok + 1))
    else
      echo "push 실패: $remote — 재시도·자격증명 입력 없이 보고만 한다" >&2
      bad=$((bad + 1))
    fi
  done
  [ "$ok" -gt 0 ] || return 1
  [ "$bad" -eq 0 ] || return 2
}

branch=$(git symbolic-ref --short HEAD 2>/dev/null) || {
  echo "error: detached HEAD — 대상 브랜치가 없다" >&2
  exit 1
}

# 링크된 worktree 판별용 경로 정규화.
# git 은 하위 디렉터리에서 호출하면 --git-dir 을 절대경로로, --git-common-dir 을
# 상대경로(../.git)로 돌려준다. 그대로 문자열 비교하면 일반 repo 를 worktree 로
# 오판해 엉뚱한 브랜치에 rebase·ff-merge 를 시도하므로 실경로로 맞춰 비교한다.
# (--path-format=absolute 는 git 2.31+ 전용이라 쓰지 않는다.)
# 해석 실패 시 양쪽 다 빈 문자열이 돼 '일반 모드' 로 떨어지는데, 병합 없이 현재
# 브랜치만 push 하는 안전한 쪽이라 폴백으로 적절하다.
resolve_dir() { (cd "$1" >/dev/null 2>&1 && pwd -P); }

if [ "$(resolve_dir "$(git rev-parse --git-dir)")" \
   = "$(resolve_dir "$(git rev-parse --git-common-dir)")" ]; then
  # ── 일반 모드 ──
  push_all "$(pwd)" "$branch"
  exit $?
fi

# ── worktree 모드 ──
target=${1:-}
if [ -z "$target" ]; then
  target=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||') || true
fi
if [ -z "$target" ]; then
  for c in main master; do
    if git show-ref -q --verify "refs/heads/$c"; then target=$c; break; fi
  done
fi
[ -n "$target" ] || { echo "error: 대상 브랜치를 정할 수 없다" >&2; exit 1; }
[ "$target" != "$branch" ] || { echo "error: 현재 브랜치가 이미 대상 브랜치($target)다" >&2; exit 1; }

target_wt=$(git worktree list --porcelain | awk -v ref="refs/heads/$target" '
  /^worktree /{wt=substr($0, 10)} $0=="branch "ref{print wt}')
[ -n "$target_wt" ] || { echo "error: 대상 브랜치($target)가 체크아웃된 worktree 가 없다" >&2; exit 1; }

cur_wt=$(git rev-parse --show-toplevel)

[ -z "$(git status --porcelain)" ] || {
  echo "error: 커밋 안 된 변경이 남아 있다 — 커밋(또는 정리) 후 재실행" >&2
  exit 1
}
[ -z "$(git -C "$target_wt" status --porcelain)" ] || {
  echo "error: 대상 worktree 가 dirty 다: $target_wt" >&2
  exit 1
}

echo "worktree 모드: $branch → $target ($target_wt)"
git rebase "$target" || {
  echo "error: rebase 충돌 — 자동 해결하지 않는다. 상태를 보존한 채 중단" >&2
  exit 1
}
git -C "$target_wt" merge --ff-only "$branch" || {
  echo "error: --ff-only merge 실패 — 자동 해결하지 않는다" >&2
  exit 1
}

push_rc=0
push_all "$target_wt" "$target" || push_rc=$?

git -C "$target_wt" worktree remove "$cur_wt"
git -C "$target_wt" branch -d "$branch"
echo "정리 완료: worktree $cur_wt · 브랜치 $branch 삭제"
echo "notice: 현재 작업 디렉터리가 삭제됐다 — cd $target_wt 필요"
exit "$push_rc"
