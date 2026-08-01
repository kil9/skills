#!/bin/bash
# backlog 소비 스킬 공용 read-only snapshot.
#
# 사용법: backlog-context.sh [TASK-N ...]
#   인자 없음   : milestone/task 목록과 모든 미완료 task 상세를 수집한다.
#   TASK-N 지정 : 같은 목록과 지정한 미완료 task 상세만 수집한다.
#
# 종료 코드: 2 backlog 부재, 3 CLI 부재, 4 milestone 목록 실패,
#            5 task 목록 실패, 6 잘못된 선택, 7 task 상세 실패.
set -euo pipefail

find_backlog_root() {
  local dir
  dir=$PWD
  while [ "$dir" != / ]; do
    if [ -d "$dir/backlog" ] || [ -f "$dir/backlog/config.yml" ]; then
      printf '%s\n' "$dir"
      return 0
    fi
    dir=${dir%/*}
    [ -n "$dir" ] || dir=/
  done
  return 1
}

usage() {
  echo "usage: backlog-context.sh [TASK-N ...]" >&2
  exit 64
}

contains_id() {
  local needle=$1 item
  shift
  for item in "$@"; do
    [ "$item" = "$needle" ] && return 0
  done
  return 1
}

selected_ids=()
for id in "$@"; do
  case "$id" in
    TASK-[0-9]*)
      number=${id#TASK-}
      case "$number" in
        ''|*[!0-9]*) usage ;;
      esac
      ;;
    *) usage ;;
  esac
  if ! contains_id "$id" "${selected_ids[@]}"; then
    selected_ids+=("$id")
  fi
done

if ! root=$(find_backlog_root); then
  echo "error: backlog/ 없음" >&2
  exit 2
fi

if ! command -v backlog >/dev/null 2>&1; then
  echo "error: backlog CLI 없음" >&2
  exit 3
fi

cd "$root"

if ! milestones=$(backlog milestone list --plain --show-completed 2>&1); then
  echo "error: milestone 조회 실패" >&2
  printf '%s\n' "$milestones" >&2
  exit 4
fi

if ! tasks=$(backlog task list --plain 2>&1); then
  echo "error: task 목록 조회 실패" >&2
  printf '%s\n' "$tasks" >&2
  exit 5
fi

ids=()
group=
while IFS= read -r line; do
  case "$line" in
    "To Do:"|"In Progress:"|"Blocked:") group=unfinished ;;
    "Done:") group=done ;;
  esac
  [ "$group" = unfinished ] || continue
  id=$(printf '%s\n' "$line" | sed -nE 's/.*(TASK-[0-9]+).*/\1/p')
  [ -n "$id" ] || continue
  if ! contains_id "$id" "${ids[@]}"; then
    ids+=("$id")
  fi
done < <(printf '%s\n' "$tasks")

if [ "${#selected_ids[@]}" -gt 0 ]; then
  for id in "${selected_ids[@]}"; do
    if ! contains_id "$id" "${ids[@]}"; then
      echo "error: 미완료 task가 아님: $id" >&2
      exit 6
    fi
  done
  ids=("${selected_ids[@]}")
fi

details=()
for id in "${ids[@]}"; do
  if ! detail=$(backlog task view "$id" --plain 2>&1); then
    echo "error: task 상세 조회 실패: $id" >&2
    printf '%s\n' "$detail" >&2
    exit 7
  fi
  details+=("$detail")
done

printf '%s\n' '## backlog context'
printf '%s\n' 'version: 1'
printf '%s\n' '## backlog root'
printf '%s\n' "$root"
printf '\n'
printf '%s\n' '## milestones'
printf '%s\n' "$milestones"
printf '\n'
printf '%s\n' '## tasks'
printf '%s\n' "$tasks"
printf '\n'
printf '## unfinished task details (%d)\n' "${#ids[@]}"
for i in "${!ids[@]}"; do
  printf '\n===== %s =====\n' "${ids[$i]}"
  printf '%s\n' "${details[$i]}"
done
