#!/bin/bash
# /commit 스킬용 컨텍스트 수집 스크립트: 커밋 판단에 필요한 정보를 한 번에 출력한다.
# (status, 최근 커밋 스타일, tracked diff, untracked 파일 내용 미리보기)
set -euo pipefail

DIFF_CAP=200000   # bytes — 과대 diff 로 컨텍스트가 터지는 것 방지
FILE_CAP=20000    # bytes — untracked 파일당 미리보기 상한

# core.quotepath 기본값이 한글 등 non-ASCII 경로를 "\353.." 로 이스케이프해,
# 그 문자열을 파일명으로 쓰는 untracked 미리보기가 head 실패 → set -e 로 전체 중단됐다.
git() { command git -c core.quotepath=off "$@"; }

echo "## status"
git status --short

echo
echo "## recent commits (메시지 스타일 참고)"
git log --oneline -8 2>/dev/null || echo "(커밋 없음)"

if git rev-parse -q --verify HEAD >/dev/null; then
  echo
  echo "## diff --stat (tracked)"
  git diff HEAD --stat
  echo
  echo "## diff (tracked)"
  out=$({ git diff HEAD || true; } | head -c "$DIFF_CAP")
  printf '%s\n' "$out"
  [ "${#out}" -lt "$DIFF_CAP" ] || echo "... (diff ${DIFF_CAP}B 에서 절단 — 필요한 파일만 git diff HEAD -- <path> 로 추가 확인)"
fi

if [ -n "$(git ls-files --others --exclude-standard)" ]; then
  echo
  echo "## untracked files"
  # NUL 구분(-z)이라 따옴표·개행이 든 파일명도 안전하다.
  while IFS= read -r -d '' f; do
    echo "--- $f ---"
    if [ -L "$f" ]; then
      echo "(symlink → $(readlink "$f"))"
    elif file --mime "$f" 2>/dev/null | grep -q 'charset=binary'; then
      echo "(binary, $(wc -c <"$f") bytes)"
    else
      head -c "$FILE_CAP" "$f"
      echo
      [ "$(wc -c <"$f")" -le "$FILE_CAP" ] || echo "... (${FILE_CAP}B 에서 절단)"
    fi
  done < <(git ls-files --others --exclude-standard -z)
fi
