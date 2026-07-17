#!/usr/bin/env bash
# /paste-image skill 용 실행 래퍼.
#
# 서브커맨드:
#   start [port] [host=<name>]
#     일회용 서버를 백그라운드로 기동하고 URL 을 stdout 에 출력한 뒤 즉시 반환.
#     Claude 가 URL 을 파싱해 사용자에게 안내할 수 있도록 두 줄을 출력한다:
#       SESSION:<session-dir>
#       LISTEN:<url>
#
#   wait <session-dir>
#     start 가 돌려준 세션 디렉토리를 받아 서버가 종료될 때까지 대기.
#     결과를 stdout 에 출력:
#       SAVED:<path>   (성공, exit 0)
#       TIMEOUT        (타임아웃, exit 2)
#
#   ensure [port] [host=<name>]
#     상시 서버(persist) 보장 기동. 이미 떠 있으면 URL 만 출력하고 즉시 반환.
#     토큰을 tmp/persist/token 에 영속화해 재기동해도 URL 이 유지된다(북마크용).
#     LLM 없이 `! pimg` (rc/bin/pimg) 로 부르는 빠른 경로의 백엔드.
#
#   stop   — 상시 서버 중지
#   last   — 상시 서버가 마지막으로 저장한 업로드 경로 출력
#
#   (인자 없음)  — 기존 foreground 동작 유지 (하위 호환)

set -euo pipefail

SKILL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 기본 호스트 결정 우선순위 (높은 것이 이긴다):
#   0. host.local 의 FUNNEL_BASE_URL  (Tailscale Funnel 전용, 설정 시 HOST/캐시 무시)
#   1. host=<name> 인자        (일회성 override)
#   2. $PASTE_IMAGE_HOST       (env override)
#   3. host.local 의 HOST       (사용자 수동, gitignored)
#   4. host.cache 의 HOST       (자동 검증 결과, gitignored)
#   5. 캐시가 없으면: $PASTE_IMAGE_HOST_DOMAIN 이 설정돼 있으면 $(hostname).$PASTE_IMAGE_HOST_DOMAIN 이
#                    DNS 로 풀리는지 검증 → 성공: 그대로 사용 / 실패 또는 미설정: localhost
#                    → 결과를 host.cache 에 기록해서 다음부터는 5번을 건너뜀.

# FUNNEL_BASE_URL 이 host.local 에 설정돼 있으면 그 값을 전역으로 노출.
FUNNEL_BASE_URL=""
_override_file="$SKILL_DIR/host.local"
if [ -f "$_override_file" ]; then
  # shellcheck disable=SC1090,SC1091
  . "$_override_file"
fi
unset _override_file

resolve_default_host() {
  local override_file="$SKILL_DIR/host.local"
  local cache_file="$SKILL_DIR/host.cache"

  if [ -f "$override_file" ]; then
    local HOST=""
    # shellcheck disable=SC1090,SC1091
    . "$override_file"
    if [ -n "${HOST:-}" ]; then
      printf '%s' "$HOST"
      return
    fi
  fi

  if [ ! -f "$cache_file" ]; then
    local resolved="localhost"
    if [ -n "${PASTE_IMAGE_HOST_DOMAIN:-}" ]; then
      local candidate="$(hostname).${PASTE_IMAGE_HOST_DOMAIN}"
      resolved="$candidate"
      if command -v getent >/dev/null 2>&1 && command -v timeout >/dev/null 2>&1; then
        if ! timeout 2 getent hosts "$candidate" >/dev/null 2>&1; then
          resolved="localhost"
        fi
      fi
    fi
    printf 'HOST=%s\n' "$resolved" > "$cache_file"
  fi

  local HOST=""
  # shellcheck disable=SC1090,SC1091
  . "$cache_file"
  printf '%s' "${HOST:-localhost}"
}

DEFAULT_HOST="$(resolve_default_host)"

# --- 서브커맨드 분기 ---
SUBCOMMAND="${1:-}"
STATE_DIR="$SKILL_DIR/tmp/persist"

# stop 서브커맨드: 상시 서버 중지
if [[ "$SUBCOMMAND" == "stop" ]]; then
  if [[ -f "$STATE_DIR/pid" ]] && kill -0 "$(cat "$STATE_DIR/pid")" 2>/dev/null; then
    kill "$(cat "$STATE_DIR/pid")"
    echo "상시 서버 중지됨 (pid $(cat "$STATE_DIR/pid"))"
  else
    echo "상시 서버가 실행 중이 아님"
  fi
  rm -f "$STATE_DIR/pid" "$STATE_DIR/listen"
  exit 0
fi

# last 서브커맨드: 상시 서버의 마지막 업로드 경로 출력
if [[ "$SUBCOMMAND" == "last" ]]; then
  LAST=""
  if [[ -f "$STATE_DIR/uploads.log" ]]; then
    LAST="$(grep '^SAVED:' "$STATE_DIR/uploads.log" | tail -1 | cut -d: -f2- || true)"
  fi
  if [[ -n "$LAST" ]]; then
    echo "$LAST"
    exit 0
  fi
  echo "ERROR:업로드 이력 없음" >&2
  exit 1
fi

# wait 서브커맨드: 세션 디렉토리를 받아 서버 종료를 기다린다
if [[ "$SUBCOMMAND" == "wait" ]]; then
  SESSION_DIR="${2:-}"
  if [[ -z "$SESSION_DIR" || ! -d "$SESSION_DIR" ]]; then
    echo "ERROR:세션 디렉토리를 찾을 수 없음: $SESSION_DIR" >&2
    exit 1
  fi
  PID_FILE="$SESSION_DIR/pid"
  RESULT_FILE="$SESSION_DIR/result"
  if [[ -f "$PID_FILE" ]]; then
    SERVER_PID="$(cat "$PID_FILE")"
    # wait 는 자식 프로세스에만 동작하므로 kill -0 으로 생존 확인하며 폴링
    while kill -0 "$SERVER_PID" 2>/dev/null && [[ ! -s "$RESULT_FILE" ]]; do
      sleep 0.5
    done
  fi
  if [[ -s "$RESULT_FILE" ]]; then
    cat "$RESULT_FILE"
  else
    echo "TIMEOUT"
  fi
  rm -rf "$SESSION_DIR"
  exit 0
fi

# 포트·호스트 파싱 (start 서브커맨드와 기존 foreground 공통)
PORT=13000
HOST="${PASTE_IMAGE_HOST:-$DEFAULT_HOST}"

# start/ensure 의 경우 첫 번째 인자를 건너뜀
ARG_START=1
[[ "$SUBCOMMAND" == "start" || "$SUBCOMMAND" == "ensure" ]] && ARG_START=2

for arg in "${@:$ARG_START}"; do
  case "$arg" in
    host=*)
      HOST="${arg#host=}"
      ;;
    ''|*[!0-9]*)
      echo "WARN: 무시된 인자 '$arg' (형식: <port 번호> 또는 host=<name>)" >&2
      ;;
    *)
      PORT="$arg"
      ;;
  esac
done

# start 서브커맨드: 백그라운드 기동 후 즉시 URL 반환
if [[ "$SUBCOMMAND" == "start" ]]; then
  SESSION_DIR="$(mktemp -d /tmp/paste-image-XXXXXX)"
  LISTEN_FILE="$SESSION_DIR/listen"
  RESULT_FILE="$SESSION_DIR/result"
  PID_FILE="$SESSION_DIR/pid"
  ERROR_LOG="$SESSION_DIR/stderr.log"

  if [[ -n "${FUNNEL_BASE_URL:-}" ]]; then
    python3 "$SKILL_DIR/server.py" \
      --port "$PORT" --public-url-base "$FUNNEL_BASE_URL" --listen-file "$LISTEN_FILE" \
      > "$RESULT_FILE" 2>"$ERROR_LOG" &
  else
    python3 "$SKILL_DIR/server.py" \
      --port "$PORT" --host-hint "$HOST" --listen-file "$LISTEN_FILE" \
      > "$RESULT_FILE" 2>"$ERROR_LOG" &
  fi
  echo $! > "$PID_FILE"

  # LISTEN URL 이 파일에 기록될 때까지 최대 5초 대기 (0.1초 간격, 50회)
  for i in $(seq 50); do
    [[ -s "$LISTEN_FILE" ]] && break
    sleep 0.1
  done

  if [[ ! -s "$LISTEN_FILE" ]]; then
    echo "ERROR:서버가 5초 내에 시작되지 않음" >&2
    if [[ -s "$ERROR_LOG" ]]; then
      echo "---- server stderr ----" >&2
      cat "$ERROR_LOG" >&2
    fi
    rm -rf "$SESSION_DIR"
    exit 1
  fi

  echo "SESSION:$SESSION_DIR"
  printf 'LISTEN:%s' "$(cat "$LISTEN_FILE")"
  exit 0
fi

# ensure 서브커맨드: 상시 서버 보장 기동 (떠 있으면 URL 만 재출력)
if [[ "$SUBCOMMAND" == "ensure" ]]; then
  mkdir -p "$STATE_DIR"
  PID_FILE="$STATE_DIR/pid"
  LISTEN_FILE="$STATE_DIR/listen"
  TOKEN_FILE="$STATE_DIR/token"

  if [[ -f "$PID_FILE" ]] && kill -0 "$(cat "$PID_FILE")" 2>/dev/null && [[ -s "$LISTEN_FILE" ]]; then
    echo "LISTEN:$(cat "$LISTEN_FILE")"
    echo "이미 실행 중 — 브라우저에서 위 URL 을 열고 Ctrl+V. 업로드되면 원격 경로가 클립보드에 복사되니 챗창에 붙여넣으면 된다."
    exit 0
  fi

  rm -f "$PID_FILE" "$LISTEN_FILE"
  if [[ -n "${FUNNEL_BASE_URL:-}" ]]; then
    nohup python3 "$SKILL_DIR/server.py" \
      --persist --port "$PORT" --public-url-base "$FUNNEL_BASE_URL" \
      --token-file "$TOKEN_FILE" --listen-file "$LISTEN_FILE" \
      >> "$STATE_DIR/uploads.log" 2>"$STATE_DIR/stderr.log" &
  else
    nohup python3 "$SKILL_DIR/server.py" \
      --persist --port "$PORT" --host-hint "$HOST" \
      --token-file "$TOKEN_FILE" --listen-file "$LISTEN_FILE" \
      >> "$STATE_DIR/uploads.log" 2>"$STATE_DIR/stderr.log" &
  fi
  echo $! > "$PID_FILE"

  for i in $(seq 50); do
    [[ -s "$LISTEN_FILE" ]] && break
    sleep 0.1
  done

  if [[ ! -s "$LISTEN_FILE" ]]; then
    echo "ERROR:상시 서버가 5초 내에 시작되지 않음" >&2
    if [[ -s "$STATE_DIR/stderr.log" ]]; then
      echo "---- server stderr ----" >&2
      cat "$STATE_DIR/stderr.log" >&2
    fi
    rm -f "$PID_FILE"
    exit 1
  fi

  echo "LISTEN:$(cat "$LISTEN_FILE")"
  echo "상시 서버 시작 — 브라우저에서 위 URL 을 열고 Ctrl+V. 업로드되면 원격 경로가 클립보드에 복사되니 챗창에 붙여넣으면 된다. (중지: pimg stop)"
  exit 0
fi

# 기본 (서브커맨드 없음): 기존 foreground 동작
if [[ -n "${FUNNEL_BASE_URL:-}" ]]; then
  exec python3 "$SKILL_DIR/server.py" --port "$PORT" --public-url-base "$FUNNEL_BASE_URL"
else
  exec python3 "$SKILL_DIR/server.py" --port "$PORT" --host-hint "$HOST"
fi
