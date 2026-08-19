#!/bin/bash
# `backlog task list` 가 태스크를 조용히 감출 때 snapshot 이 그것을 잡는지 본다.
#
# ## 왜 이 검사가 필요한가
#
# CLI 가 다른 브랜치·리모트의 더 새로운 상태를 보고(`check_active_branches`·`remote_operations`)
# 파일 경로가 없어진 것을 '삭제됨' 으로 접는다. 2026-08-19 에 실측한 두 사례:
#
#   * 제목을 고쳐 **파일명이 바뀐** 태스크가 목록에서 사라졌다.
#   * 상태가 `To Do` 인 태스크 하나가 어느 상태 그룹에도 안 나왔다(원인 미확정).
#
# **증상이 조용하다는 것**이 문제다 — 드레인 루프가 '남은 일 없음' 으로 종료할 뻔했다.
# 그래서 목록을 믿기 전에 파일의 id 집합과 대조하고, 감춰진 미완료분은 상세까지 되살린다.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
script="$repo_root/claude/skills/references/backlog-context.sh"
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

mkdir -p "$fixture/bin" "$fixture/repo/backlog/tasks"
: > "$fixture/repo/backlog/config.yml"

# 목록에는 TASK-1 만 나온다. 파일은 넷이다 — 나머지 셋이 '감춰진 것' 이다.
cat > "$fixture/bin/backlog" <<'STUB'
#!/bin/bash
set -euo pipefail
case "$*" in
  "milestone list --plain --show-completed")
    echo "Active milestones (0):"
    ;;
  "task list --plain")
    printf 'To Do:\n  [HIGH] TASK-1 - visible\n'
    ;;
  "task view "*)
    id=${*#task view }
    id=${id% --plain}
    echo "Task $id"
    ;;
  *)
    echo "unexpected: $*" >&2
    exit 99
    ;;
esac
STUB
chmod +x "$fixture/bin/backlog"

write_task() {
  printf -- '---\nid: %s\nstatus: %s\n---\n' "$1" "$2" > "$fixture/repo/backlog/tasks/$3"
}

write_task TASK-1 "To Do" "task-1 - visible.md"
write_task TASK-2 "To Do" "task-2 - hidden-todo.md"
write_task TASK-9 Done "task-9 - hidden-done.md"
# ⚠ **접두가 겹치는 id.** 목록에 `TASK-1` 이 있다고 `TASK-13` 을 있는 것으로 세면 이 검사가
# 조용히 반쪽이 된다 — 그 자리를 여기서 못박는다.
write_task TASK-13 Blocked "task-13 - hidden-blocked.md"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

set +e
output=$(cd "$fixture/repo" && PATH="$fixture/bin:/usr/bin:/bin" "$script" 2>"$fixture/err")
status=$?
set -e
[ "$status" -eq 0 ] || fail "감춤이 있어도 스냅샷은 성공해야 한다(status=$status)"

grep -q '## hidden tasks (3)' <<< "$output" || fail "감춘 건수: $(grep '## hidden tasks' <<< "$output")"
grep -q 'TASK-2 To Do' <<< "$output" || fail "감춰진 To Do 가 목록에 없다"
grep -q 'TASK-13 Blocked' <<< "$output" || fail "접두가 겹치는 id 를 놓쳤다"
grep -q 'TASK-9 Done' <<< "$output" || fail "감춰진 Done 도 보고해야 한다"
grep -q 'warning: backlog task list 가 태스크 3건을 감추고' "$fixture/err" \
  || fail "stderr 경고가 없다: $(cat "$fixture/err")"

# **감춰진 미완료분은 상세까지 되살린다** — 경고만 하고 빠뜨리면 이 검사가 반쪽이다.
grep -q '## unfinished task details (3)' <<< "$output" || fail "되살린 상세 수가 틀리다"
for id in TASK-1 TASK-2 TASK-13; do
  grep -q "===== $id =====" <<< "$output" || fail "$id 상세가 없다"
done
# Done 은 되살리지 않는다(이 스냅샷의 상세는 미완료분이다).
if grep -q '===== TASK-9 =====' <<< "$output"; then
  fail "감춰진 Done 의 상세까지 끌어오면 안 된다"
fi

# 감춤이 없으면 조용하다 — 이 검사가 평소에 소음을 내면 아무도 안 읽는다.
rm "$fixture/repo/backlog/tasks/task-2 - hidden-todo.md" \
   "$fixture/repo/backlog/tasks/task-9 - hidden-done.md" \
   "$fixture/repo/backlog/tasks/task-13 - hidden-blocked.md"
output=$(cd "$fixture/repo" && PATH="$fixture/bin:/usr/bin:/bin" "$script" 2>"$fixture/err")
grep -q '## hidden tasks (0)' <<< "$output" || fail "감춤 0 건일 때 표기"
[ ! -s "$fixture/err" ] || fail "감춤이 없는데 경고가 났다: $(cat "$fixture/err")"

# `backlog/tasks/` 가 없어도 죽지 않는다(완료분만 남은 저장소).
rm -r "$fixture/repo/backlog/tasks"
output=$(cd "$fixture/repo" && PATH="$fixture/bin:/usr/bin:/bin" "$script" 2>/dev/null)
grep -q '## hidden tasks (0)' <<< "$output" || fail "tasks 디렉터리 부재"

echo "ok: backlog hidden-task guard"
