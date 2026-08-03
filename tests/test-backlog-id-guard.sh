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

# 이미 push 된 태스크에 fix 를 돌려도 개명하지 않는다. 리모트에 있는 자기 사본을 충돌로
# 세면 커밋 태그·문서가 참조하는 번호가 조용히 옮겨진다(task-314).
published='backlog/tasks/task-7 - published.md'
printf '%s\n' '---' 'id: TASK-7' '---' >"$local_repo/$published"
git -C "$local_repo" add "$published"
git -C "$local_repo" commit -q -m published-task
git -C "$local_repo" push -q origin main
output=$(cd "$local_repo" && PATH="$fake_bin:$PATH" BACKLOG_ID_GUARD_NO_FETCH=1 \
  bash "$guard" fix TASK-7)
assert_contains "$output" 'ok=TASK-7'
assert_contains "$output" 'published=TASK-7'
assert_not_contains "$output" 'moved='
test -f "$local_repo/$published" || fail 'published task file was renamed'

# 커밋된 항목은 '더 큰 번호가 다른 데 있다' 는 이유로도 개명되지 않는다 — fix 의 판정은
# '이 번호가 max 인가' 라서 자기 충돌이 아니어도 개명 대상이 된다.
printf '%s\n' '---' 'id: TASK-8' '---' >"$local_repo/backlog/tasks/task-8 - higher.md"
output=$(cd "$local_repo" && PATH="$fake_bin:$PATH" BACKLOG_ID_GUARD_NO_FETCH=1 \
  bash "$guard" fix TASK-7 2>&1) && fail 'fix on a committed task should exit non-zero'
assert_contains "$output" 'error=committed TASK-7'
assert_not_contains "$output" 'moved='
test -f "$local_repo/$published" || fail 'committed task file was renamed'

# 커밋 뒤 상태만 바뀌어 dirty 인 태스크도 갓 만든 것이 아니다 — 그 경우가 실제로 조용히
# 개명됐다(kil9conf TASK-314 -> 317).
printf '%s\n' '---' 'id: TASK-7' 'status: In Progress' '---' >"$local_repo/$published"
output=$(cd "$local_repo" && PATH="$fake_bin:$PATH" BACKLOG_ID_GUARD_NO_FETCH=1 \
  bash "$guard" fix TASK-7 2>&1) && fail 'fix on a dirty committed task should exit non-zero'
assert_contains "$output" 'error=committed TASK-7'
test -f "$local_repo/$published" || fail 'dirty committed task file was renamed'
git -C "$local_repo" checkout -q -- "$published"
rm -f "$local_repo/backlog/tasks/task-8 - higher.md"

# 진짜 충돌(다른 머신이 같은 번호를 리모트에 올림)은 여전히 개명한다. 제목이 다르므로
# 파일명도 다르고, 위 제외 규칙에 걸리지 않는다.
git -C "$seed" fetch -q origin main
git -C "$seed" reset -q --hard origin/main
remote_only='backlog/tasks/task-9 - from-another-machine.md'
printf '%s\n' '---' 'id: TASK-9' '---' >"$seed/$remote_only"
git -C "$seed" add "$remote_only"
git -C "$seed" commit -q -m other-machine-task
git -C "$seed" push -q origin main
git -C "$local_repo" fetch -q origin
mine='backlog/tasks/task-9 - mine.md'
printf '%s\n' '---' 'id: TASK-9' '---' >"$local_repo/$mine"
output=$(cd "$local_repo" && PATH="$fake_bin:$PATH" BACKLOG_ID_GUARD_NO_FETCH=1 \
  bash "$guard" fix TASK-9)
assert_contains "$output" 'moved=TASK-9 -> TASK-10'
test -f "$local_repo/backlog/tasks/task-10 - mine.md" || fail 'colliding task was not renamed'

grep -q 'warning=unpublished' "$repo_root/claude/skills/references/backlog-basics.md" \
  || fail 'publication warning contract missing from shared backlog instructions'
for skill in add-task add-milestone init-backlog migrate-to-backlog start-backlog loop-backlog; do
  grep -q 'ID 가드' "$repo_root/claude/skills/$skill/SKILL.md" \
    || fail "ID guard missing from claude/$skill"
  grep -q 'ID 가드' "$repo_root/codex/skills/$skill/SKILL.md" \
    || fail "ID guard missing from codex/$skill"
done

echo 'ok: backlog ID publication warning'
