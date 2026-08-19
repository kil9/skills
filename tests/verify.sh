#!/bin/bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

# ID·착수 가드 테스트가 목록에 없어 게이트를 안 타고 있었다 — 두 스크립트 다 file:// 픽스처와
# NO_FETCH 로 돌아 네트워크가 필요 없고 1초도 안 걸린다(task-314).
scripts=(
  claude/skills/references/backlog-context.sh
  claude/skills/references/backlog-id-guard.sh
  claude/skills/references/backlog-start-guard.sh
)
tests=(
  tests/test-backlog-context.sh
  tests/test-backlog-id-guard.sh
  tests/test-backlog-start-guard.sh
  tests/test-backlog-hidden-guard.sh
  tests/test-task-252-metrics.sh
)

bash -n "${scripts[@]}" "${tests[@]}" tests/verify.sh
shellcheck -S error "${scripts[@]}" "${tests[@]}" tests/verify.sh
for test in "${tests[@]}"; do
  bash "$test"
done
