#!/bin/bash
set -euo pipefail

# 현재 repo 와 같은 repo 의 체크아웃을 다른 머신들에서 찾아 pull 한다(/all-sync). 로컬 /sync 는 SKILL.md 가 먼저 한다.
# 사용: all-sync.sh [머신 ...]
# 머신 목록 우선순위: 인자 > $ALL_SYNC_HOSTS(공백 구분) > ~/.claude/all-sync-hosts.conf(한 줄에 하나, # 주석)
#   > `hc machine ls` 의 등록 머신(Herdr). 각 항목은 'name' 또는 'name=ssh대상'.
# 원격은 stash·rebase 없이 `git pull --ff-only` 만 한다 — 그 머신에서 도는 세션의 dirty 변경을 건드리지 않고,
# 갈라졌으면 손대지 않고 보고한다. 체크아웃 경로는 머신마다 달라서(D:\work\x · ~/x · ~/work/x) 리모트 URL 로 찾는다.
# kil9conf 처럼 루트에 bootstrap/apply-kil9conf.sh 가 있는 repo 는 pull 이 ok·pulled 로 끝난 머신에서 재적용까지
# 돌린다 — pull 만으로는 dotfile·mod·키가 그 머신에 얹히지 않는다. Windows(Git Bash)는 Apply-Kil9conf.ps1 -NoSync.
# 재적용이 실패하면 상태를 apply-fail 로 바꾼다. ALL_SYNC_NO_APPLY=1 이면 재적용을 건너뛴다.
# 출력: 머신마다 한 줄 'name<TAB>상태<TAB>경로<TAB>설명'.
# 상태: ok | pulled | skip(그 머신이 upstream 에 못 닿음) | apply-fail | behind | diverged | dirty-conflict | notfound | unreachable | error.
# 종료 코드: 모두 ok·pulled·skip 이면 0, 아니면 1.

top=$(git rev-parse --show-toplevel 2>/dev/null) || { echo "git 저장소 안에서 실행하세요" >&2; exit 2; }
PY=$(command -v python3 || command -v python || true)

# Git Bash 의 HOME 이 %USERPROFILE% 가 아닌 Windows 머신(k9pc4080s 는 D:\work)에서는 ssh 가 엉뚱한 ~/.ssh 를 읽어
# 계정(User kil9)·HostName·known_hosts 를 못 찾는다. Herdr 앱·Windows OpenSSH 가 쓰는 %USERPROFILE%\.ssh 를 쓰게 한다.
# msys ssh 는 $HOME 을 바꿔도 따르지 않아 -F·UserKnownHostsFile 로 직접 준다(2026-11-07 실측).
SSH_OPTS=()
if [ -n "${USERPROFILE:-}" ] && command -v cygpath >/dev/null 2>&1; then
  up=$(cygpath -u "$USERPROFILE")
  [ "$up" != "$HOME" ] && [ -f "$up/.ssh/config" ] && SSH_OPTS=(-F "$up/.ssh/config" -o "UserKnownHostsFile=$up/.ssh/known_hosts")
fi
ssh() { command ssh ${SSH_OPTS[@]+"${SSH_OPTS[@]}"} "$@"; }

# URL 을 'host/owner/repo' 로 맞춘다: git@h:o/r.git · https://u@h/o/r · ssh://git@h/o/r 모두 같은 값이 된다.
norm() { sed -E 's#^[a-z+]+://##; s#^[^@/]+@##; s#:([^0-9/])#/\1#; s#\.git/?$##; s#/$##' <<<"$1" | tr 'A-Z' 'a-z'; }

keys=()
while read -r u; do [ -n "$u" ] && keys+=("$(norm "$u")"); done < <(git -C "$top" remote -v | awk '{print $2}' | sort -u)
[ ${#keys[@]} -gt 0 ] || { echo "리모트가 없는 repo 입니다" >&2; exit 2; }
name=$(basename "${keys[0]}")
sha=$(git -C "$top" rev-parse HEAD)

hosts=()
if [ $# -gt 0 ]; then hosts=("$@")
elif [ -n "${ALL_SYNC_HOSTS:-}" ]; then read -r -a hosts <<<"$ALL_SYNC_HOSTS"
elif [ -f "$HOME/.claude/all-sync-hosts.conf" ]; then
  while read -r l; do l=${l%%#*}; l=$(echo $l); [ -n "$l" ] && hosts+=("$l"); done < "$HOME/.claude/all-sync-hosts.conf"
elif command -v hc >/dev/null 2>&1 && [ -n "$PY" ]; then
  # Windows python 은 CRLF 로 낸다 — CR 이 남으면 ssh 가 'hostname contains invalid characters' 로 죽는다.
  while read -r l; do l=${l//[[:cntrl:]]/}; [ -n "$l" ] && hosts+=("$l"); done < <(hc machine ls 2>/dev/null | PYTHONUTF8=1 "$PY" -c '
import json, sys
for m in json.load(sys.stdin).get("machines", []):
    print("%s=%s" % (m["name"], m.get("target") or m["name"]))' 2>/dev/null || true)
fi
[ ${#hosts[@]} -gt 0 ] || { echo "대상 머신이 없습니다 — 인자·ALL_SYNC_HOSTS·~/.claude/all-sync-hosts.conf 중 하나로 지정하세요" >&2; exit 2; }

# 원격에서 도는 부분. 인자: repo 이름, 로컬 HEAD, 재적용 여부(1/0), 정규화한 리모트 URL 들.
remote_script='
name=$1 sha=$2 apply=$3; shift 3
norm() { sed -E "s#^[a-z+]+://##; s#^[^@/]+@##; s#:([^0-9/])#/\1#; s#\.git/?\$##; s#/\$##" <<<"$1" | tr "A-Z" "a-z"; }
found=
for d in "$HOME/$name" "$HOME/work/$name" "$HOME"/work/*/"$name" "$HOME"/*/"$name"; do
  [ -d "$d/.git" ] || [ -f "$d/.git" ] || continue
  for u in $(git -C "$d" remote -v 2>/dev/null | awk "{print \$2}" | sort -u); do
    k=$(norm "$u"); for want in "$@"; do [ "$k" = "$want" ] && { found=$d; break 3; }; done
  done
done
[ -n "$found" ] || { printf "notfound\t-\t%s 체크아웃을 찾지 못함(~/%s · ~/work/[*/]%s)\n" "$name" "$name" "$name"; exit 0; }
cd "$found"
dirty=$(git status --porcelain | wc -l | tr -d " ")
before=$(git rev-parse --short HEAD)
if out=$(git pull --ff-only -q 2>&1); then
  after=$(git rev-parse --short HEAD)
  note=""; [ "$dirty" != 0 ] && note=" (커밋 안 된 변경 ${dirty}개는 그대로 둠)"
  if git merge-base --is-ancestor "$sha" HEAD 2>/dev/null; then st=ok; [ "$before" != "$after" ] && st=pulled
  else st=behind; note="$note — 로컬 HEAD ${sha:0:8} 가 아직 이 머신 upstream 에 없음(그 리모트로 push 됐는지 확인)"; fi
  if [ "$apply" = 1 ] && [ "$st" != behind ] && [ -f bootstrap/apply-kil9conf.sh ]; then
    case $(uname -s) in
      MINGW*|MSYS*|CYGWIN*) aout=$(pwsh -NoProfile -File bootstrap/Apply-Kil9conf.ps1 -NoSync 2>&1); arc=$? ;;
      *) aout=$(bash -lc "bash bootstrap/apply-kil9conf.sh" 2>&1); arc=$? ;;
    esac
    asum=$(grep -a "apply-kil9conf:" <<<"$aout" | tail -1)
    if [ "$arc" = 0 ]; then note="$note · apply: ${asum:-OK}"
    else st=apply-fail; note="$note · apply rc=$arc: $(grep -a -E "FAIL|apply-kil9conf:|logs:" <<<"$aout" | tail -4 | tr "\n" " " | cut -c1-300)"; fi
  fi
  printf "%s\t%s\t%s -> %s%s\n" "$st" "$found" "$before" "$after" "$note"
else
  st=error
  grep -qi "not possible to fast-forward\|diverg" <<<"$out" && st=diverged
  grep -qi "would be overwritten" <<<"$out" && st=dirty-conflict
  # 그 머신에서 upstream 에 닿지 않음(인증 없음·망 밖) — /sync 의 도달 불가 리모트처럼 실패가 아니라 skip 이다.
  grep -qi "could not read Username\|Could not resolve host\|timed out\|Permission denied (publickey\|Authentication failed" <<<"$out" && st=skip
  printf "%s\t%s\t%s\n" "$st" "$found" "$(tr "\n" " " <<<"$out" | cut -c1-200)"
fi
'

apply=1; [ "${ALL_SYNC_NO_APPLY:-}" = 1 ] && apply=0
tmp=$(mktemp -d "${TMPDIR:-/tmp}/all-sync.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
i=0
for h in "${hosts[@]}"; do
  label=${h%%=*}; target=${h#*=}
  (
    # fail-fast: ProxyJump 경유 호스트가 ControlMaster 로 붙는 곳(FastID 같은 대화형 인증 게이트웨이)이면 master 가
    # 살아 있을 때만 접속한다. master 가 없으면 점프 ssh 가 새로 로그인하며 승인을 기다리다(푸시까지 보낸 채) 수십 초
    # 뒤 거부된다 — BatchMode 는 점프 ssh 에 안 넘어간다. 그 대기 없이 바로 unreachable 로 낸다.
    jump=$(ssh -G "$target" 2>/dev/null | awk '$1=="proxyjump"{print $2; exit}')
    jump=${jump%%,*}
    if [ -n "$jump" ] && [ "$jump" != none ] \
       && cp=$(ssh -G "$jump" 2>/dev/null | awk '$1=="controlpath"{print $2; exit}') && [ -n "$cp" ] && [ "$cp" != none ] \
       && ! ssh -O check "$jump" 2>/dev/null; then
      printf "%s\tunreachable\t-\t경유 호스트 %s 의 master 연결이 없다 — 그쪽에 먼저 로그인한 뒤 다시\n" "$label" "$jump"
      exit 0
    fi
    if r=$(ssh -o BatchMode=yes -o ConnectTimeout=10 "$target" bash -s -- "$name" "$sha" "$apply" "${keys[@]}" <<<"$remote_script" 2>"$tmp/$i.err"); then
      printf "%s\t%s\n" "$label" "${r:-error	-	빈 응답}"
    else
      printf "%s\tunreachable\t-\t%s\n" "$label" "$(tr '\n' ' ' < "$tmp/$i.err" | cut -c1-200)"
    fi
  ) > "$tmp/$i.out" &
  i=$((i + 1))
done
wait

rc=0
for j in $(seq 0 $((i - 1))); do
  line=$(cat "$tmp/$j.out")
  echo "$line"
  case $(cut -f2 <<<"$line") in ok|pulled|skip) ;; *) rc=1 ;; esac
done
exit $rc
