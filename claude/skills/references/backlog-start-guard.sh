#!/bin/bash
# 착수 후보의 로컬 상태보다 GitHub 진실원본에 새 변경이 있는지 결정적으로 수집한다.
# 판단은 하지 않는다. 소비 스킬이 stale 후보를 멈추고 unknown 은 경고 후 fail-open 한다.
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=backlog-git-guard-lib.sh
. "$script_dir/backlog-git-guard-lib.sh"

usage() {
  echo "usage: $(basename "$0") TASK-N [TASK-N ...]" >&2
  exit 2
}

[ "$#" -ge 1 ] || usage

root=$PWD
while [ "$root" != / ]; do
  [ -d "$root/backlog" ] && break
  root=$(dirname "$root")
done
if [ "$root" = / ]; then
  echo "skip=no-backlog"
  exit 0
fi
if ! git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
  echo "skip=no-git"
  exit 0
fi

tasks=()
for raw in "$@"; do
  case $raw in
    [Tt][Aa][Ss][Kk]-*) num=${raw#*-} ;;
    [Tt]-*)             num=${raw#*-} ;;
    *[!0-9]*|'')        usage ;;
    *)                  num=$raw ;;
  esac
  case $num in *[!0-9]*|'') usage ;; esac
  tasks+=("TASK-$((10#$num))")
done

if ! git -C "$root" rev-parse --verify HEAD >/dev/null 2>&1; then
  for task in "${tasks[@]}"; do echo "unknown=$task reason=no-head"; done
  exit 0
fi

backlog_guard_fetch_github "$root" "${BACKLOG_START_GUARD_NO_FETCH:-0}"
if [ -z "$BACKLOG_GUARD_REMOTE" ]; then
  for task in "${tasks[@]}"; do echo "unknown=$task reason=no-github-remote"; done
  exit 0
fi
echo "remote=$BACKLOG_GUARD_REMOTE fetch=$BACKLOG_GUARD_FETCH_STATUS"

refs=()
while IFS= read -r ref; do refs+=("$ref"); done < <(
  backlog_guard_relevant_refs "$root" "$BACKLOG_GUARD_REMOTE"
)
# refs 는 관련 ref 가 없으면 빈 배열이다. bash 4.4 미만은 `set -u` 아래 빈 배열의 `"${arr[@]}"` 를
# unbound 로 죽이므로(맥 기본 3.2, task-377) 아래 전개를 `+` 로 가드한다. tasks 는 usage() 가
# 인자 1개 이상을 보장하므로 그대로 둔다.

for task in "${tasks[@]}"; do
  num=${task#TASK-}
  found=0
  for ref in ${refs[@]+"${refs[@]}"}; do
    count=$(git -C "$root" rev-list --count "HEAD..$ref" -- \
      ":(glob)backlog/**/task-$num.md" \
      ":(glob)backlog/**/task-$num *.md" \
      ":(glob)backlog/**/task-$num-*.md")
    if [ "$count" -gt 0 ]; then
      echo "stale=$task ref=$ref commits=$count"
      found=1
      break
    fi
  done
  [ "$found" -eq 0 ] || continue
  if [ "$BACKLOG_GUARD_FETCH_STATUS" = failed ]; then
    echo "unknown=$task reason=fetch-failed"
  elif [ "${#refs[@]}" -eq 0 ]; then
    echo "unknown=$task reason=no-remote-ref"
  else
    echo "fresh=$task"
  fi
done
