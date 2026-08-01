#!/bin/bash
# backlog 동시성 가드의 GitHub 리모트 선택·bounded fetch 공통 배관.
# source 전용. bash 3.2와 macOS 기본 도구에서 돌아야 한다.

backlog_guard_run_with_timeout() {  # $1=제한초, 나머지=실행할 명령
  local secs=$1 pid rc i=0
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "$secs" "$@"
    return $?
  fi
  if command -v gtimeout >/dev/null 2>&1; then
    gtimeout "$secs" "$@"
    return $?
  fi
  "$@" &
  pid=$!
  while [ "$i" -lt $((secs * 10)) ]; do
    if ! kill -0 "$pid" 2>/dev/null; then
      if wait "$pid"; then rc=0; else rc=$?; fi
      return "$rc"
    fi
    sleep 0.1
    i=$((i + 1))
  done
  kill -TERM "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  return 124
}

backlog_guard_remote_is_github() {  # $1=repo root, $2=remote
  local url
  url=$(git -C "$1" config --get "remote.$2.url" 2>/dev/null) || return 1
  case $url in
    git@github.com:*|ssh://*@github.com/*|https://github.com/*|http://github.com/*) return 0 ;;
    *) return 1 ;;
  esac
}

backlog_guard_github_remote() {  # $1=repo root
  local root=$1 branch upstream_remote remote
  branch=$(git -C "$root" symbolic-ref --quiet --short HEAD 2>/dev/null) || branch=""
  if [ -n "$branch" ]; then
    upstream_remote=$(git -C "$root" config --get "branch.$branch.remote" 2>/dev/null) || upstream_remote=""
    if [ -n "$upstream_remote" ] && backlog_guard_remote_is_github "$root" "$upstream_remote"; then
      echo "$upstream_remote"
      return 0
    fi
  fi
  for remote in github origin; do
    if backlog_guard_remote_is_github "$root" "$remote"; then
      echo "$remote"
      return 0
    fi
  done
  while IFS= read -r remote; do
    if backlog_guard_remote_is_github "$root" "$remote"; then
      echo "$remote"
      return 0
    fi
  done < <(git -C "$root" remote 2>/dev/null)
  return 1
}

# shellcheck disable=SC2034 # source 한 호출자가 두 상태 변수를 읽는다.
backlog_guard_fetch_github() {  # $1=repo root, $2=fetch 비활성(0|1)
  local root=$1 no_fetch=${2:-0} timeout_secs
  BACKLOG_GUARD_REMOTE=$(backlog_guard_github_remote "$root") || BACKLOG_GUARD_REMOTE=""
  if [ -z "$BACKLOG_GUARD_REMOTE" ]; then
    BACKLOG_GUARD_FETCH_STATUS=no-github-remote
    return 0
  fi
  if [ "$no_fetch" = 1 ]; then
    BACKLOG_GUARD_FETCH_STATUS=disabled
    return 0
  fi
  timeout_secs=${BACKLOG_GUARD_FETCH_TIMEOUT:-3}
  if GIT_TERMINAL_PROMPT=0 GCM_INTERACTIVE=Never \
      backlog_guard_run_with_timeout "$timeout_secs" \
      git -C "$root" fetch --quiet "$BACKLOG_GUARD_REMOTE" >/dev/null 2>&1; then
    BACKLOG_GUARD_FETCH_STATUS=ok
  else
    BACKLOG_GUARD_FETCH_STATUS=failed
  fi
}

backlog_guard_relevant_refs() {  # $1=repo root, $2=remote
  local root=$1 remote=$2 upstream head branch ref seen=" "
  upstream=$(git -C "$root" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null) \
    || upstream=""
  head=$(git -C "$root" symbolic-ref --quiet --short "refs/remotes/$remote/HEAD" 2>/dev/null) \
    || head=""
  branch=$(git -C "$root" symbolic-ref --quiet --short HEAD 2>/dev/null) || branch=""
  for ref in "$upstream" "$head" "$remote/$branch" "$remote/main" "$remote/master"; do
    [ -n "$ref" ] || continue
    case $ref in "$remote/"*) ;; *) continue ;; esac
    case $seen in *" $ref "*) continue ;; esac
    git -C "$root" rev-parse --verify --quiet "refs/remotes/$ref" >/dev/null || continue
    echo "$ref"
    seen="$seen$ref "
  done
}
