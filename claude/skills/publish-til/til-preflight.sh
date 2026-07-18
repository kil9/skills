#!/bin/bash
# /publish-til §0 프리플라이트: 경로·origin·브랜치·clean (+슬러그 형식·충돌) 일괄 검증.
# 사용법: til-preflight.sh [slug]
# 종료코드: 0=통과, 1=전제 불충족(중단), 3=슬러그 충돌(덮어쓰기 여부는 사용자 판단).
set -euo pipefail

repo="$HOME/work/kil9/til"
[ -d "$repo" ] || { echo "error: 저장소 경로 없음: $repo — 클론 위치를 사용자에게 물을 것" >&2; exit 1; }
cd "$repo"
git rev-parse --show-toplevel >/dev/null

url=$(git remote get-url origin)
case "$url" in
  *github.com[:/]kil9/til | *github.com[:/]kil9/til.git) ;;
  *github.com[:/]kil9/docs | *github.com[:/]kil9/docs.git)
    echo "notice: 구명 kil9/docs 리다이렉트 — origin 을 kil9/til 로 갱신"
    git remote set-url origin https://github.com/kil9/til.git
    ;;
  *)
    echo "error: origin 이 github.com 의 kil9/til 이 아님: $url — 경로만 믿지 말고 중단" >&2
    exit 1
    ;;
esac

branch=$(git rev-parse --abbrev-ref HEAD)
[ "$branch" = main ] || { echo "error: 브랜치가 main 이 아님: $branch" >&2; exit 1; }
if [ -n "$(git status --porcelain)" ]; then
  git status --short
  echo "error: working tree dirty — 다른 변경이 섞일 위험" >&2
  exit 1
fi

slug=${1:-}
if [ -n "$slug" ]; then
  [[ "$slug" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || {
    echo "error: 슬러그 형식 불일치(kebab-case 아님): $slug — 인터뷰로 재수집" >&2
    exit 1
  }
  # 날짜 아티클은 <현재연도>/<slug>/ 에 놓인다(TASK-40 재편, t/ 래퍼 제거). 충돌은 그 경로로 검사.
  reldir="$(date +%Y)/$slug"
  if [ -e "$reldir" ] || [ -e "$slug" ] || [ -e "p/$slug" ]; then
    echo "conflict: $slug 경로가 이미 존재(<연도>/·p/·루트 중) — 덮어쓰기 여부는 사용자에게 물을 것" >&2
    exit 3
  fi
fi

echo "preflight ok: $repo (origin=$(git remote get-url origin), main, clean${slug:+, slug=$slug → $(date +%Y)/$slug/})"
