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

# ---------------------------------------------------------------- 감춤 검사
#
# **`backlog task list` 가 태스크를 조용히 감출 수 있다.** CLI 가 다른 브랜치·리모트의 더 새로운
# 상태를 보고(`check_active_branches`·`remote_operations`) 그 파일 경로가 없어진 것을 '삭제됨' 으로
# 접기 때문이다. 실측 두 사례(2026-08-19):
#
#   * 제목을 고쳐 **파일명이 바뀐** 태스크가 사라졌다(옛 경로가 다른 시점에서 삭제로 보인다).
#   * 상태가 `To Do` 인 태스크 하나가 어느 상태 그룹에도 안 나왔다(원인 미확정).
#
# 증상이 **조용하다는 것**이 문제다 — 그 태스크는 아무도 안 보는 채로 남고, 드레인 루프는
# '남은 일 없음' 으로 종료한다(실제로 그럴 뻔했다). 그래서 목록을 믿기 전에 **파일의 id 집합과
# 대조**한다. `completed/` 만 보는 검사로는 위 둘 다 못 잡는다.
#
# 감춰진 것은 **버리지 않고 되살린다**: 미완료 상태면 아래 `ids` 에 넣어 상세까지 싣는다
# (`backlog task view` 는 감춰진 것도 연다). 경고만 하고 빠뜨리면 이 검사가 반쪽이다.
hidden_ids=()
hidden_lines=()
if [ -d "$root/backlog/tasks" ]; then
  for file in "$root"/backlog/tasks/*.md; do
    # glob 이 안 맞으면 패턴 문자열 그대로 들어온다(nullglob 을 켜지 않는다 — 이 스크립트의
    # 다른 부분이 그 설정에 기대지 않는 편이 안전하다).
    [ -e "$file" ] || continue
    file_id=$(sed -nE 's/^id:[[:space:]]*(TASK-[0-9]+).*/\1/p' "$file" | head -1)
    [ -n "$file_id" ] || continue
    # **뒤에 숫자가 오면 다른 id 다** — `TASK-13` 이 `TASK-131` 안에서 걸리는 것을 막는다.
    if printf '%s\n' "$tasks" | grep -qE "${file_id}([^0-9]|\$)"; then
      continue
    fi
    file_status=$(sed -nE 's/^status:[[:space:]]*(.+)$/\1/p' "$file" | head -1)
    hidden_ids+=("$file_id")
    hidden_lines+=("$file_id ${file_status:-(상태 없음)} ${file##*/}")
  done
fi
if [ "${#hidden_ids[@]}" -gt 0 ]; then
  echo "warning: backlog task list 가 태스크 ${#hidden_ids[@]}건을 감추고 있다(아래 snapshot 의 '## hidden tasks')" >&2
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

# 감춰진 미완료 태스크를 목록 뒤에 붙인다. **Done 은 넣지 않는다** — 이 스냅샷의 상세는
# 미완료분이고, 완료된 것이 감춰진 것은 이 루프가 할 일이 아니다(경고에는 그대로 뜬다).
i=0
while [ "$i" -lt "${#hidden_ids[@]}" ]; do
  case "${hidden_lines[$i]}" in
    *" Done "*) ;;
    *)
      if ! contains_id "${hidden_ids[$i]}" ${ids[@]+"${ids[@]}"}; then
        ids+=("${hidden_ids[$i]}")
      fi
      ;;
  esac
  i=$((i + 1))
done

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
# **감춰진 것을 목록 바로 아래에 낸다.** 별도 섹션이라 소비하는 스킬이 '## tasks' 만 읽어도
# 깨지지 않고, 여기 줄이 있으면 그 목록을 믿으면 안 된다는 뜻이다.
printf '## hidden tasks (%d)\n' "${#hidden_ids[@]}"
if [ "${#hidden_ids[@]}" -gt 0 ]; then
  printf '%s\n' '⚠ backlog task list 에 안 나오지만 파일에는 있는 태스크다. 미완료분은 아래'
  printf '%s\n' '  상세에 함께 실려 있다 — 목록에 없다고 없는 일로 보지 말 것.'
  i=0
  while [ "$i" -lt "${#hidden_lines[@]}" ]; do
    printf '  %s\n' "${hidden_lines[$i]}"
    i=$((i + 1))
  done
fi
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
