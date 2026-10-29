#!/bin/bash
# cleanup-backlog.sh 가 Done 을 archive/tasks 로 옮기고(옛 completed/ 는 쓰지 않음), 마일스톤 완료 수에
# 옛 completed/ 정리분까지 세는지 본다(kil9conf task-548 — backlog.md 1.54 의 completed 흐름 폐지).
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
cleanup=$repo_root/claude/skills/cleanup-backlog/cleanup-backlog.sh
fixture=$(mktemp -d "${TMPDIR:-/tmp}/cleanup-backlog.XXXXXX")
trap 'rm -rf "$fixture"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  case $1 in
    *"$2"*) ;;
    *) fail "expected '$2' in: $1" ;;
  esac
}

task() {  # $1=디렉터리 $2=번호 $3=상태 $4=마일스톤(빈 값 가능)
  {
    printf '%s\n' '---' "id: TASK-$2" "title: t$2" "status: $3" "updated_date: '2026-01-0$2 00:00'"
    [ -z "$4" ] || printf 'milestone: %s\n' "$4"
    printf '%s\n' '---'
  } >"$1/task-$2 - t$2.md"
}

milestone() {
  printf '%s\n' '---' "id: $1" "title: \"$1 제목\"" '---' >"$fixture/backlog/milestones/$1 - x.md"
}

git init -q "$fixture"
git -C "$fixture" config user.name fixture
git -C "$fixture" config user.email fixture@example.com
mkdir -p "$fixture/backlog/tasks" "$fixture/backlog/completed" "$fixture/backlog/milestones"
task "$fixture/backlog/tasks" 1 Done m-1       # m-1: 남은 0 · 완료 1 → 아카이브
task "$fixture/backlog/tasks" 2 Done m-2       # m-2: To Do 가 남아 유지
task "$fixture/backlog/tasks" 3 "To Do" m-2
task "$fixture/backlog/tasks" 4 Done ""
task "$fixture/backlog/completed" 5 Done m-3   # m-3: 옛 completed/ 에만 완료분 → 아카이브
milestone m-1
milestone m-2
milestone m-3
milestone m-4                                  # m-4: 태스크 없는 신규 → 유지
git -C "$fixture" add backlog
git -C "$fixture" commit -q -m seed

out=$(cd "$fixture" && bash "$cleanup" --dry-run)
assert_contains "$out" "Done=3  이동=3"
assert_contains "$out" "⇒ m-1"
assert_contains "$out" "⇒ m-3"
case $out in *"⇒ m-2"* | *"⇒ m-4"*) fail "m-2·m-4 는 아카이브 대상이 아니다: $out" ;; esac
[ ! -e "$fixture/backlog/archive" ] || fail "dry-run 이 archive 디렉터리를 만들었다"

out=$(cd "$fixture" && bash "$cleanup")
for n in 1 2 4; do
  [ -e "$fixture/backlog/archive/tasks/task-$n - t$n.md" ] || fail "task-$n 이 archive/tasks 로 가지 않았다"
done
[ -e "$fixture/backlog/tasks/task-3 - t3.md" ] || fail "To Do 인 task-3 이 보드에서 빠졌다"
[ "$(ls "$fixture/backlog/completed")" = "task-5 - t5.md" ] || fail "completed/ 에 새 파일이 생겼다"
[ -e "$fixture/backlog/archive/milestones/m-1 - x.md" ] || fail "m-1 이 아카이브되지 않았다"
[ -e "$fixture/backlog/archive/milestones/m-3 - x.md" ] || fail "옛 completed/ 완료분을 세지 않아 m-3 이 남았다"
[ -e "$fixture/backlog/milestones/m-2 - x.md" ] || fail "m-2 가 아카이브됐다"
[ -e "$fixture/backlog/milestones/m-4 - x.md" ] || fail "신규 m-4 가 아카이브됐다"
[ -z "$(git -C "$fixture" status --porcelain)" ] || fail "옮긴 파일이 커밋되지 않았다"
assert_contains "$(git -C "$fixture" log -1 --format=%s)" "완료 태스크 3건 archive 로 정리"

out=$(cd "$fixture" && bash "$cleanup")
assert_contains "$out" "이동 대상 없음"

echo "PASS: cleanup-backlog"
