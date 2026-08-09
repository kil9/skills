#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf '%s\n' 'Usage: check-usage.sh [--cwd DIR]'
}

usage_cwd=$PWD

while (($#)); do
  case "$1" in
    --cwd)
      if (($# < 2)) || [[ -z ${2-} ]]; then
        printf '%s\n' '--cwd requires a directory' >&2
        usage >&2
        exit 2
      fi
      usage_cwd=${2-}
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      printf 'Unknown argument: %s\n' "$1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ ${HERDR_ENV-} != 1 ]]; then
  printf '%s\n' 'HERDR_ENV=1 is required' >&2
  exit 2
fi

if [[ ! -d $usage_cwd ]]; then
  printf 'cwd is not a directory: %s\n' "$usage_cwd" >&2
  exit 2
fi

for command_name in claude herdr python3; do
  if ! command -v "$command_name" >/dev/null 2>&1; then
    printf 'required command not found: %s\n' "$command_name" >&2
    exit 127
  fi
done

usage_tmp=$(mktemp -d /tmp/opus-usage.XXXXXX)
usage_pane=''

cleanup() {
  cleanup_status=$?
  trap - EXIT INT TERM HUP
  if [[ -n $usage_pane ]]; then
    herdr pane close "$usage_pane" >/dev/null 2>&1 || true
  fi
  rm -rf -- "$usage_tmp"
  exit "$cleanup_status"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
trap 'exit 129' HUP

if ! claude auth status --json >"$usage_tmp/auth.json" 2>"$usage_tmp/auth.err"; then
  printf '%s\n' 'unable to read Claude authentication status' >&2
  sed -n '1,20p' "$usage_tmp/auth.err" >&2
  exit 1
fi

auth_summary=$(python3 - "$usage_tmp/auth.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as source:
    data = json.load(source)

print("\t".join([
    "true" if data.get("loggedIn") else "false",
    str(data.get("authMethod") or "unknown"),
    str(data.get("apiProvider") or "unknown"),
    str(data.get("subscriptionType") or "none"),
]))
PY
)
IFS=$'\t' read -r logged_in auth_method api_provider subscription_type <<<"$auth_summary"

if [[ $logged_in != true ]]; then
  printf '%s\n' '{"status":"not-logged-in","metering":"unknown"}'
  exit 0
fi

if [[ $auth_method != claude.ai ]]; then
  python3 - "$auth_method" "$api_provider" "$subscription_type" <<'PY'
import json
import sys

print(json.dumps({
    "status": "blocked-payg",
    "metering": "payg-or-external",
    "auth_method": sys.argv[1],
    "api_provider": sys.argv[2],
    "subscription_type": sys.argv[3],
}, ensure_ascii=False))
PY
  exit 0
fi

pane_json=$(herdr pane split --current --direction right --no-focus --cwd "$usage_cwd")
usage_pane=$(printf '%s' "$pane_json" \
  | python3 -c 'import json,sys; print(json.load(sys.stdin)["result"]["pane"]["pane_id"])')
agent_name="opususage$$"

herdr agent start "$agent_name" --kind claude --pane "$usage_pane" -- \
  --model opus --effort low --ax-screen-reader >"$usage_tmp/start.json" \
  2>"$usage_tmp/start.err" || start_failed=1

if [[ ${start_failed-0} == 1 ]]; then
  herdr pane read "$usage_pane" --source visible --lines 80 --format text \
    >"$usage_tmp/start.txt" || true
  if grep -Eqi 'trust (this folder|the files in this folder)|is this a project you trust' \
      "$usage_tmp/start.txt"; then
    printf '%s\n' 'Claude folder trust is required; inspect and trust the cwd manually' >&2
    exit 1
  fi
  if grep -q '"code":"agent_pane_busy"' "$usage_tmp/start.json" "$usage_tmp/start.err" \
      && [[ -s $usage_tmp/start.txt ]]; then
    sleep 0.2
    herdr agent start "$agent_name" --kind claude --pane "$usage_pane" -- \
      --model opus --effort low --ax-screen-reader >"$usage_tmp/start.json"
  else
    sed -n '1,20p' "$usage_tmp/start.json" >&2
    sed -n '1,20p' "$usage_tmp/start.err" >&2
    exit 1
  fi
fi

herdr pane read "$usage_pane" --source visible --lines 80 --format text >"$usage_tmp/start.txt"
if grep -Eqi 'trust (this folder|the files in this folder)|is this a project you trust' \
    "$usage_tmp/start.txt"; then
  printf '%s\n' 'Claude folder trust is required; inspect and trust the cwd manually' >&2
  exit 1
fi

herdr pane send-text "$usage_pane" '/usage'
herdr pane send-keys "$usage_pane" Enter
herdr pane wait-output "$usage_pane" --match 'Current week (all models)' \
  --timeout 20000 >/dev/null
herdr pane read "$usage_pane" --source recent-unwrapped --lines 240 --format text \
  >"$usage_tmp/usage.txt"

python3 - "$usage_tmp/usage.txt" "$auth_method" "$api_provider" "$subscription_type" <<'PY'
import json
import re
import sys

usage_path, auth_method, api_provider, subscription_type = sys.argv[1:]
with open(usage_path, encoding="utf-8") as source:
    lines = [line.strip() for line in source]

def read_section(label, stop_labels):
    indexes = [index for index, line in enumerate(lines) if label in line]
    if not indexes:
        return None, None
    used = None
    reset = None
    start = indexes[-1]
    for offset, line in enumerate(lines[start:start + 10]):
        if offset and any(stop_label in line for stop_label in stop_labels):
            break
        match = re.search(r"(\d+)%.*used", line)
        if match and used is None:
            used = int(match.group(1))
        if line.startswith("Resets ") and reset is None:
            reset = line.removeprefix("Resets ")
    return used, reset

session_used, session_reset = read_section(
    "Current session",
    ("Current week", "What's contributing"),
)
weekly_used, weekly_reset = read_section(
    "Current week (all models)",
    ("Current week (Sonnet", "What's contributing"),
)
status = "ok" if session_used is not None and weekly_used is not None else "unreadable"

print(json.dumps({
    "status": status,
    "metering": "subscription",
    "auth_method": auth_method,
    "api_provider": api_provider,
    "subscription_type": subscription_type,
    "session_used_pct": session_used,
    "session_reset": session_reset,
    "weekly_all_models_used_pct": weekly_used,
    "weekly_all_models_reset": weekly_reset,
    "diagnostic": None if status == "ok" else "required /usage sections or percentages were not found",
}, ensure_ascii=False))
PY
