#!/bin/bash
# sync-repo.sh 의 체크아웃 동기화가 도달 불가 repo 에서 통째로 멈추지 않는지 본다(task-487).
#
# ## 왜 이 검사가 필요한가
#
# /sync 스킬 문서는 '도달 불가 리모트(사외망에서 사내 GHE 등)는 실패가 아니라 skip' 이라고
# 정하는데, sync_checkout 은 pull 실패를 그대로 터뜨려 `set -e` 로 스크립트가 거기서 끝났다.
# 2026-08-27 맥에서 GHEC 인증이 없는 ~/work/kil9/workflow 가 목록 마지막이 아니었다면 그 뒤
# 체크아웃이 통째로 안 돌았을 것이다. 증상은 '마지막 요약 줄이 없다' 뿐이라 조용하다.
#
# 반대 방향도 같이 지킨다: 닿았는데 못 합친 것(발산·충돌)은 여전히 알리고 exit 1 이어야 한다.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
script="$repo_root/claude/skills/sync/sync-repo.sh"
fixture=$(mktemp -d)
trap 'rm -rf "$fixture"' EXIT

export GIT_CONFIG_GLOBAL="$fixture/gitconfig"
export GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@e GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@e
git config --global init.defaultBranch main
git config --global user.name t
git config --global user.email t@e

make_repo() { # make_repo <이름> — bare 리모트 + 그것을 추적하는 체크아웃
  local name=$1
  git init -q --bare "$fixture/$name.git"
  git clone -q "$fixture/$name.git" "$fixture/$name"
  echo seed > "$fixture/$name/f"
  git -C "$fixture/$name" add f
  git -C "$fixture/$name" commit -qm seed
  git -C "$fixture/$name" push -q origin main
}

make_repo self        # /sync 를 돌리는 repo 자신
make_repo reachable   # 정상 체크아웃 — 도달 불가 뒤에도 처리돼야 한다
make_repo gone        # 리모트를 통째로 치워 도달 불가로 만든다
rm -rf "$fixture/gone.git"

run_sync() { # run_sync <체크아웃 목록...> — self 에서 돌린다
  local repos="$*"
  (cd "$fixture/self" && SYNC_SKILL_REPOS="$repos" \
    SYNC_EXTRA_REPOS_CONF="$fixture/no-such.conf" bash "$script" 2>&1)
}

# --- 1. 도달 불가 체크아웃은 skip 이고 그 뒤 체크아웃이 계속 처리된다 -----------------
out=$(run_sync "$fixture/gone" "$fixture/reachable") || {
  echo "FAIL: 도달 불가 체크아웃 때문에 /sync 가 실패로 끝났다"; echo "$out"; exit 1
}
case "$out" in
  *"skip: $fixture/gone"*) ;;
  *) echo "FAIL: 도달 불가 체크아웃을 skip 으로 알리지 않았다"; echo "$out"; exit 1 ;;
esac
case "$out" in
  *"--- $fixture/reachable"*) ;;
  *) echo "FAIL: skip 뒤의 체크아웃이 처리되지 않았다"; echo "$out"; exit 1 ;;
esac
case "$out" in
  *"sync 완료"*) ;;
  *) echo "FAIL: 마지막 요약 줄이 없다 — 중간에 끊겼다"; echo "$out"; exit 1 ;;
esac

# --- 2. 닿는데 못 합치는 것(발산·충돌)은 여전히 알리고 exit 1 이다 --------------------
# reachable 의 리모트와 로컬이 같은 파일을 서로 다르게 고쳐 rebase 충돌을 만든다.
side=$fixture/side
git clone -q "$fixture/reachable.git" "$side"
echo remote-쪽 > "$side/f"
git -C "$side" commit -qam remote-change
git -C "$side" push -q origin main
echo local-쪽 > "$fixture/reachable/f"
git -C "$fixture/reachable" commit -qam local-change

rc=0
out=$(run_sync "$fixture/gone" "$fixture/reachable") || rc=$?
[ "$rc" = 1 ] || { echo "FAIL: 발산·충돌인데 exit $rc 다"; echo "$out"; exit 1; }
case "$out" in
  *"체크아웃 동기화 실패"*"reachable"*) ;;
  *) echo "FAIL: 발산·충돌을 알리지 않았다"; echo "$out"; exit 1 ;;
esac
# 충돌로 멈춘 rebase 를 남기면 다음 /sync 가 다른 얼굴의 실패를 낸다.
if [ -d "$(git -C "$fixture/reachable" rev-parse --git-path rebase-merge)" ] ||
   [ -d "$(git -C "$fixture/reachable" rev-parse --git-path rebase-apply)" ]; then
  echo "FAIL: 진행 중인 rebase 가 남았다"; exit 1
fi

echo "ok: test-sync-checkout-skip"
