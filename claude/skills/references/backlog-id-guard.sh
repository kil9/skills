#!/bin/bash
# backlog ID 가드 — 이미 쓰인 번호가 다시 발급되는 것을 막는다. 태스크와 마일스톤 둘 다 본다.
#
# backlog CLI(1.48.0 실측)의 ID 할당기는 backlog/tasks/ + backlog/completed/ 만 본다.
# 그래서 두 구멍이 남는다:
#   1. backlog/archive/tasks/ 는 안 본다 — 거기 최대 번호가 있으면 그대로 재발급된다.
#   2. 다른 머신이 만들었지만 이 체크아웃에 아직 안 온 태스크를 알 길이 없다.
#      실제 충돌 3건(task-153/167/203)이 전부 이 경우였다. 그쪽이 push 만 했으면
#      리모트 트리에는 그 번호가 있으므로, 여기서 그것까지 훑어 피한다.
# 마일스톤 할당기도 같은 구멍을 갖는다(2026-07-26 실사고, task-222: 두 세션이 m-22 를 각각
# 발급해 milestones/ 에 m-22 가 두 벌 생겼고 그 아래 task-211~214 까지 통째로 충돌했다).
#
# 사용법:
#   backlog-id-guard.sh next [task|milestone]   # 다음에 쓸 ID 를 출력 (기본 task)
#   backlog-id-guard.sh fix TASK-N              # 방금 만든 태스크가 이미 쓰인 번호면 개명
#   backlog-id-guard.sh fix m-N                 # 마일스톤도 같다 (엔티티는 접두사로 판별)
#
# fix 출력은 ID 판정과 게시 상태 각 한 줄이다:
#   next=TASK-206 | next=m-24
#   ok=TASK-206                       # 개명 불필요
#   moved=TASK-203 -> TASK-206        # 개명함
#   published=TASK-206 ref=github/main
#   warning=unpublished id=TASK-206 reason=uncommitted path=...
#   skip=no-backlog | skip=no-cli     # 대상 저장소가 아님 (exit 0)
#
# fix 는 **방금 만든 것**에만 쓴다. 다른 파일·커밋이 이미 그 ID 를 참조하는 오래된 태스크·
# 마일스톤을 개명하면 그 참조가 끊긴다(그 판단은 사람 몫이다). 마일스톤은 태스크
# frontmatter 의 `milestone: m-N` 이 곧 그 참조라, 그런 태스크가 하나라도 있으면 개명하지 않고
# error=refs 로 멈춘다 — 그 경우는 `backlog milestone rename` 이 맞는 도구다.
#
# 리모트 조회는 GitHub 리모트 하나만 `git fetch` 한다(타임아웃 3초, 실패는 무시).
# VPN 전용 리모트는 건드리지 않아 사외망에서도 시작을 붙잡지 않는다.
# 끄려면 BACKLOG_ID_GUARD_NO_FETCH=1.
#
# **BSD(macOS) 도구만 있는 환경을 가정한다.** 2026-07-26 에 여기서 두 구멍이 드러났다:
# `grep -oP`(PCRE)와 `timeout`(GNU coreutils) 둘 다 macOS 기본 설치에 없다. 그런데 둘 다
# `|| true` 로 감싸여 있어 **에러가 나도 exit 0 에 next= 는 정상 출력됐다** — 즉 가드가
# 막으려던 두 구멍(archive·미동기 리모트)이 조용히 다시 열린 상태로 몇 달을 돌았다.
# 그래서 아래는 GNU 전용 도구를 쓰지 않는다(`sed -i` 도 BSD 는 접미사 인자를 요구하므로 안 쓴다).
# bash 3.2(macOS 기본)에서도 돌아야 한다. 새 코드도 그 규칙을 지킬 것.
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=backlog-git-guard-lib.sh
. "$script_dir/backlog-git-guard-lib.sh"

usage() {
  echo "usage: $(basename "$0") next [task|milestone] | fix TASK-N | fix m-N" >&2
  exit 2
}

[[ $# -ge 1 ]] || usage
mode=$1

# backlog 저장소 찾기 (cwd 에서 위로)
root=$PWD
while [[ $root != / ]]; do
  [[ -d $root/backlog/tasks ]] && break
  root=$(dirname "$root")
done
if [[ $root == / ]]; then
  echo "skip=no-backlog"
  exit 0
fi
if ! command -v backlog >/dev/null 2>&1; then
  echo "skip=no-cli"
  exit 0
fi

# 엔티티별 차이는 전부 여기 모은다 — 아래 스캔 로직은 태스크·마일스톤에 공통이다.
#   ENT_DIRS[0] 은 '활성' 디렉터리다(fix 가 대상 파일을 여기서만 찾는다).
ent_select() {  # $1=task|milestone
  case $1 in
    task)
      ENT=task
      ENT_NUM_RE='^task-([0-9]+)'
      ENT_GLOB='task-*.md'
      ENT_DIRS=("$root/backlog/tasks" "$root/backlog/completed" "$root/backlog/archive")
      ENT_TREE_PATHS=(backlog)
      ENT_ID_RE='^id: [Tt][Aa][Ss][Kk]-[0-9]+$'
      ;;
    milestone)
      ENT=milestone
      ENT_NUM_RE='^m-([0-9]+)'
      ENT_GLOB='m-*.md'
      ENT_DIRS=("$root/backlog/milestones" "$root/backlog/archive/milestones")
      ENT_TREE_PATHS=(backlog/milestones backlog/archive/milestones)
      ENT_ID_RE='^id: [Mm]-[0-9]+$'
      ;;
    *) usage ;;
  esac
}

ent_id() {  # $1=번호 → 표기용 ID
  if [[ $ENT == task ]]; then echo "TASK-$1"; else echo "m-$1"; fi
}

# 방금 만든 엔티티가 다른 머신의 ID 가드에서도 보이는지 보고한다. 새 파일이 커밋되지 않았거나
# GitHub 리모트 트리에서 같은 blob 을 확인할 수 없으면 경고한다. fix 자체는 기존처럼 성공한다.
report_publication() {  # $1=표시 ID, $2=현재 파일 절대 경로
  local id=$1 file=$2 rel status remote current_blob ref remote_blob ref_count=0
  if ! git -C "$root" rev-parse --git-dir >/dev/null 2>&1; then
    echo "warning=unpublished id=$id reason=no-git path=$file"
    return
  fi
  case $file in
    "$root"/*) rel=${file#"$root"/} ;;
    *)
      echo "warning=unpublished id=$id reason=outside-repo path=$file"
      return
      ;;
  esac

  status=$(git -C "$root" status --porcelain -- "$rel") || status=""
  if [[ -n $status ]]; then
    echo "warning=unpublished id=$id reason=uncommitted path=$rel"
    return
  fi

  current_blob=$(git -C "$root" rev-parse --verify "HEAD:$rel" 2>/dev/null) || current_blob=""
  if [[ -z $current_blob ]]; then
    echo "warning=unpublished id=$id reason=not-in-head path=$rel"
    return
  fi

  remote=$(backlog_guard_github_remote "$root") || remote=""
  if [[ -z $remote ]]; then
    echo "warning=unpublished id=$id reason=no-github-remote path=$rel"
    return
  fi
  while IFS= read -r ref; do
    ref_count=$((ref_count + 1))
    remote_blob=$(git -C "$root" rev-parse --verify "$ref:$rel" 2>/dev/null) || remote_blob=""
    if [[ -n $remote_blob && $remote_blob == "$current_blob" ]]; then
      echo "published=$id ref=$ref"
      return
    fi
  done < <(git -C "$root" for-each-ref --format='%(refname:short)' \
    "refs/remotes/$remote" 2>/dev/null)

  if [[ $ref_count -eq 0 ]]; then
    echo "warning=unpublished id=$id reason=no-remote-ref path=$rel"
  else
    echo "warning=unpublished id=$id reason=not-on-github path=$rel"
  fi
}

# 로컬: 활성 + completed + archive 를 통틀어 쓰인 번호. exclude 로 준 경로 하나는 뺀다.
local_max() {
  local exclude=${1:-} f base max=0
  while IFS= read -r -d '' f; do
    [[ -n $exclude && $f == "$exclude" ]] && continue
    base=$(basename "$f")
    [[ $base =~ $ENT_NUM_RE ]] || continue
    ((10#${BASH_REMATCH[1]} > max)) && max=$((10#${BASH_REMATCH[1]}))
  done < <(find "${ENT_DIRS[@]}" -type f -name "$ENT_GLOB" -print0 2>/dev/null)
  echo "$max"
}

# 리모트: 아직 안 당겨온 것이 다른 머신에서 push 됐을 수 있다.
remote_max() {
  git -C "$root" rev-parse --git-dir >/dev/null 2>&1 || { echo 0; return; }
  backlog_guard_fetch_github "$root" "${BACKLOG_ID_GUARD_NO_FETCH:-0}"
  local refs=() r max=0
  [[ -n $BACKLOG_GUARD_REMOTE ]] || { echo 0; return; }
  while IFS= read -r r; do refs+=("$r"); done < <(
    git -C "$root" for-each-ref --format='%(refname:short)' \
      "refs/remotes/$BACKLOG_GUARD_REMOTE" 2>/dev/null)
  # 번호 추출은 grep -oP 가 아니라 bash 정규식으로 한다(local_max 와 같은 방식). ls-tree -r 은
  # blob 만 내놓으므로 마지막 경로 성분이 곧 파일명이다.
  local p base
  for r in "${refs[@]}"; do
    while IFS= read -r p; do
      base=${p##*/}
      [[ $base =~ $ENT_NUM_RE ]] || continue
      ((10#${BASH_REMATCH[1]} > max)) && max=$((10#${BASH_REMATCH[1]}))
    done < <(git -C "$root" ls-tree -r --name-only "$r" -- "${ENT_TREE_PATHS[@]}" 2>/dev/null || true)
  done
  echo "$max"
}

used_max() {
  local l r
  l=$(local_max "${1:-}")
  r=$(remote_max)
  ((r > l)) && l=$r
  echo "$l"
}

case $mode in
  next)
    ent_select "${2:-task}"
    echo "next=$(ent_id $(( $(used_max) + 1 )))"
    ;;
  fix)
    [[ $# -eq 2 ]] || usage
    case $2 in
      [Tt][Aa][Ss][Kk]-*) ent_select task ;;
      [Mm]-*)             ent_select milestone ;;
      *)                  usage ;;
    esac
    [[ $2 =~ ([0-9]+) ]] || usage
    num=$((10#${BASH_REMATCH[1]}))

    file=""
    while IFS= read -r -d '' f; do
      base=$(basename "$f")
      [[ $base =~ ${ENT_NUM_RE}[[:space:]] ]] || continue
      if ((10#${BASH_REMATCH[1]} == num)); then file=$f; break; fi
    done < <(find "${ENT_DIRS[0]}" -maxdepth 1 -type f -name "$ENT_GLOB" -print0)

    if [[ -z $file ]]; then
      echo "error=not-found $(ent_id "$num")" >&2
      exit 1
    fi

    other_max=$(used_max "$file")
    if ((num > other_max)); then
      echo "ok=$(ent_id "$num")"
      report_publication "$(ent_id "$num")" "$file"
      exit 0
    fi

    # 마일스톤을 참조하는 태스크가 이미 있으면 개명이 그 참조를 끊는다. 갓 만든 것에만 쓰라는
    # 계약이 깨진 경우이므로 손대지 않고 멈춘다 — 그 상황은 milestone rename 이 맞는 도구다.
    if [[ $ENT == milestone ]]; then
      # 매치가 없으면 grep 이 1 로 끝난다 — pipefail 이 켜져 있어 || true 가 없으면 여기서
      # 스크립트가 조용히 죽는다(참조 0 건, 즉 정상 경로가 통째로 사라진다).
      ref_count=$( { grep -rlE "^milestone: [Mm]-$num$" "$root/backlog/tasks" 2>/dev/null || true; } | wc -l | tr -d ' ')
      if [[ $ref_count != 0 ]]; then
        echo "error=refs $(ent_id "$num") ($ref_count tasks) — use: backlog milestone rename" >&2
        exit 1
      fi
    fi

    new=$((other_max + 1))
    newfile=$(dirname "$file")/$(basename "$file" | sed -E "s/^(task-|m-)[0-9]+/\\1$new/")
    # frontmatter 의 id 만 바꾼다(그 줄만 통째로 `id: <ID>` 다. SECTION 마커·본문은 안 걸린다).
    # 옛 코드는 `0,/re/s//…/` 와 `sed -i` 를 썼는데 둘 다 GNU 전용이라 macOS 에서 죽는다
    # (0 시작 주소 미지원 + -i 가 접미사 인자를 요구). 임시 파일 + 단순 치환으로 쓴다.
    tmp=$file.idguard.$$
    sed -E "s/$ENT_ID_RE/id: $(ent_id "$new")/" "$file" >"$tmp" \
      || { rm -f "$tmp"; echo "error=sed-failed" >&2; exit 1; }
    mv "$tmp" "$file"
    if git -C "$root" ls-files --error-unmatch "$file" >/dev/null 2>&1; then
      git -C "$root" mv "$file" "$newfile"
    else
      mv "$file" "$newfile"
    fi
    echo "moved=$(ent_id "$num") -> $(ent_id "$new")"
    report_publication "$(ent_id "$new")" "$newfile"
    ;;
  *)
    usage
    ;;
esac
