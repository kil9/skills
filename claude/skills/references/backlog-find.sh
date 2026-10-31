#!/bin/bash
# backlog 의 과거 작업·문서를 찾는다 — 에이전트용. `backlog search` 대신 쓴다.
#
# `backlog search`(1.55.3)는 활성 tasks·docs·decisions 만 색인하고(archive·옛 completed·drafts 제외),
# Fuse.js 퍼지 매칭(threshold 0.35)이라 짧은 한글 쿼리는 한 글자가 달라도 통과해 결과가 노이즈로 찬다
# (kil9conf task-550 실측: "파일명" → 무관 44건·정답 0, "Logitech" → archive 의 task-395 놓침).
# 이 명령은 backlog/ 아래 마크다운 전부를 대소문자 무시 고정 문자열로 찾고, 단어가 여럿이면 전부 든
# 파일만 남긴다(AND, 같은 줄일 필요는 없다). 색인이 없어 늘 최신이고, 수백 파일이면 즉시 끝난다.
#
# 사용법: backlog-find.sh [--max N] <단어> [단어 ...]
# 출력: 한 파일에 한 줄 — `<폴더>\t<ID>\t<상태>\t<제목>\t<경로>`. 폴더는 backlog/ 아래 상대 디렉터리
#       (tasks·drafts·decisions·docs·milestones·archive/tasks·completed 등)이고, 상태가 없는 문서는 `-`.
#       보드에 있는 폴더가 먼저, 같은 폴더 안에서는 번호가 큰(최근) 것부터 나온다. N 건(기본 30)을
#       넘으면 마지막 줄에 `# 총 M건 중 N건` 을 붙인다 — 단어를 더해 좁힌다.
# 종료 코드: 0 찾음, 1 없음, 2 backlog 부재, 64 사용법 오류.
set -euo pipefail

usage() {
  echo "usage: backlog-find.sh [--max N] <단어> [단어 ...]" >&2
  exit 64
}

max=30
words=()
while [ $# -gt 0 ]; do
  case "$1" in
    --max)
      [ $# -ge 2 ] || usage
      max=$2
      shift 2
      ;;
    --max=*) max=${1#*=}; shift ;;
    --) shift; break ;;
    -*) usage ;;
    *) words+=("$1"); shift ;;
  esac
done
while [ $# -gt 0 ]; do words+=("$1"); shift; done
case "$max" in ''|*[!0-9]*) usage ;; esac
[ "${#words[@]}" -gt 0 ] || usage

find_backlog_root() {
  local dir parent
  # Windows 셸이 넘긴 PWD(D:\x\y)는 '/' 가 없어 ${dir%/*} 가 줄지 않아 무한 루프였다 —
  # 구분자를 '/' 로 바꾸고, 더 줄지 않으면(D: 나 /) 끝낸다.
  dir=${PWD//\\//}
  while :; do
    if [ -d "$dir/backlog" ]; then
      printf '%s\n' "$dir"
      return 0
    fi
    case $dir in */*) parent=${dir%/*} ;; *) return 1 ;; esac
    [ -n "$parent" ] || parent=/
    [ "$parent" != "$dir" ] || return 1
    dir=$parent
  done
}

if ! root=$(find_backlog_root); then
  echo "backlog/ 없음" >&2
  exit 2
fi
cd "$root"

# 첫 단어로 후보를 모으고 나머지 단어로 거른다. 파일명에 공백이 있어 줄 단위로 다룬다(개행은 없다).
# grep 만 쓰는 이유: rg 가 없는 머신이 있고, 맥 기본 bash 3.2 에서도 돌아야 한다.
hits=$(grep -rliF --include='*.md' -- "${words[0]}" backlog 2>/dev/null) || true
for w in "${words[@]:1}"; do
  [ -n "$hits" ] || break
  hits=$(printf '%s\n' "$hits" | while IFS= read -r f; do
    if grep -qiF -- "$w" "$f"; then printf '%s\n' "$f"; fi
  done) || true
done
[ -n "$hits" ] || { echo "일치 없음: ${words[*]}" >&2; exit 1; }

# frontmatter 값(없으면 빈 문자열). 앞뒤 따옴표를 뗀다. 긴 제목은 CLI 가 YAML 접힌 블록(`title: >-`
# 뒤 들여쓴 줄들)으로 쓰므로 그 줄들을 공백으로 잇는다. frontmatter 밖 본문의 같은 키는 보지 않는다.
fm() {
  awk -v k="$1" '
    NR == 1 { if ($0 == "---") next; exit }
    $0 == "---" { exit }
    grab { if ($0 ~ /^[ \t]/) { sub(/^[ \t]+/, ""); v = v (v == "" ? "" : " ") $0; next } exit }
    index($0, k ":") == 1 {
      v = substr($0, length(k) + 2); sub(/^[ \t]+/, "", v)
      if (v ~ /^[>|][-+]?$/) { v = ""; grab = 1; next }
      exit
    }
    END { gsub(/^["\047]|["\047]$/, "", v); print v }
  ' "$2"
}

rank() {  # 보드에 있는 것을 먼저 — 정렬 키
  case "$1" in
    tasks) echo 1 ;;
    drafts) echo 2 ;;
    decisions) echo 3 ;;
    docs) echo 4 ;;
    milestones) echo 5 ;;
    *) echo 9 ;;
  esac
}

rows=$(printf '%s\n' "$hits" | while IFS= read -r f; do
  folder=${f#backlog/}
  folder=${folder%/*}
  base=${f##*/}
  num=$(printf '%s\n' "$base" | sed -nE 's/^[A-Za-z]+-([0-9]+).*/\1/p')
  id=$(fm id "$f")
  status=$(fm status "$f")
  title=$(fm title "$f")
  printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$(rank "$folder")" "${num:-0}" \
    "$folder" "${id:-${base%% *}}" "${status:--}" "${title:-${base%.md}}" "$f"
done | sort -t "$(printf '\t')" -k1,1n -k3,3 -k2,2nr)

total=$(printf '%s\n' "$rows" | grep -c .) || true
printf '%s\n' "$rows" | head -n "$max" | cut -f3-
if [ "$total" -gt "$max" ]; then
  echo "# 총 ${total}건 중 ${max}건 — 단어를 더해 좁히거나 --max 를 늘린다"
fi
