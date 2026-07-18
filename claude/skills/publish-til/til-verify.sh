#!/bin/bash
# /publish-til §5 검증: 새 페이지 필수 요소·목록 일관성 grep 일괄. repo 루트에서 실행.
# 사용법: til-verify.sh <reldir>   (예: 2026/my-post 또는 p/my-page)
set -euo pipefail

reldir=${1:?사용법: til-verify.sh <reldir>  예: 2026/my-post}
reldir=${reldir%/}
slug=$(basename "$reldir")
f="$reldir/index.html"
fail=0

chk() { # chk <라벨> <성공(0)/실패(비0)>
  if [ "$2" -eq 0 ]; then echo "ok: $1"; else echo "FAIL: $1"; fail=1; fi
}

[ -f "$f" ] || { echo "FAIL: $f 없음" >&2; exit 1; }
head -1 "$f" | grep -qi '^<!doctype html' && r=0 || r=$?; chk "doctype" "$r"
grep -qi 'rel="icon"'          "$f" && r=0 || r=$?; chk 'rel="icon" (favicon)' "$r"
grep -qi 'og:title'            "$f" && r=0 || r=$?; chk "og:title 메타" "$r"
grep -q  'cloudflareinsights'  "$f" && r=0 || r=$?; chk "Cloudflare beacon" "$r"
grep -q  "$reldir/"      index.html && r=0 || r=$?; chk "루트 index.html 갤러리 카드가 $reldir/ 참조" "$r"
grep -q  "$reldir/"       README.md && r=0 || r=$?; chk "README 표가 $reldir/ 참조" "$r"

[ "$fail" -eq 0 ] && echo "verify ok: $reldir" || { echo "verify 실패 — FAIL 항목을 보정할 것" >&2; exit 1; }
