#!/usr/bin/env bash
set -euo pipefail

usage() {
  printf '%s\n' \
    'Usage: run-worker.sh --model luna|terra --cwd DIR --sandbox read-only|workspace-write [--output FILE]'
}

worker_model=''
worker_cwd=''
worker_sandbox=''
worker_output=''

while (($#)); do
  case "$1" in
    --model)
      worker_model=${2-}
      shift 2
      ;;
    --cwd)
      worker_cwd=${2-}
      shift 2
      ;;
    --sandbox)
      worker_sandbox=${2-}
      shift 2
      ;;
    --output)
      worker_output=${2-}
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

case "$worker_model" in
  luna)
    model_slug='gpt-5.6-luna'
    model_effort='max'
    ;;
  terra)
    model_slug='gpt-5.6-terra'
    model_effort='high'
    ;;
  *)
    printf '%s\n' '--model must be luna or terra' >&2
    exit 2
    ;;
esac

if [[ ! -d "$worker_cwd" ]]; then
  printf 'cwd is not a directory: %s\n' "$worker_cwd" >&2
  exit 2
fi

case "$worker_sandbox" in
  read-only|workspace-write) ;;
  *)
    printf '%s\n' '--sandbox must be read-only or workspace-write' >&2
    exit 2
    ;;
esac

if ! command -v codex >/dev/null 2>&1; then
  printf '%s\n' 'codex CLI not found' >&2
  exit 127
fi

codex_args=(
  exec
  --ephemeral
  --model "$model_slug"
  --config "model_reasoning_effort=\"$model_effort\""
  --config 'approval_policy="never"'
  --disable multi_agent
  --disable multi_agent_v2
  --sandbox "$worker_sandbox"
  --cd "$worker_cwd"
  --color never
)

if [[ -n "$worker_output" ]]; then
  codex_args+=(--output-last-message "$worker_output")
fi

exec codex "${codex_args[@]}" -
