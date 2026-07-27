#!/usr/bin/env bash
# cleanup-backlog.sh — backlog 의 완료(Done) 태스크를 backlog/completed/ 로 비대화형 정리한다.
#
# 배경: `backlog cleanup` 은 age 플래그가 없는 대화형 전용이라 자동화가 안 된다. 이 스크립트는 같은
# 동작(완료 태스크를 completed 폴더로 이동)을 스크립트로 대체해 정책·기준을 인자로 받는다.
#
# 기본 정책(--all): Done 을 전부 git mv 로 이동한다(완료 시각과 무관하게 클린 슬레이트).
# --today 를 주면 오늘(로컬 날짜) 완료분만 보드에 남긴다. updated_date 는 backlog 이 UTC 로 기록하므로
# 로컬 날짜로 변환해 "오늘" 을 판단한다.
#
# 커밋은 backlog 경로만 대상으로 해 무관한 워킹트리 변경을 쓸어담지 않는다. push 는 하지 않는다
# (repo 관례에 따라 호출측이 결정 — 이 repo 는 직배포라 호출측에서 push).
#
# 사용:
#   cleanup-backlog.sh [--today | --all | --keep-recent=N] [--dry-run]
#   --all (기본)     : Done 전부 이동(클린 슬레이트)
#   --today          : 오늘 완료분만 보드에 남기고 나머지 이동
#   --keep-recent=N  : updated_date 최신 N 건만 남기고 나머지 이동
#   --dry-run, -n    : 실제 이동/커밋 없이 대상만 출력
# 종료코드: 0=성공(이동 0건 포함), 2=backlog repo 아님/인자 오류
set -euo pipefail

MODE="all"
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

# UTC 타임스탬프('YYYY-MM-DD HH:MM')를 로컬 날짜로. Z 오프셋으로 넘긴다 — 타임존 '이름'
# (예: "... UTC")을 붙이면 GNU date 가 그 존을 출력에도 적용해 변환이 일어나지 않고 UTC
# 날짜가 그대로 나온다(KST 새벽 완료분이 전날로 찍힘). date -d 가 없는 BSD 는 앞 10자로 폴백.
utc_to_local_date() { date -d "${1}Z" +%F 2>/dev/null || echo "${1:0:10}"; }

# Done 태스크 수집(파일\t로컬완료날짜)
#
# **빈 타임스탬프를 date 에 넘기지 않는다.** `date -d "Z"` 는 에러가 아니라 '지금'으로 파싱돼
# 그 태스크가 매번 오늘로 찍히고, --today 정책에서 영영 이동하지 않은 채 보드에 박힌다.
# 실패가 조용한 것이 문제다 — "이동 0건"이 정상 결과와 구별되지 않는다(kil9conf task-217,
# 실물은 backlog CLI 가 만든 뒤 한 번도 edit 되지 않고 Done 이 된 태스크). 그래서
# updated_date → created_date → 파일 mtime 순으로 폴백하고, 폴백했으면 반드시 말한다.
rows=""
fallbacks=""
while IFS= read -r f; do
  [ -n "$f" ] || continue
  [ "$(fm status "$f")" = "Done" ] || continue
  up="$(fm updated_date "$f")"
  if [ -n "$up" ]; then
    d="$(utc_to_local_date "$up")"
  else
    cr="$(fm created_date "$f")"
    if [ -n "$cr" ]; then
      d="$(utc_to_local_date "$cr")"
      fallbacks+="  ! $(basename "$f"): updated_date 없음 → created_date($cr) 사용"$'\n'
    else
      # 둘 다 없으면 파일 mtime. GNU·BSD 둘 다 date -r <file> 을 지원한다.
      d="$(date -r "$f" +%F 2>/dev/null || echo "$TODAY")"
      fallbacks+="  ! $(basename "$f"): updated_date·created_date 둘 다 없음 → 파일 mtime($d) 사용"$'\n'
    fi
  fi
  rows+="${d}	${f}"$'\n'
done < <(find "$TASKS_DIR" -maxdepth 1 -name 'task-*.md' | sort)

rows="${rows%$'\n'}"
total=0
[ -n "$rows" ] && total=$(printf '%s\n' "$rows" | grep -c . || true)

# 이동 대상 선정
declare -a MOVE=()
if [ -n "$rows" ]; then
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
fi

keep=$(( total - ${#MOVE[@]} ))
echo "정책=$MODE  오늘=$TODAY  Done=$total  이동=${#MOVE[@]}  보드잔류=$keep"
# 날짜를 폴백으로 정한 태스크는 반드시 드러낸다 — 조용히 넘어가면 그 태스크가 왜 안 움직이는지
# (또는 왜 움직였는지) 알 길이 없다.
[ -n "$fallbacks" ] && printf '%s' "$fallbacks"
for f in "${MOVE[@]}"; do echo "  → $(basename "$f")"; done

# ── 다 끝난 마일스톤 아카이브 ────────────────────────────────────────────────
#
# 마일스톤 카운터(`backlog milestone list`)는 backlog/tasks/ 에 있는 태스크만 센다.
# 그래서 위에서 완료 태스크를 completed/ 로 옮기는 순간 그 마일스톤은 0/0 이 되어
# **끝난 것과 아직 시작 안 한 것이 보드에서 똑같이 보인다**(2026-07-27 실제로 m-7·m-9·
# m-10 이 '껍데기 마일스톤'으로 오인됐다 — 셋 다 완료 태스크 8·7·3건을 가진 완료분이었다).
# 태스크 정리가 만든 문제이므로 같은 자리에서 함께 처리한다.
#
# 판정: 남은 태스크 0건 **이고** completed/ 에 그 마일스톤 태스크가 1건 이상.
# 뒤 조건이 핵심이다 — 양쪽 다 0 이면 태스크를 아직 안 붙인 **신규** 마일스톤이라
# 아카이브하면 안 된다(/add-milestone 이 마일스톤을 먼저 만들고 태스크를 나중에 붙인다).
# 아카이브는 CLI(`backlog milestone archive`)와 같은 동작인 단순 파일 이동이다.
MS_DIR="backlog/milestones"
MS_ARCHIVE="backlog/archive/milestones"

# 이동 예정 파일은 아직 tasks/ 에 있으므로 잔여 계산에서 미리 뺀다(dry-run 도 같은 답을 낸다).
# 파일명에 공백이 들어가므로 줄 단위로 담고 -Fx 로 통째 비교한다.
moving_list="$(printf '%s\n' "${MOVE[@]-}")"

count_ms() {  # $1=디렉터리 $2=마일스톤id $3=제외 목록(줄 단위, 빈 값 가능)
  local n=0 f
  for f in "$1"/task-*.md; do
    [ -e "$f" ] || continue
    if [ -n "$3" ] && printf '%s\n' "$3" | grep -Fxq -- "$f"; then continue; fi
    if [ "$(fm milestone "$f")" = "$2" ]; then n=$((n+1)); fi
  done
  echo "$n"
}

declare -a MS_MOVE=()
if [ -d "$MS_DIR" ]; then
  for msf in "$MS_DIR"/*.md; do
    [ -e "$msf" ] || continue
    mid="$(fm id "$msf")"
    [ -n "$mid" ] || mid="$(basename "$msf" | sed 's/ .*//')"
    left="$(count_ms "$TASKS_DIR" "$mid" "$moving_list")"
    [ "$left" -eq 0 ] || continue
    # completed/ 에 이미 있는 것 + 이번에 옮겨질 것. 뒤엣것을 빼먹으면 첫 정리에서
    # 막 끝난 마일스톤이 '완료 0건' 으로 보여 영영 아카이브되지 않는다.
    done_n="$(count_ms "$DONE_DIR" "$mid" "")"
    for mf in "${MOVE[@]-}"; do
      [ -n "$mf" ] || continue
      if [ "$(fm milestone "$mf")" = "$mid" ]; then done_n=$((done_n+1)); fi
    done
    [ "$done_n" -gt 0 ] || continue     # 신규 빈 마일스톤은 건드리지 않는다
    MS_MOVE+=("$msf")
    echo "  ⇒ $mid $(fm title "$msf") — 남은 태스크 0, 완료 ${done_n}건 → 아카이브"
  done
fi

if [ "${#MOVE[@]}" -eq 0 ] && [ "${#MS_MOVE[@]}" -eq 0 ]; then
  echo "이동 대상 없음"; exit 0
fi
if [ "$DRY" -eq 1 ]; then echo "(dry-run: 실제 이동/커밋 안 함)"; exit 0; fi

for f in "${MOVE[@]}"; do git mv "$f" "$DONE_DIR/$(basename "$f")"; done
if [ "${#MS_MOVE[@]}" -gt 0 ]; then
  mkdir -p "$MS_ARCHIVE"
  for f in "${MS_MOVE[@]}"; do git mv "$f" "$MS_ARCHIVE/$(basename "$f")"; done
fi

# 커밋 범위는 우리가 옮긴 파일의 옛/새 경로만 준다. 디렉터리를 주면 (a) 보드를 완전히
# 비운 뒤 재실행할 때 빈 backlog/tasks 가 'pathspec did not match' 로 죽고, (b) 옆
# 세션이 backlog 에 만들어 둔 다른 변경까지 쓸어담는다.
declare -a COMMIT_PATHS=()
for f in "${MOVE[@]-}"; do
  [ -n "$f" ] || continue
  COMMIT_PATHS+=("$f" "$DONE_DIR/$(basename "$f")")
done
for f in "${MS_MOVE[@]-}"; do
  [ -n "$f" ] || continue
  COMMIT_PATHS+=("$f" "$MS_ARCHIVE/$(basename "$f")")
done

subject="backlog: 완료 태스크 ${#MOVE[@]}건 completed 폴더로 정리"
if [ "${#MS_MOVE[@]}" -gt 0 ]; then
  subject="$subject · 완료 마일스톤 ${#MS_MOVE[@]}건 아카이브"
fi
body=""
for f in "${MOVE[@]}"; do b="$(basename "${f%.md}")"; body+="- ${b}"$'\n'; done
for f in "${MS_MOVE[@]}"; do b="$(basename "${f%.md}")"; body+="- (마일스톤) ${b}"$'\n'; done
git commit -q -m "$subject

${body}
정책=${MODE}. /cleanup-backlog 정리.

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>" -- "${COMMIT_PATHS[@]}"

echo "커밋: $(git rev-parse --short HEAD)"
