#!/usr/bin/env bash
# hc-popup.sh — 사용자 입력이 잠깐 필요한 명령(로그인·비밀번호·확인)을 Herdr 앱의 내 탭 옆 pane 으로
# 띄우고, 명령이 끝나면 pane 을 닫는다. 종료 코드는 그 명령의 것이다.
#
#   ~/.claude/skills/references/hc-popup.sh 'kinit chungha.kim'
#
# Claude 는 Bash run_in_background 로 돌려 종료 통지를 받는다(foreground 면 명령이 끝날 때까지 막힌다).
# 브라우저만 필요한 명령(mail-agent login 등 SSO relay)은 pane 도 필요 없다 — 백그라운드로 돌리고
# 찍힌 주소를 사용자에게 알린다. 이 스크립트는 터미널에 직접 쳐야 하는 입력이 있을 때 쓴다.
#
# HC_POPUP_TIMEOUT(초, 기본 900)이 지나면 124 로 돌아오지만 pane 의 명령은 계속 돈다.
# exit 2: Herdr 앱 밖이거나 내 터미널이 앱 화면 밖이라 띄울 수 없다 — 사용자에게 직접 치라고 안내한다.
set -euo pipefail

if [ -z "${HC_TERMINAL_SOCKET:-}" ] || [ -n "${HERDR_ENV:-}" ]; then
  echo "hc-popup: Herdr 앱 터미널이 아니다" >&2
  exit 2
fi
if [ $# -eq 0 ]; then
  echo "사용: hc-popup.sh '<명령>'" >&2
  exit 2
fi

me=$(hc get "$HC_TERMINAL_ID")
space=$(jq -r '.labels["herdr.space"] // empty' <<<"$me")
tab=$(jq -r '.labels["herdr.tab"] // empty' <<<"$me")
if [ -z "$space" ] || [ -z "$tab" ]; then
  echo "hc-popup: 이 터미널은 앱 화면 밖이다(탭 레이블 없음) — 띄워도 보이지 않는다" >&2
  exit 2
fi

# hc 터미널은 코어의 환경으로 떠서 PATH 에 ~/.local/bin 이 없다 — 부른 쪽 PATH·cwd 를 실어 보낸다.
# 실패하면 pane 이 곧바로 사라지지 않게 남겨 사용자가 에러를 읽게 한다. 명령 안의 exit 가 이 안내까지
# 끝내지 않도록 subshell 에서 돌린다.
script="export PATH=$(printf %q "$PATH")
cd $(printf %q "$PWD") || exit 1
( $* )
rc=\$?
if [ \$rc -ne 0 ]; then
  printf '\n[exit %s] Enter 를 치거나 30초 뒤 닫힌다\n' \$rc
  read -r -t 30 _ || true
fi
exit \$rc"

exec hc run --rm --no-notify --timeout "${HC_POPUP_TIMEOUT:-900}" \
  --label herdr.space="$space" --label herdr.tab="$tab" -- bash -c "$script"
