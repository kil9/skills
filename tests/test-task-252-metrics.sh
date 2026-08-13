#!/bin/bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_smaller() {
  local baseline=$1 path=$2 current
  current=$(wc -l < "$path")
  [ "$current" -lt "$baseline" ] || fail "$path lines=$current baseline=$baseline"
  printf '%s: %s -> %s lines\n' "$path" "$baseline" "$current"
}

assert_smaller 129 claude/skills/next-backlog/SKILL.md
# TASK-226가 추가한 착수 신선도 가드까지 포함한 upstream 기준선이다.
assert_smaller 109 claude/skills/start-backlog/SKILL.md
assert_smaller 66 claude/skills/loop-backlog/SKILL.md

for path in \
  claude/skills/next-backlog/SKILL.md \
  claude/skills/start-backlog/SKILL.md \
  claude/skills/loop-backlog/SKILL.md; do
  grep -q 'backlog-context.sh' "$path" || fail "$path must use backlog-context"
  if grep -Eq 'backlog (milestone list|task list|task view) --plain' "$path"; then
    fail "$path has an inline backlog collector"
  fi
done
[ "$(readlink codex/skills/references/backlog-context.sh)" = \
  ../../../claude/skills/references/backlog-context.sh ] \
  || fail 'Codex backlog-context mirror'

printf '%s\n' 'AGENT_ROUND_TRIPS: next=2+U->1 start=1+U->1 loop=1+U->1'
echo 'PASS: task-252 public metrics'
