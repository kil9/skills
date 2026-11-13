#!/usr/bin/env bash
# check-backlog.sh — 정리 전에 backlog 데이터의 어긋남을 찾고, 기계적으로 고칠 수 있는 것은 고친다.
#
# 배경: task-87 이 milestone 을 id(m-11) 대신 제목으로 적어 두었고, 남은 태스크를 id 로만 세는 보관
# 판정이 진행 중인 m-11 을 보관했다(workflow repo, 2026-11-02). 보드에는 보관된 마일스톤 아래 진행 중
# 태스크가 매달리고 id 칸에 긴 제목이 접혀 그려졌다. 증상이 보드에서만 보여 정리할 때 함께 본다.
#
# 고치는 것(--fix):
#   F1 태스크 milestone 이 제목으로 적힘   → 제목이 마일스톤 하나와 정확히 맞으면 id 로 바꾼다
#   F2 Done 아닌 태스크가 보관된 마일스톤을 가리킴 → 마일스톤을 backlog/milestones/ 로 되돌린다
# 알리기만 하는 것(판단이 필요):
#   R1 milestone 값이 어떤 마일스톤과도 안 맞음
#   R2 status 가 config.yml 의 statuses 밖
#   R3 파일의 id 가 `backlog task list` 에 안 나옴(CLI 의 git 인식이 조용히 감추는 경우)
#   R4 `backlog doctor` 가 중복 ID·순환 의존을 보고함
#
# 사용: check-backlog.sh [--fix]
# 출력 끝줄: "정합성: 고침 N · 확인 필요 M". 고친 파일은 그 경로만 커밋한다(push 안 함).
# 종료코드: 0=성공(문제 유무와 무관), 2=backlog repo 아님
set -euo pipefail

FIX=0
for a in "$@"; do
  case "$a" in
    --fix) FIX=1 ;;
    *) echo "unknown arg: $a" >&2; exit 2 ;;
  esac
done

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$REPO_ROOT" ] || { echo "git repo 아님" >&2; exit 2; }
cd "$REPO_ROOT"
TASKS_DIR="backlog/tasks"
MS_DIR="backlog/milestones"
MS_ARCHIVE="backlog/archive/milestones"
[ -d "$TASKS_DIR" ] || { echo "backlog/tasks 없음 (backlog repo 아님)" >&2; exit 2; }

fm() { sed -n "s/^$1:[[:space:]]*//p" "$2" | head -1 | sed "s/^[\"']//; s/[\"']$//"; }

# 마일스톤 표: id\t제목\t상태(active|archived)\t파일
ms_rows=""
for d in "$MS_DIR" "$MS_ARCHIVE"; do
  [ -d "$d" ] || continue
  state=active; [ "$d" = "$MS_ARCHIVE" ] && state=archived
  for f in "$d"/*.md; do
    [ -e "$f" ] || continue
    id="$(fm id "$f")"; [ -n "$id" ] || id="$(basename "$f" | sed 's/ .*//')"
    ms_rows+="${id}	$(fm title "$f")	${state}	${f}"$'\n'
  done
done
ms_by_id()    { printf '%s' "$ms_rows" | awk -F'\t' -v k="$1" '$1==k'; }
ms_by_title() { printf '%s' "$ms_rows" | awk -F'\t' -v k="$1" '$2==k'; }

statuses="$(sed -n 's/^statuses:[[:space:]]*//p' backlog/config.yml 2>/dev/null | tr -d '[]"' | tr ',' '\n' | sed 's/^ *//; s/ *$//')"

fixed=0; review=0
declare -a COMMIT_PATHS=()
declare -a RESTORED=()

for f in "$TASKS_DIR"/task-*.md; do
  [ -e "$f" ] || continue
  tid="$(fm id "$f")"; st="$(fm status "$f")"; ms="$(fm milestone "$f")"

  if [ -n "$statuses" ] && ! printf '%s\n' "$statuses" | grep -Fxq -- "$st"; then
    echo "  ? R2 $tid status '$st' 가 config 의 statuses 밖"; review=$((review+1))
  fi
  [ -n "$ms" ] || continue

  row="$(ms_by_id "$ms")"
  if [ -z "$row" ]; then
    hits="$(ms_by_title "$ms")"
    n=0; [ -n "$hits" ] && n=$(printf '%s\n' "$hits" | grep -c .)
    if [ "$n" -eq 1 ]; then
      mid="$(printf '%s' "$hits" | cut -f1)"
      echo "  ✎ F1 $tid milestone '$ms' → $mid"
      if [ "$FIX" -eq 1 ]; then
        tmp="$(mktemp)"; awk -v id="$mid" '!done && /^milestone:/{print "milestone: " id; done=1; next}1' "$f" > "$tmp" && cat "$tmp" > "$f" && rm -f "$tmp"
        COMMIT_PATHS+=("$f")
      fi
      fixed=$((fixed+1)); row="$hits"
    else
      echo "  ? R1 $tid milestone '$ms' 가 어떤 마일스톤과도 안 맞음(제목 일치 ${n}건)"; review=$((review+1))
      continue
    fi
  fi

  if [ "$st" != "Done" ] && [ "$(printf '%s' "$row" | cut -f3)" = "archived" ]; then
    mf="$(printf '%s' "$row" | cut -f4)"; mid="$(printf '%s' "$row" | cut -f1)"
    case " ${RESTORED[*]-} " in *" $mid "*) continue ;; esac
    RESTORED+=("$mid")
    echo "  ✎ F2 $mid 는 보관됐지만 $tid($st)가 남아 있음 → backlog/milestones/ 로 복원"
    if [ "$FIX" -eq 1 ]; then
      dst="$MS_DIR/$(basename "$mf")"; mkdir -p "$MS_DIR"
      if git ls-files --error-unmatch -- "$mf" >/dev/null 2>&1; then git mv "$mf" "$dst"; COMMIT_PATHS+=("$mf" "$dst")
      else mv "$mf" "$dst"; fi
    fi
    fixed=$((fixed+1))
  fi
done

# R3: 파일 id 집합 ⊆ CLI 목록 id 집합
if command -v backlog >/dev/null 2>&1; then
  listed="$(backlog task list --plain 2>/dev/null | grep -oE 'TASK-[0-9.]+' | tr 'A-Z' 'a-z' | sort -u || true)"
  for f in "$TASKS_DIR"/task-*.md; do
    [ -e "$f" ] || continue
    tid="$(fm id "$f" | tr 'A-Z' 'a-z')"
    [ "$(fm status "$f")" = "Done" ] && continue
    if ! printf '%s\n' "$listed" | grep -Fxq -- "$tid"; then
      echo "  ? R3 $tid 파일은 있는데 'backlog task list' 에 안 나옴"; review=$((review+1))
    fi
  done
  doc="$(timeout 120 backlog doctor 2>&1 || true)"
  if ! printf '%s' "$doc" | grep -q "^No duplicate IDs"; then
    echo "  ? R4 backlog doctor 보고:"; printf '%s\n' "$doc" | sed 's/^/      /' | head -20; review=$((review+1))
  fi
fi

echo "정합성: 고침 ${fixed} · 확인 필요 ${review}$([ "$FIX" -eq 0 ] && [ "$fixed" -gt 0 ] && echo ' (미적용 — --fix 로 고친다)')"

if [ "$FIX" -eq 1 ] && [ "${#COMMIT_PATHS[@]}" -gt 0 ]; then
  git commit -q -m "backlog: 정합성 ${fixed}건 수정 (/cleanup-backlog)

마일스톤 참조를 id 로 고치고, 진행 중 태스크가 남은 보관 마일스톤을 되돌린다.

Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>" -- "${COMMIT_PATHS[@]}"
  echo "커밋: $(git rev-parse --short HEAD)"
fi
