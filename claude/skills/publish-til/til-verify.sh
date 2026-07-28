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

# impeccable 디자인 가드(TASK-114). 새 페이지 디렉터리만 본다 — 기존 발행물은 이관 당시의 자체
# 스타일을 그대로 두기로 했고(TASK-113 triage), 전체를 걸면 새 글이 남의 잔재로 막힌다.
# advisory(em-dash 등)는 detect 가 애초에 exit code 에 반영하지 않으므로 여기서 걸러낼 것이 없다.
# 규칙 waive 목록은 repo 의 .impeccable/config.json(커밋됨)이 정본이다.
if [ -f DESIGN.md ] && command -v npx >/dev/null 2>&1; then
  out=$(npx impeccable detect "$reldir/" 2>&1) && r=0 || r=$?
  case "$r" in
    0) chk "impeccable detect (신규 페이지 0 failures)" 0 ;;
    2) # 위반. detect 는 failures 가 있을 때만 2 로 끝난다.
       echo "$out"; chk "impeccable detect (신규 페이지 0 failures)" 1 ;;
    *) # 미설치·네트워크 실패 등 실행 자체가 안 된 경우. 발행을 막지 않는다 — 이건 품질
       # 게이트지 정합성 게이트가 아니고, 하드 게이트는 site-check.py 가 따로 맡는다.
       # 대신 건너뛴 사실을 반드시 찍는다(조용히 통과시키지 않는다).
       echo "skip: impeccable detect 실행 불가(exit $r) — 'npx impeccable install' 로 설치" ;;
  esac
else
  echo "skip: impeccable detect (DESIGN.md 또는 npx 없음)"
fi

[ "$fail" -eq 0 ] && echo "verify ok: $reldir" || { echo "verify 실패 — FAIL 항목을 보정할 것" >&2; exit 1; }
