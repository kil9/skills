#!/usr/bin/env bash
# /web-show 실행 래퍼. macOS bash 3.2 에서도 돈다.
#
#   start [host=<name>] FILE...   문서 서버를 background 로 띄우고 등록한다
#                                 → PID:<pid> / PORT:<port> / URL:<url> (파일마다) / HINT:<안내>
#   add PORT [host=<name>] FILE...  떠 있는 서버에 파일을 더 등록한다 → URL:<url>
#   stop PORT                     서버를 끄고 포트를 비운다
#   host [host=<name>]            URL 에 쓸 호스트 → HOST:<host> (+ 못 구했으면 HINT:)
#   port                          18080 부터 빈 포트 하나 → PORT:<port>
#
# 호스트 결정(앞이 이긴다): host= 인자 → $WEB_SHOW_HOST → host.local 의 HOST →
#   host.cache → $(hostname).$WEB_SHOW_HOST_DOMAIN(DNS 로 풀릴 때) → tailscale Self.DNSName.
#   자동으로 찾은 FQDN 만 host.cache 에 남긴다(실패는 캐시하지 않아 다음에 다시 찾는다).
#   전부 실패하면 localhost 가 아니라 tailscale IP → LAN IP 를 쓰고 HINT 를 붙인다.
set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/web-show"
mkdir -p "$STATE_DIR"
HINT=""

tailscale_bin() {
  if command -v tailscale >/dev/null 2>&1; then echo tailscale
  elif [ -x /Applications/Tailscale.app/Contents/MacOS/Tailscale ]; then
    echo /Applications/Tailscale.app/Contents/MacOS/Tailscale
  fi
}

resolve_host() {  # $1 = host= 인자 값(없으면 빈 문자열)
  if [ -n "$1" ]; then printf '%s' "$1"; return; fi
  if [ -n "${WEB_SHOW_HOST:-}" ]; then printf '%s' "$WEB_SHOW_HOST"; return; fi
  local HOST=""
  if [ -f "$SKILL_DIR/host.local" ]; then
    # shellcheck disable=SC1091
    . "$SKILL_DIR/host.local"
    if [ -n "$HOST" ]; then printf '%s' "$HOST"; return; fi
  fi
  if [ -f "$SKILL_DIR/host.cache" ]; then
    # shellcheck disable=SC1091
    . "$SKILL_DIR/host.cache"
    if [ -n "$HOST" ]; then printf '%s' "$HOST"; return; fi
  fi
  local cand="" ts
  if [ -n "${WEB_SHOW_HOST_DOMAIN:-}" ]; then
    cand="$(hostname -s 2>/dev/null || hostname).${WEB_SHOW_HOST_DOMAIN}"
    if ! python3 -c 'import socket,sys; socket.setdefaulttimeout(2); socket.gethostbyname(sys.argv[1])' "$cand" 2>/dev/null; then
      cand=""
    fi
  fi
  ts="$(tailscale_bin)"
  if [ -z "$cand" ] && [ -n "$ts" ]; then
    cand="$("$ts" status --json 2>/dev/null | python3 -c 'import json,sys
try: print(json.load(sys.stdin)["Self"]["DNSName"].rstrip("."))
except Exception: pass' || true)"
  fi
  if [ -n "$cand" ]; then
    printf 'HOST=%s\n' "$cand" > "$SKILL_DIR/host.cache"
    printf '%s' "$cand"; return
  fi
  # FQDN 실패: IP 로 대신한다
  local ip=""
  [ -n "$ts" ] && ip="$("$ts" ip -4 2>/dev/null | head -1 || true)"
  if [ -z "$ip" ]; then
    ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
    [ -z "$ip" ] && ip="$(ipconfig getifaddr en0 2>/dev/null || true)"
  fi
  [ -z "$ip" ] && ip="127.0.0.1"
  printf '%s' "$ip"
}

set_hint() {  # resolve_host 는 서브셸에서 돌므로 결과가 IP 인지로 판정한다
  case "$1" in
    *[!0-9.]*) ;;
    *) HINT="FQDN 을 못 찾아 IP 로 띄웠다 — 고정하려면 $SKILL_DIR/host.local 에 HOST=<FQDN> 을 적는다" ;;
  esac
}

free_port() {
  python3 - <<'PY'
import socket
for p in range(18080, 18180):
    s = socket.socket()
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)  # 서버와 같은 조건: TIME_WAIT 은 빈 포트다
    try:
        s.bind(("0.0.0.0", p)); print(p); break
    except OSError:
        pass
    finally:
        s.close()
else:
    raise SystemExit("빈 포트 없음(18080-18179)")
PY
}

split_args() {  # host= 를 HOST_ARG 로, 나머지를 FILES 배열로
  HOST_ARG=""; FILES=()
  local a
  for a in "$@"; do
    case "$a" in
      host=*) HOST_ARG="${a#host=}" ;;
      *) FILES+=("$(cd "$(dirname "$a")" && pwd)/$(basename "$a")") ;;
    esac
  done
}

print_urls() {  # $1 port, $2 host, 나머지 slug
  local port="$1" host="$2"; shift 2
  local s
  for s in "$@"; do echo "URL:http://${host}:${port}/${s}/"; done
  if [ -n "$HINT" ]; then echo "HINT:$HINT"; fi
}

cmd="${1:-}"; shift || true
case "$cmd" in
  host)
    split_args "$@"
    h="$(resolve_host "$HOST_ARG")"
    set_hint "$h"
    echo "HOST:$h"; [ -n "$HINT" ] && echo "HINT:$HINT"; exit 0 ;;
  port)
    echo "PORT:$(free_port)"; exit 0 ;;
  start)
    split_args "$@"
    [ "${#FILES[@]}" -gt 0 ] || { echo "ERROR:띄울 파일이 없다" >&2; exit 1; }
    port="$(free_port)"
    log="$STATE_DIR/$port.log"
    nohup python3 "$SKILL_DIR/server.py" --port "$port" "${FILES[@]}" >"$log" 2>&1 </dev/null &
    pid=$!
    echo "$pid" > "$STATE_DIR/$port.pid"
    for _ in $(seq 50); do grep -q '^READY' "$log" 2>/dev/null && break; sleep 0.1; done
    if ! grep -q '^READY' "$log"; then
      echo "ERROR:서버가 5초 안에 뜨지 않았다" >&2; cat "$log" >&2
      kill "$pid" 2>/dev/null || true; rm -f "$STATE_DIR/$port.pid"; exit 1
    fi
    h="$(resolve_host "$HOST_ARG")"
    set_hint "$h"
    echo "PID:$pid"; echo "PORT:$port"
    # shellcheck disable=SC2046
    print_urls "$port" "$h" $(grep '^READY' "$log" | head -1 | cut -d' ' -f2-)
    ;;
  add)
    port="${1:?PORT 가 필요하다}"; shift
    split_args "$@"
    h="$(resolve_host "$HOST_ARG")"
    set_hint "$h"
    slugs=()
    for f in "${FILES[@]}"; do
      slugs+=("$(curl -fsS --data-binary "$f" "http://127.0.0.1:${port}/__register")")
    done
    print_urls "$port" "$h" "${slugs[@]}"
    ;;
  stop)
    port="${1:?PORT 가 필요하다}"
    pidf="$STATE_DIR/$port.pid"
    if [ -f "$pidf" ] && kill "$(cat "$pidf")" 2>/dev/null; then echo "STOPPED:$port"
    else echo "NOT-RUNNING:$port"; fi
    rm -f "$pidf" "$STATE_DIR/$port.log"
    ;;
  *)
    sed -n '2,15p' "$0"; exit 1 ;;
esac
