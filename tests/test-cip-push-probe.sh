#!/bin/bash
# cip-push.sh 의 SSH 리모트 도달성 체크가 nc 없이도 동작하는지 본다(kil9conf task-544).
#
# Windows Git Bash 에는 nc 가 없어 SSH 리모트가 전부 '도달 불가' 로 빠졌다 — /cip 가 push 를
# 한 번도 못 하는데 증상은 'skip' 한 줄뿐이다. 맥 nc 는 응답 없는 주소에서 75초를 기다렸다.
# nc 가 있을 때와 없을 때 둘 다,
#   - 열린 포트는 닿고
#   - 닫힌 포트·라우팅 안 되는 주소는 수 초 안에 도달 불가로 끝나는지 본다.
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
script="$repo_root/claude/skills/cip/cip-push.sh"
fixture=$(mktemp -d)
listener_pid=""
cleanup() {
  [ -n "$listener_pid" ] && kill "$listener_pid" 2>/dev/null || true
  rm -rf "$fixture"
}
trap cleanup EXIT

# 열린 포트: python 으로 127.0.0.1 임의 포트에 listen 하고 그 번호를 파일로 받는다.
python3 -c '
import socket, sys, time
s = socket.socket(); s.bind(("127.0.0.1", 0)); s.listen(8)
open(sys.argv[1], "w").write(str(s.getsockname()[1]))
while True:
    c, _ = s.accept(); c.close()
' "$fixture/port" &
listener_pid=$!
disown "$listener_pid"
for _ in $(seq 1 50); do [ -s "$fixture/port" ] && break; sleep 0.1; done
open_port=$(cat "$fixture/port")
# 닫힌 포트: 잠깐 열었다 닫은 번호.
closed_port=$(python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])')

# nc 없는 PATH: 스크립트가 쓰는 도구만 링크한다. 이 머신에 nc 가 원래 없으면(Windows Git Bash)
# PATH 를 그대로 쓴다 — Git Bash 의 ln -s 는 복사라 옮긴 bash.exe 가 msys DLL 을 못 찾아 127 로 죽는다.
if command -v nc >/dev/null 2>&1; then
  nonc="$fixture/bin"
  mkdir -p "$nonc"
  for t in bash git seq sleep cat sed; do
    ln -s "$(command -v "$t")" "$nonc/$t"
  done
else
  nonc=$PATH
fi

fail=0
check() { # check <설명> <기대 rc> <PATH> <url>
  local desc=$1 want=$2 path=$3 url=$4 rc start elapsed
  start=$(date +%s)
  rc=0
  PATH="$path" CIP_PUSH_SOURCE_ONLY=1 bash -c 'source "$1"; remote_reachable "$2"' _ "$script" "$url" || rc=$?
  elapsed=$(( $(date +%s) - start ))
  if [ "$rc" != "$want" ] || [ "$elapsed" -gt 8 ]; then
    echo "FAIL: $desc — rc=$rc(기대 $want), ${elapsed}s"
    fail=1
  else
    echo "ok: $desc (${elapsed}s)"
  fi
}

for mode in path no-nc; do
  # path: 이 머신 PATH 그대로(맥·리눅스는 nc 가 있다) / no-nc: Windows Git Bash 처럼 nc 가 없다.
  if [ "$mode" = path ]; then p=$PATH; else p=$nonc; fi
  check "$mode: 열린 포트(ssh://)" 0 "$p" "ssh://git@127.0.0.1:$open_port/x.git"
  check "$mode: 닫힌 포트(ssh://)" 1 "$p" "ssh://git@127.0.0.1:$closed_port/x.git"
  # 10.255.255.1 은 라우팅되지 않아 SYN 이 응답 없이 사라진다 — 4초 감시가 끊어야 한다.
  # 맥 nc 로 재던 시절엔 여기서 75초가 걸렸다.
  check "$mode: 응답 없는 주소(scp 형식)" 1 "$p" "git@10.255.255.1:o/r.git"
done

[ "$fail" = 0 ] && echo "test-cip-push-probe: 통과"
exit "$fail"
