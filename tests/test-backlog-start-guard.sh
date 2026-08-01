#!/bin/bash
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
guard=$repo_root/claude/skills/references/backlog-start-guard.sh
fixture_root=$(mktemp -d "${TMPDIR:-/tmp}/backlog-start-guard.XXXXXX")
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

git_init() {
  git init -q "$1"
  git -C "$1" checkout -q -b main
  git -C "$1" config user.name fixture
  git -C "$1" config user.email fixture@example.com
}

bare=$fixture_root/github.git
seed=$fixture_root/seed
local_repo=$fixture_root/local
peer=$fixture_root/peer
ghe=$fixture_root/ghe.git

git init -q --bare "$bare"
git init -q --bare "$ghe"
git_init "$seed"
mkdir -p "$seed/backlog/tasks"
printf '%s\n' 'id: TASK-1' 'status: To Do' >"$seed/backlog/tasks/task-1.md"
printf '%s\n' 'id: TASK-2' 'status: To Do' >"$seed/backlog/tasks/task-2.md"
git -C "$seed" add backlog/tasks/task-1.md backlog/tasks/task-2.md
git -C "$seed" commit -q -m seed
git -C "$seed" remote add origin "$bare"
git -C "$seed" push -q -u origin main

git clone -q "$bare" "$local_repo"
git -C "$local_repo" remote rename origin github
git -C "$local_repo" remote set-url github https://github.com/example/backlog-guard-fixture.git
git -C "$local_repo" config url."file://$bare".insteadOf https://github.com/example/backlog-guard-fixture.git
git -C "$local_repo" remote add ghe ssh://git@oss.navercorp.com/example/project.git
git -C "$local_repo" config url."file://$ghe".insteadOf ssh://git@oss.navercorp.com/example/project.git

git clone -q "$bare" "$peer"
git -C "$peer" config user.name fixture
git -C "$peer" config user.email fixture@example.com
printf '%s\n' 'id: TASK-1' 'status: Done' >"$peer/backlog/tasks/task-1.md"
git -C "$peer" add backlog/tasks/task-1.md
git -C "$peer" commit -q -m remote-task-change
git -C "$peer" push -q origin main

output=$(cd "$local_repo" && bash "$guard" TASK-1 TASK-2)
assert_contains "$output" 'remote=github fetch=ok'
assert_contains "$output" 'stale=TASK-1 ref=github/main commits=1'
assert_contains "$output" 'fresh=TASK-2'
if git -C "$local_repo" show-ref --verify --quiet refs/remotes/ghe/main; then
  fail 'non-GitHub remote was fetched'
fi

git -C "$local_repo" remote set-url github https://github.com/example/missing-fixture.git
git -C "$local_repo" config --unset-all url."file://$bare".insteadOf
git -C "$local_repo" config url."file://$fixture_root/missing.git".insteadOf https://github.com/example/missing-fixture.git
git -C "$local_repo" update-ref -d refs/remotes/github/main
output=$(cd "$local_repo" && BACKLOG_GUARD_FETCH_TIMEOUT=1 bash "$guard" TASK-1)
assert_contains "$output" 'remote=github fetch=failed'
assert_contains "$output" 'unknown=TASK-1 reason=fetch-failed'

git -C "$local_repo" remote remove github
output=$(cd "$local_repo" && bash "$guard" TASK-1)
assert_contains "$output" 'unknown=TASK-1 reason=no-github-remote'

for skill in \
  "$repo_root/claude/skills/start-backlog/SKILL.md" \
  "$repo_root/codex/skills/start-backlog/SKILL.md" \
  "$repo_root/claude/skills/loop-backlog/SKILL.md" \
  "$repo_root/codex/skills/loop-backlog/SKILL.md"; do
  grep -q '착수 신선도' "$skill" || fail "startup guard missing from $skill"
done

echo 'ok: backlog start guard'
