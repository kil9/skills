#!/usr/bin/env bash
# cleanup-tasks.sh — backlog 의 완료(Done) 태스크를 backlog/completed/ 로 비대화형 정리한다.
#
# 배경: `backlog cleanup` 은 age 플래그가 없는 대화형 전용이라 자동화가 안 된다. 이 스크립트는 같은
# 동작(완료 태스크를 completed 폴더로 이동)을 스크립트로 대체해 정책·기준을 인자로 받는다.
#
# 기본 정책(--today): 오늘(로컬 날짜) 완료한 Done 은 보드에 남기고 나머지 Done 을 git mv 로 이동한다.
# updated_date 는 backlog 이 UTC 로 기록하므로 로컬 날짜로 변환해 "오늘" 을 판단한다.
#
# 커밋은 backlog 경로만 대상으로 해 무관한 워킹트리 변경을 쓸어담지 않는다. push 는 하지 않는다
# (repo 관례에 따라 호출측이 결정 — 이 repo 는 직배포라 호출측에서 push).
#
# 사용:
#   cleanup-tasks.sh [--today | --all | --keep-recent=N] [--dry-run]
#   --today (기본)   : 오늘 완료분만 보드에 남기고 나머지 이동
#   --all            : Done 전부 이동(클린 슬레이트)
#   --keep-recent=N  : updated_date 최신 N 건만 남기고 나머지 이동
#   --dry-run, -n    : 실제 이동/커밋 없이 대상만 출력
# 종료코드: 0=성공(이동 0건 포함), 2=backlog repo 아님/인자 오류
set -euo pipefail

MODE="today"
KEEP_N=2
DRY=0

for a in "$@"; do
  case "$a" in
    --today) MODE="today" ;;
    --all) MODE="all" ;;
    --keep-recent=*) MODE="keep-recent"; KEEP_N="${a#*=}" ;;
    --dry-run|-n) DRY=1 ;;
    *) echo "unknown arg: $a" >&2; exit 2 ;;
  esac
done

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$REPO_ROOT" ] || { echo "git repo 아님" >&2; exit 2; }
cd "$REPO_ROOT"

TASKS_DIR="backlog/tasks"
DONE_DIR="backlog/completed"
[ -d "$TASKS_DIR" ] || { echo "backlog/tasks 없음 (backlog repo 아님)" >&2; exit 2; }
mkdir -p "$DONE_DIR"

# frontmatter 한 줄 값 추출(항상 exit 0; 없으면 빈 문자열). 앞뒤 따옴표 제거.
fm() { sed -n "s/^$1:[[:space:]]*//p" "$2" | head -1 | sed "s/^[\"']//; s/[\"']$//"; }

TODAY="$(date +%F)"

# Done 태스크 수집(파일\t로컬완료날짜)
rows=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ "$(fm status "$f")" = "Done" ] || continue
  up="$(fm updated_date "$f")"
  # Z 오프셋으로 넘긴다 — 타임존 '이름'(예: "... UTC")을 붙이면 GNU date 가 그 존을 출력에도
  # 적용해 변환이 일어나지 않고 UTC 날짜가 그대로 나온다(KST 새벽 완료분이 전날로 찍힘).
  d="$(date -d "${up}Z" +%F 2>/dev/null || echo "${up:0:10}")"
  rows+="${d}	${f}"$'\n'
done < <(find "$TASKS_DIR" -maxdepth 1 -name 'task-*.md' | sort)

rows="${rows%$'\n'}"
if [ -z "$rows" ]; then echo "Done 태스크 없음 — 정리할 것 없음"; exit 0; fi
total=$(printf '%s\n' "$rows" | grep -c . || true)

# 이동 대상 선정
declare -a MOVE=()
case "$MODE" in
  all)
    while IFS=$'\t' read -r d f; do [ -n "$f" ] && MOVE+=("$f"); done <<< "$rows" ;;
  today)
    while IFS=$'\t' read -r d f; do [ -n "$f" ] && [ "$d" != "$TODAY" ] && MOVE+=("$f"); done <<< "$rows" ;;
  keep-recent)
    idx=0
    while IFS=$'\t' read -r d f; do
      [ -n "$f" ] || continue
      idx=$((idx+1)); [ "$idx" -le "$KEEP_N" ] && continue
      MOVE+=("$f")
    done <<< "$(printf '%s\n' "$rows" | sort -r)" ;;
esac

keep=$(( total - ${#MOVE[@]} ))
echo "정책=$MODE  오늘=$TODAY  Done=$total  이동=${#MOVE[@]}  보드잔류=$keep"
if [ "${#MOVE[@]}" -eq 0 ]; then echo "이동 대상 없음"; exit 0; fi
for f in "${MOVE[@]}"; do echo "  → $(basename "$f")"; done

if [ "$DRY" -eq 1 ]; then echo "(dry-run: 실제 이동/커밋 안 함)"; exit 0; fi

for f in "${MOVE[@]}"; do git mv "$f" "$DONE_DIR/$(basename "$f")"; done

body=""
for f in "${MOVE[@]}"; do b="$(basename "${f%.md}")"; body+="- ${b}"$'\n'; done
git commit -q -m "backlog: 완료 태스크 ${#MOVE[@]}건 completed 폴더로 정리

${body}
정책=${MODE}. /cleanup-tasks 정리.

Co-Authored-By: Claude Opus 4.8 (1M context) <noreply@anthropic.com>" -- "$TASKS_DIR" "$DONE_DIR"

echo "커밋: $(git rev-parse --short HEAD)"
