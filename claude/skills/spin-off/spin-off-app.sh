#!/usr/bin/env bash
# spin-off-app.sh <repo dir> <prompt file> [name]
# Herdr 앱(herdr-core)에서 <repo dir> 의 space 에 탭을 붙이고 `ca "$(< prompt)"` 를 띄운다.
# 그 folder 의 space 가 없으면 새로 만들고 name 을 repo 이름으로 채운다. 포커스는 옮기지 않는다.
# [name] 을 주면 `ca -n <name>` 으로 띄워 탭·사이드바·ListAgents 이름을 처음부터 고정한다.
# 성공하면 stdout 에 JSON 한 줄: {terminal, space, space_name, tab, new_space, app}
set -euo pipefail

repo="${1:?usage: spin-off-app.sh <repo dir> <prompt file>}"
prompt="${2:?usage: spin-off-app.sh <repo dir> <prompt file>}"
[ -n "${HC_TERMINAL_SOCKET:-}" ] || { echo "not in the Herdr app (no HC_TERMINAL_SOCKET)" >&2; exit 2; }
[ -d "$repo" ] || { echo "no such dir: $repo" >&2; exit 2; }
[ -s "$prompt" ] || { echo "empty or missing prompt file: $prompt" >&2; exit 2; }
name="${3:-}"
# K9_RUN 이 셸 문자열로 타이핑되므로 이름은 따옴표가 필요 없는 문자만 받는다.
[[ -z "$name" || "$name" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "name must match [A-Za-z0-9._-]+: $name" >&2; exit 2; }
repo_real="$(realpath "$repo")"
prompt="$(realpath "$prompt")"
# Windows core(Git Bash 에서 호출)에는 env·zsh 가 없고, 레이아웃 문서의 folder 는 `D:\work\x` 꼴이다.
win=false; case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) win=true ;; esac
norm() { if $win; then realpath -m "$(cygpath -u "$1")"; else realpath -m "$1"; fi; }

doc_get() {
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"hello","params":{"generation":1}}' \
    '{"jsonrpc":"2.0","id":2,"method":"doc.get","params":{"name":"herdr-app"}}' \
    | hc connect | tail -1 | jq -c '.result'
}

# 1) folder 로 space 찾기. 심링크(ha.kil9.dev -> home.kil9.dev)가 있어 양쪽 다 realpath 로 비교한다.
space="" new_space=false
while IFS=$'\t' read -r sid sfolder; do
  [ -n "$sfolder" ] || continue
  if [ "$(norm "$sfolder")" = "$repo_real" ]; then space="$sid"; break; fi
done < <(doc_get | jq -r '.value.spaces[] | [.id, (.folder // "")] | @tsv')
if [ -z "$space" ]; then
  space="sp$(head -c16 /dev/urandom | xxd -p)"; new_space=true
fi
tab="tb$(head -c16 /dev/urandom | xxd -p)"

# 2) 띄우기. hc run 은 호출한 쪽 환경을 넘기지 않으므로 ccs 프로필을 env 로 직접 싣는다.
#    ca 는 login zsh 의 alias 라 K9_RUN 으로 첫 프롬프트에 타이핑시킨다.
if $win; then
  # Windows: ca alias 가 없다. 앱이 직접 띄운 세션과 같은 꼴(pwsh -Command, claude -n)로 띄운다(2026-11-16 실측).
  ps="claude ${name:+-n $name }(Get-Content -Raw '$(cygpath -w "$prompt")')"
  [ -n "${CLAUDE_CONFIG_DIR:-}" ] && ps="\$env:CLAUDE_CONFIG_DIR='$(cygpath -w "$CLAUDE_CONFIG_DIR")'; $ps"
  cmd=(pwsh -NoLogo -NoExit -Command "$ps")
  cwd="$(cygpath -w "$repo_real")"
else
  envs=()
  [ -n "${CLAUDE_CONFIG_DIR:-}" ] && envs+=("CLAUDE_CONFIG_DIR=$CLAUDE_CONFIG_DIR")
  cmd=(env "${envs[@]}" "K9_RUN=ca ${name:+-n $name }\"\$(< $prompt)\"" zsh -l)
  cwd="$repo_real"
fi
out="$(env -u HC_TERMINAL_ID -u HC_SCOPE hc run --bg --json --no-parent --cwd "$cwd" \
  --label "herdr.space=$space" --label "herdr.tab=$tab" -- "${cmd[@]}")"
term="$(jq -r '.address // .id // .terminal // empty' <<<"$out")"
[ -n "$term" ] || { echo "hc run gave no terminal: $out" >&2; exit 1; }

# 3) 새 space 면 name 채우기. folder 는 앱이 터미널 cwd 로 채우지만 name 은 빈 채로 남는다(2026-11-16 실측).
space_name="$(basename "$repo_real")"
if $new_space; then
  for _ in $(seq 1 20); do
    r="$(doc_get)"
    if jq -e --arg s "$space" '.value.spaces[] | select(.id==$s)' <<<"$r" >/dev/null; then
      req="$(jq -c --arg s "$space" --arg n "$space_name" \
        '{jsonrpc:"2.0",id:3,method:"doc.set",params:{name:"herdr-app",version:.version,
          value:(.value | .spaces |= map(if .id==$s then .name=$n else . end))}}' <<<"$r")"
      res="$(printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"hello","params":{"generation":1}}' "$req" | hc connect | tail -1)"
      jq -e '.error' <<<"$res" >/dev/null || break   # 충돌이면 앱이 먼저 쓴 것 — 다시 읽어 재시도
    fi
    sleep 0.5
  done
else
  space_name="$(doc_get | jq -r --arg s "$space" '.value.spaces[] | select(.id==$s) | .name // ""')"
fi

# 4) claude 가 자기 상태를 보고할 때까지 기다린다. 처음 보는 folder 는 신뢰 프롬프트에서 멈춘다.
app=""
for _ in $(seq 1 60); do
  app="$(hc get "$term" 2>/dev/null | jq -r '.status.app // empty')"
  [ "$app" = claude-code ] && break
  if hc read "$term" --lines 60 2>/dev/null | grep -q 'trust this folder'; then app="trust-prompt"; break; fi
  sleep 1
done

jq -nc --arg t "$term" --arg s "$space" --arg sn "$space_name" --arg tb "$tab" \
  --argjson ns "$new_space" --arg a "${app:-none}" \
  '{terminal:$t, space:$s, space_name:$sn, tab:$tb, new_space:$ns, app:$a}'
[ "$app" = claude-code ]
