#!/bin/bash
# backlog task ID 가드 — 이미 쓰인 번호가 다시 발급되는 것을 막는다.
#
# backlog CLI(1.48.0 실측)의 ID 할당기는 backlog/tasks/ + backlog/completed/ 만 본다.
# 그래서 두 구멍이 남는다:
#   1. backlog/archive/tasks/ 는 안 본다 — 거기 최대 번호가 있으면 그대로 재발급된다.
#   2. 다른 머신이 만들었지만 이 체크아웃에 아직 안 온 태스크를 알 길이 없다.
#      실제 충돌 3건(task-153/167/203)이 전부 이 경우였다. 그쪽이 push 만 했으면
#      리모트 트리에는 그 번호가 있으므로, 여기서 그것까지 훑어 피한다.
#
# 사용법:
#   backlog-id-guard.sh next          # 다음에 쓸 ID 를 출력 (next=TASK-N)
#   backlog-id-guard.sh fix TASK-N    # 방금 만든 태스크가 이미 쓰인 번호면 개명
#
# 출력은 한 줄 key=value 다:
#   next=TASK-206
#   ok=TASK-206                       # 개명 불필요
#   moved=TASK-203 -> TASK-206        # 개명함
#   skip=no-backlog | skip=no-cli     # 대상 저장소가 아님 (exit 0)
#
# fix 는 **방금 만든 태스크**에만 쓴다. 다른 파일·커밋이 이미 그 ID 를 참조하는
# 오래된 태스크를 개명하면 그 참조가 끊긴다(그 판단은 사람 몫이다).
#
# 리모트 조회는 `git fetch` 를 한 번 태운다(타임아웃 10초, 실패는 무시).
# 끄려면 BACKLOG_ID_GUARD_NO_FETCH=1.
#
# **BSD(macOS) 도구만 있는 환경을 가정한다.** 2026-07-26 에 여기서 두 구멍이 드러났다:
# `grep -oP`(PCRE)와 `timeout`(GNU coreutils) 둘 다 macOS 기본 설치에 없다. 그런데 둘 다
# `|| true` 로 감싸여 있어 **에러가 나도 exit 0 에 next= 는 정상 출력됐다** — 즉 가드가
# 막으려던 두 구멍(archive·미동기 리모트)이 조용히 다시 열린 상태로 몇 달을 돌았다.
# 그래서 아래는 GNU 전용 도구를 쓰지 않는다. 새 코드도 그 규칙을 지킬 것.
set -euo pipefail

# GNU timeout 대응물. 없으면 백그라운드 + 폴링으로 직접 만든다(macOS 에 timeout 이 없다).
run_with_timeout() {  # $1=제한초, 나머지=실행할 명령
  local secs=$1 pid rc i=0
  shift
  if command -v timeout >/dev/null 2>&1; then timeout "$secs" "$@"; return $?; fi
  if command -v gtimeout >/dev/null 2>&1; then gtimeout "$secs" "$@"; return $?; fi
  "$@" &
  pid=$!
  while ((i < secs * 10)); do
    if ! kill -0 "$pid" 2>/dev/null; then
      wait "$pid" && rc=0 || rc=$?
      return "$rc"
    fi
    sleep 0.1
    ((i++))
  done
  kill -TERM "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  return 124
}

usage() {
  echo "usage: $(basename "$0") next | fix TASK-N" >&2
  exit 2
}

[[ $# -ge 1 ]] || usage
mode=$1

# backlog 저장소 찾기 (cwd 에서 위로)
root=$PWD
while [[ $root != / ]]; do
  [[ -d $root/backlog/tasks ]] && break
  root=$(dirname "$root")
done
if [[ $root == / ]]; then
  echo "skip=no-backlog"
  exit 0
fi
if ! command -v backlog >/dev/null 2>&1; then
  echo "skip=no-cli"
  exit 0
fi

# 로컬: tasks/ + completed/ + archive/ 를 통틀어 쓰인 번호. exclude 로 준 경로 하나는 뺀다.
local_max() {
  local exclude=${1:-} f base max=0
  while IFS= read -r -d '' f; do
    [[ -n $exclude && $f == "$exclude" ]] && continue
    base=$(basename "$f")
    [[ $base =~ ^task-([0-9]+) ]] || continue
    ((10#${BASH_REMATCH[1]} > max)) && max=$((10#${BASH_REMATCH[1]}))
  done < <(find "$root/backlog/tasks" "$root/backlog/completed" "$root/backlog/archive" \
             -type f -name 'task-*.md' -print0 2>/dev/null)
  echo "$max"
}

# 리모트: 아직 안 당겨온 태스크가 다른 머신에서 push 됐을 수 있다.
remote_max() {
  git -C "$root" rev-parse --git-dir >/dev/null 2>&1 || { echo 0; return; }
  if [[ ${BACKLOG_ID_GUARD_NO_FETCH:-0} != 1 ]]; then
    # 인증 프롬프트에 걸려 매달리지 않게 GIT_TERMINAL_PROMPT=0 도 함께 준다
    # (VPN 이 필요한 사내 origin 이 붙지 않을 때가 그 경우다).
    GIT_TERMINAL_PROMPT=0 run_with_timeout 10 \
      git -C "$root" fetch --all --quiet >/dev/null 2>&1 || true
  fi
  local refs=() up n max=0
  up=$(git -C "$root" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null) || up=""
  [[ -n $up ]] && refs+=("$up")
  while IFS= read -r r; do refs+=("$r"); done < <(
    git -C "$root" for-each-ref --format='%(refname:short)' \
      'refs/remotes/*/main' 'refs/remotes/*/master' 2>/dev/null)
  # 번호 추출은 grep -oP 가 아니라 bash 정규식으로 한다(local_max 와 같은 방식). ls-tree -r 은
  # blob 만 내놓으므로 마지막 경로 성분이 곧 파일명이다.
  local p base
  for r in "${refs[@]}"; do
    while IFS= read -r p; do
      base=${p##*/}
      [[ $base =~ ^task-([0-9]+) ]] || continue
      ((10#${BASH_REMATCH[1]} > max)) && max=$((10#${BASH_REMATCH[1]}))
    done < <(git -C "$root" ls-tree -r --name-only "$r" -- backlog 2>/dev/null || true)
  done
  echo "$max"
}

used_max() {
  local l r
  l=$(local_max "${1:-}")
  r=$(remote_max)
  ((r > l)) && l=$r
  echo "$l"
}

case $mode in
  next)
    echo "next=TASK-$(( $(used_max) + 1 ))"
    ;;
  fix)
    [[ $# -eq 2 ]] || usage
    [[ $2 =~ ([0-9]+) ]] || usage
    num=$((10#${BASH_REMATCH[1]}))

    file=""
    while IFS= read -r -d '' f; do
      base=$(basename "$f")
      [[ $base =~ ^task-([0-9]+)[[:space:]] ]] || continue
      if ((10#${BASH_REMATCH[1]} == num)); then file=$f; break; fi
    done < <(find "$root/backlog/tasks" -maxdepth 1 -type f -name 'task-*.md' -print0)

    if [[ -z $file ]]; then
      echo "error=not-found TASK-$num" >&2
      exit 1
    fi

    other_max=$(used_max "$file")
    if ((num > other_max)); then
      echo "ok=TASK-$num"
      exit 0
    fi

    new=$((other_max + 1))
    newfile=$(dirname "$file")/$(basename "$file" | sed -E "s/^task-[0-9]+/task-$new/")
    # frontmatter 의 id 는 대문자 TASK-N 이다. SECTION 마커·본문은 건드리지 않는다.
    sed -i -E "0,/^id: [Tt][Aa][Ss][Kk]-[0-9]+$/s//id: TASK-$new/" "$file"
    if git -C "$root" ls-files --error-unmatch "$file" >/dev/null 2>&1; then
      git -C "$root" mv "$file" "$newfile"
    else
      mv "$file" "$newfile"
    fi
    echo "moved=TASK-$num -> TASK-$new"
    ;;
  *)
    usage
    ;;
esac
