#!/bin/bash
# backlog 스킬군 공유: backlog/config.yml 을 이 저장소군의 표준으로 맞춘다. 멱등.
# 소비: /init-backlog, /migrate-to-backlog (미러는 이 파일로의 상대 심링크)
# 사용법: backlog-config-standard.sh [<config.yml 경로>]   (기본: backlog/config.yml)
#
# 표준의 근거:
#   - statuses/default_status: 스킬군이 "To Do"/"In Progress"/"Done"/"Blocked" 를 전제한다.
#     `backlog config set` 은 statuses 를 다루지 않으므로 config.yml 을 직접 편집한다
#     (태스크·문서 마크다운이 아니라 설정 파일이므로 직접 편집이 안전).
#   - auto_commit=false: 커밋은 /commit 규칙대로 사람이 통제한다.
#   - remoteOperations=false (origin 이 없을 때만): 리모트명이 origin 이 아니거나 리모트가
#     없는 저장소에서 backlog 가 fetch 를 시도하다 에러를 내는 것을 막는다.
set -euo pipefail

cfg="${1:-backlog/config.yml}"
[ -f "$cfg" ] || { echo "error: config 없음: $cfg — 먼저 backlog init 을 실행할 것" >&2; exit 1; }

changed=0

# statuses / default_status
if ! grep -q '^statuses:.*"To Do".*"In Progress".*"Done".*"Blocked"' "$cfg"; then
  if grep -q '^statuses:' "$cfg"; then
    perl -pi -e 's|^statuses:.*$|statuses: ["To Do", "In Progress", "Done", "Blocked"]|' "$cfg"
  else
    printf 'statuses: ["To Do", "In Progress", "Done", "Blocked"]\n' >> "$cfg"
  fi
  echo "set: statuses"; changed=1
fi

if ! grep -q '^default_status: *"\?To Do"\?' "$cfg"; then
  if grep -q '^default_status:' "$cfg"; then
    perl -pi -e 's|^default_status:.*$|default_status: "To Do"|' "$cfg"
  else
    printf 'default_status: "To Do"\n' >> "$cfg"
  fi
  echo "set: default_status"; changed=1
fi

# auto_commit
if ! grep -q '^auto_commit: *false' "$cfg"; then
  if grep -q '^auto_commit:' "$cfg"; then
    perl -pi -e 's|^auto_commit:.*$|auto_commit: false|' "$cfg"
  else
    printf 'auto_commit: false\n' >> "$cfg"
  fi
  echo "set: auto_commit=false"; changed=1
fi

# remoteOperations — origin 이 없을 때만 끈다.
if ! git remote get-url origin >/dev/null 2>&1; then
  if ! grep -q '^remote_operations: *false' "$cfg"; then
    backlog config set remoteOperations false >/dev/null 2>&1 \
      || perl -pi -e 's|^remote_operations:.*$|remote_operations: false|' "$cfg"
    grep -q '^remote_operations:' "$cfg" || printf 'remote_operations: false\n' >> "$cfg"
    echo "set: remoteOperations=false (origin 리모트 없음)"; changed=1
  fi
fi

[ "$changed" -eq 0 ] && echo "config 표준 이미 적용됨: $cfg" || echo "config 표준 적용 완료: $cfg"
