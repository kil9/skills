#!/bin/bash
# 스킬 문서가 가리키는 경로가 실제로 있는지 본다. 공용 절차를 references/ 로 끌어올린 뒤
# 파일을 옮기거나 지우면 포인터만 남아 에이전트가 조용히 절차를 지어낸다 — 그걸 커밋 전에 잡는다.
#
# 검사하는 것은 세 꼴뿐이다:
#   ~/.claude/skills/<경로>   설치 위치(SKILLS_HOME) 기준 — repo 를 가로지르는 참조도 여기서 풀린다
#   references/<파일>         그 문서의 스킬 디렉터리 → 문서 옆 → 공용 claude/skills/references/ 순으로 찾는다
#   ../references/<파일>      문서 위치 기준 상대경로
#
# 사용: check-skill-refs.sh [스킬 루트...]   (기본: 이 repo 의 claude/skills)
set -uo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
skills_home=${SKILLS_HOME:-$HOME/.claude/skills}
shared_refs=$repo_root/claude/skills/references
roots=("$@")
[ ${#roots[@]} -eq 0 ] && roots=("$repo_root/claude/skills")

broken=0
while IFS= read -r md; do
  root=""
  for r in "${roots[@]}"; do
    case $md in "$r"/*) root=$r ;; esac
  done
  rel=${md#"$root"/}
  skill_dir=$root/${rel%%/*}

  while IFS=: read -r lineno ref; do
    case $ref in
      \~/.claude/skills/*|'$HOME/.claude/skills/'*)
        target=$skills_home/${ref#*/.claude/skills/}
        [ -e "$target" ] && continue
        # 설치되지 않은 머신(사외 장비의 사내 스킬 등)에서는 판정하지 않는다
        name=${ref#*/.claude/skills/}; name=${name%%/*}
        [ -e "$skills_home/$name" ] || continue
        ;;
      ../*)
        [ -e "$(dirname "$md")/$ref" ] && continue
        ;;
      references/*)
        [ -e "$skill_dir/$ref" ] && continue
        [ -e "$(dirname "$md")/$ref" ] && continue
        [ -e "$shared_refs/${ref#references/}" ] && continue
        ;;
    esac
    echo "${md#"$repo_root"/}:$lineno: 없는 경로 $ref"
    broken=$((broken + 1))
  done < <(grep -noE '(~|\$HOME)/\.claude/skills/[A-Za-z0-9._/-]*[A-Za-z0-9_-]|(^|[^A-Za-z0-9_./~-])(\.\./)*references/[A-Za-z0-9._-]+\.(md|sh|py)' "$md" \
             | sed -E 's/^([0-9]+):[^~$.r]*/\1:/')
done < <(find "${roots[@]}" -name '*.md' -type f | sort)

if [ "$broken" -gt 0 ]; then
  echo "깨진 경로 참조 $broken 건" >&2
  exit 1
fi
