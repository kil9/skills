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

# 빈 배열을 `"${arr[@]}"` 로 전개하면 bash 4.4 미만이 `set -u` 아래 unbound 로 죽는다. 맥 기본
# /bin/bash 는 3.2 라 이 스크립트가 거기서 항상 exit 1 했다(task-377). `${arr[@]+"${arr[@]}"}` 는
# 배열이 비었을 때 아무 인자도 만들지 않고, 비어 있지 않으면 각 원소를 따로 인용해 넘긴다 —
# 즉 3.2 에서도 공백 포함 원소가 쪼개지지 않는다. 아래 전개는 전부 이 형태를 지킨다.
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
  if ! contains_id "$id" ${selected_ids[@]+"${selected_ids[@]}"}; then
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
  if ! contains_id "$id" ${ids[@]+"${ids[@]}"}; then
    ids+=("$id")
  fi
done < <(printf '%s\n' "$tasks")

if [ "${#selected_ids[@]}" -gt 0 ]; then
  for id in "${selected_ids[@]}"; do
    if ! contains_id "$id" ${ids[@]+"${ids[@]}"}; then
      echo "error: 미완료 task가 아님: $id" >&2
      exit 6
    fi
  done
  ids=("${selected_ids[@]}")
fi

details=()
for id in ${ids[@]+"${ids[@]}"}; do
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
# `${!ids[@]}`(인덱스 목록)에는 위의 `+` 가드를 붙일 수 없으므로 개수로 센다 — 빈 배열이면 한 번도
# 돌지 않는다.
i=0
while [ "$i" -lt "${#ids[@]}" ]; do
  printf '\n===== %s =====\n' "${ids[$i]}"
  printf '%s\n' "${details[$i]}"
  i=$((i + 1))
done
