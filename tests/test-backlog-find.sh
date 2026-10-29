#!/bin/bash
# backlog-find.sh 가 archive·옛 completed·drafts·docs 까지 찾고, 단어 AND·접힌 제목·정렬·--max·종료
# 코드를 지키는지 본다(kil9conf task-550 — `backlog search` 는 활성 태스크만 색인하고 한글 퍼지가 샌다).
set -euo pipefail

repo_root=$(git rev-parse --show-toplevel)
find_cmd=$repo_root/claude/skills/references/backlog-find.sh
fixture=$(mktemp -d "${TMPDIR:-/tmp}/backlog-find.XXXXXX")
trap 'rm -rf "$fixture"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_eq() {
  [ "$1" = "$2" ] || fail "expected:
$2
got:
$1"
}

doc() {  # $1=상대 경로 $2=id $3=status(빈 값이면 생략) $4=title 줄(그대로) $5=본문
  mkdir -p "$fixture/backlog/${1%/*}"
  {
    printf '%s\n' '---' "id: $2"
    printf '%s\n' "$4"
    [ -z "$3" ] || printf 'status: %s\n' "$3"
    printf '%s\n' '---' '' "$5"
  } >"$fixture/backlog/$1"
}

doc "tasks/task-12 - 보드.md" TASK-12 "To Do" "title: 보드 태스크" "재시작 루프를 본다"
doc "archive/tasks/task-3 - 옛것.md" TASK-3 Done "title: 'Logitech 재시작'" "루프 원인"
doc "completed/task-7 - 더옛것.md" TASK-7 Done "title: >-
  접힌 제목
  둘째 줄" "LOGITECH 루프"
doc "drafts/draft-2 - 초안.md" DRAFT-2 Draft "title: 파일명 단축" "재시작 없음"
doc "docs/doc-5 - 문서.md" doc-5 "" "title: 문서 제목" "status: 본문의 가짜 상태
재시작 루프"
mkdir -p "$fixture/sub"

cd "$fixture/sub"   # 하위 디렉터리에서도 backlog 루트를 찾는다
out=$(bash "$find_cmd" 재시작 루프 | cut -f1-4)
assert_eq "$out" "$(printf '%s\t%s\t%s\t%s\n' \
  tasks TASK-12 'To Do' '보드 태스크' \
  docs doc-5 - '문서 제목' \
  archive/tasks TASK-3 Done 'Logitech 재시작')"

# 대소문자 무시 · 옛 completed/ · 접힌 제목(`>-` 뒤 줄을 잇는다) · 번호 큰 것 먼저(같은 폴더 아님 → 폴더 순)
out=$(bash "$find_cmd" logitech | cut -f1-4)
assert_eq "$out" "$(printf '%s\t%s\t%s\t%s\n' \
  archive/tasks TASK-3 Done 'Logitech 재시작' \
  completed TASK-7 Done '접힌 제목 둘째 줄')"

out=$(bash "$find_cmd" 단축 | cut -f1-2)
assert_eq "$out" "$(printf 'drafts\tDRAFT-2')"

out=$(bash "$find_cmd" --max 1 루프)
assert_eq "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" 2
case $out in *"# 총 4건 중 1건"*) ;; *) fail "--max 안내 줄이 없다: $out" ;; esac

rc=0; bash "$find_cmd" 없는단어xyz 2>/dev/null || rc=$?
assert_eq "$rc" 1
rc=0; bash "$find_cmd" 2>/dev/null || rc=$?
assert_eq "$rc" 64
rc=0; (cd / && bash "$find_cmd" 루프 2>/dev/null) || rc=$?
assert_eq "$rc" 2

echo "PASS: backlog-find"
