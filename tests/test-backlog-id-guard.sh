#!/bin/bash
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
guard=$repo_root/claude/skills/references/backlog-id-guard.sh
fixture_root=$(mktemp -d "${TMPDIR:-/tmp}/backlog-id-guard.XXXXXX")
trap 'rm -rf "$fixture_root"' EXIT

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

assert_not_contains() {
  case $1 in
    *"$2"*) fail "did not expect '$2' in: $1" ;;
    *) ;;
  esac
}

git_init() {
  git init -q "$1"
  git -C "$1" checkout -q -b main
  git -C "$1" config user.name fixture
  git -C "$1" config user.email fixture@example.com
}

fake_bin=$fixture_root/bin
bare=$fixture_root/github.git
seed=$fixture_root/seed
local_repo=$fixture_root/local
mkdir -p "$fake_bin"
printf '%s\n' '#!/bin/sh' 'exit 0' >"$fake_bin/backlog"
chmod +x "$fake_bin/backlog"

git init -q --bare "$bare"
git -C "$bare" symbolic-ref HEAD refs/heads/main
git_init "$seed"
mkdir -p "$seed/backlog/tasks" "$seed/backlog/archive/tasks"
printf '%s\n' '---' 'id: TASK-1' '---' >"$seed/backlog/tasks/task-1 - seed.md"
git -C "$seed" add 'backlog/tasks/task-1 - seed.md'
git -C "$seed" commit -q -m seed
git -C "$seed" remote add origin "$bare"
git -C "$seed" push -q -u origin main

git clone -q "$bare" "$local_repo"
git -C "$local_repo" config user.name fixture
git -C "$local_repo" config user.email fixture@example.com
git -C "$local_repo" remote set-url origin https://github.com/example/backlog-id-guard-fixture.git
git -C "$local_repo" config \
  url."file://$bare".insteadOf https://github.com/example/backlog-id-guard-fixture.git

output=$(cd "$local_repo" && PATH="$fake_bin:$PATH" BACKLOG_ID_GUARD_NO_FETCH=1 \
  bash "$guard" next task)
test "$output" = 'next=TASK-2' || fail "unexpected next output: $output"

task2='backlog/tasks/task-2 - pending.md'
printf '%s\n' '---' 'id: TASK-2' '---' >"$local_repo/$task2"
output=$(cd "$local_repo" && PATH="$fake_bin:$PATH" BACKLOG_ID_GUARD_NO_FETCH=1 \
  bash "$guard" fix TASK-2)
assert_contains "$output" 'ok=TASK-2'
assert_contains "$output" 'warning=unpublished id=TASK-2 reason=uncommitted'
assert_contains "$output" "path=$task2"

git -C "$local_repo" add "$task2"
output=$(cd "$local_repo" && PATH="$fake_bin:$PATH" BACKLOG_ID_GUARD_NO_FETCH=1 \
  bash "$guard" fix TASK-2)
assert_contains "$output" 'warning=unpublished id=TASK-2 reason=uncommitted'

git -C "$local_repo" commit -q -m local-only-task
output=$(cd "$local_repo" && PATH="$fake_bin:$PATH" BACKLOG_ID_GUARD_NO_FETCH=1 \
  bash "$guard" fix TASK-2)
assert_contains "$output" 'ok=TASK-2'
assert_contains "$output" 'warning=unpublished id=TASK-2 reason=not-on-github'

mkdir -p "$local_repo/backlog/archive/tasks"
printf '%s\n' '---' 'id: TASK-5' '---' >"$local_repo/backlog/archive/tasks/task-5 - archived.md"
task3='backlog/tasks/task-3 - collision.md'
printf '%s\n' '---' 'id: TASK-3' '---' >"$local_repo/$task3"
output=$(cd "$local_repo" && PATH="$fake_bin:$PATH" BACKLOG_ID_GUARD_NO_FETCH=1 \
  bash "$guard" fix TASK-3)
assert_contains "$output" 'moved=TASK-3 -> TASK-6'
assert_contains "$output" 'warning=unpublished id=TASK-6 reason=uncommitted'
assert_contains "$output" 'path=backlog/tasks/task-6 - collision.md'
assert_not_contains "$output" 'id=TASK-3 reason=uncommitted'
test -f "$local_repo/backlog/tasks/task-6 - collision.md" || fail 'renamed task file missing'
grep -q '^id: TASK-6$' "$local_repo/backlog/tasks/task-6 - collision.md" \
  || fail 'renamed task frontmatter was not updated'

grep -q 'warning=unpublished' "$repo_root/claude/skills/references/backlog-basics.md" \
  || fail 'publication warning contract missing from shared backlog instructions'
for skill in add-task add-milestone init-backlog migrate-to-backlog start-backlog loop-backlog; do
  grep -q 'ID 가드' "$repo_root/claude/skills/$skill/SKILL.md" \
    || fail "ID guard missing from claude/$skill"
  grep -q 'ID 가드' "$repo_root/codex/skills/$skill/SKILL.md" \
    || fail "ID guard missing from codex/$skill"
done

echo 'ok: backlog ID publication warning'
