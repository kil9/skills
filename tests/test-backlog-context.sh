#!/bin/bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
script="$repo_root/claude/skills/references/backlog-context.sh"
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

mkdir -p "$fixture/bin" "$fixture/repo/backlog"
: > "$fixture/repo/backlog/config.yml"
log="$fixture/backlog.log"

cat > "$fixture/bin/backlog" <<'STUB'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "$BACKLOG_LOG"
case "$*" in
  "milestone list --plain --show-completed")
    [ "${BACKLOG_SCENARIO:-ok}" != milestone-fail ] || exit 9
    echo "Active milestones (1):"
    echo "  m-1: sample (0/2 done)"
    ;;
  "task list --plain")
    [ "${BACKLOG_SCENARIO:-ok}" != list-fail ] || exit 8
    cat <<'EOF'
To Do:
  [HIGH] TASK-1 - first
Done:
  TASK-2 - finished
Blocked:
  TASK-3 - blocked
EOF
    ;;
  "task view TASK-1 --plain")
    echo "Task TASK-1"
    echo "Status: To Do"
    ;;
  "task view TASK-3 --plain")
    [ "${BACKLOG_SCENARIO:-ok}" != view-fail ] || exit 7
    echo "Task TASK-3"
    echo "Status: Blocked"
    ;;
  *)
    echo "unexpected: $*" >&2
    exit 99
    ;;
esac
STUB
chmod +x "$fixture/bin/backlog"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_status() {
  local expected=$1 scenario=$2 cwd=$3 output status
  shift 3
  set +e
  output=$(cd "$cwd" && BACKLOG_LOG="$log" BACKLOG_SCENARIO="$scenario" \
    PATH="$fixture/bin:/usr/bin:/bin" "$script" "$@" 2>&1)
  status=$?
  set -e
  [ "$status" -eq "$expected" ] || fail "$scenario status=$status expected=$expected output=$output"
  printf '%s\n' "$output"
}

: > "$log"
output=$(assert_status 0 ok "$fixture/repo")
grep -q '^## backlog context$' <<< "$output" || fail "snapshot header"
grep -q '## unfinished task details (2)' <<< "$output" || fail "unfinished count"
grep -q '===== TASK-1 =====' <<< "$output" || fail "TASK-1 detail"
grep -q '===== TASK-3 =====' <<< "$output" || fail "TASK-3 detail"
if grep -q '===== TASK-2 =====' <<< "$output"; then
  fail "Done task detail must not be fetched"
fi
[ "$(grep -c '^task view ' "$log")" -eq 2 ] || fail "detail call count"

output=$(assert_status 0 ok "$fixture/repo" TASK-1)
grep -q '## unfinished task details (1)' <<< "$output" || fail "selected count"
grep -q '===== TASK-1 =====' <<< "$output" || fail "selected detail"
if grep -q '===== TASK-3 =====' <<< "$output"; then
  fail "unselected task detail must not be fetched"
fi

output=$(assert_status 2 ok "$fixture")
grep -q 'backlog/ 없음' <<< "$output" || fail "missing backlog message"

output=$(assert_status 4 milestone-fail "$fixture/repo")
grep -q 'milestone 조회 실패' <<< "$output" || fail "milestone failure message"

output=$(assert_status 5 list-fail "$fixture/repo")
grep -q 'task 목록 조회 실패' <<< "$output" || fail "list failure message"

output=$(assert_status 7 view-fail "$fixture/repo")
grep -q 'task 상세 조회 실패: TASK-3' <<< "$output" || fail "view failure message"

output=$(assert_status 6 ok "$fixture/repo" TASK-2)
grep -q '미완료 task가 아님: TASK-2' <<< "$output" || fail "selected Done task message"

output=$(assert_status 64 ok "$fixture/repo" task-1)
grep -q 'usage: backlog-context.sh' <<< "$output" || fail "malformed argument message"

set +e
output=$(cd "$fixture/repo" && PATH="/usr/bin:/bin" "$script" 2>&1)
status=$?
set -e
[ "$status" -eq 3 ] || fail "missing CLI status=$status"
grep -q 'backlog CLI 없음' <<< "$output" || fail "missing CLI message"

# Windows 셸이 PWD 를 D:\x\y 로 넘겨도 루트 탐색이 끝나야 한다(예전엔 무한 루프).
# Linux 에선 bash 가 맞지 않는 PWD 를 버리므로 이 구간이 그냥 통과한다.
# 맥에는 timeout(coreutils)이 없다 — 없으면 127 로 빠져 테스트가 엉뚱하게 실패했다. perl alarm 으로 대신한다.
with_timeout() { # with_timeout <초> <명령...>
  if command -v timeout >/dev/null 2>&1; then timeout "$@"
  elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$@"
  else perl -e 'alarm shift; exec @ARGV or exit 127' "$@"
  fi
}
winpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "${1//\//\\}"; fi; }
mkdir -p "$fixture/empty"
set +e
output=$(cd "$fixture/empty" && PWD=$(winpath "$fixture/empty") PATH="$fixture/bin:$PATH" with_timeout 20 "$script" 2>&1)
status=$?
set -e
[ "$status" -eq 2 ] || fail "windows PWD without backlog status=$status"
output=$(cd "$fixture/repo/backlog" && PWD=$(winpath "$fixture/repo/backlog") PATH="$fixture/bin:$PATH" \
  BACKLOG_LOG="$log" with_timeout 20 "$script" 2>&1) || fail "windows PWD inside backlog failed"
grep -q '^## tasks' <<< "$output" || fail "windows PWD inside backlog output"

echo "PASS: backlog-context"
