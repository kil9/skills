#!/bin/bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

# 착수 가드 테스트가 목록에 없어 게이트를 안 타고 있었다 — file:// 픽스처와 NO_FETCH 로 돌아
# 네트워크가 필요 없고 1초도 안 걸린다(task-314). ID 가드와 그 테스트는 2026-08-22 에 걷어냈다
# (kil9conf task-441·442 — 예방 기계의 유지보수가 그것이 막은 사고보다 많았다).
scripts=(
  claude/skills/references/backlog-context.sh
  claude/skills/references/backlog-start-guard.sh
)
tests=(
  tests/test-backlog-context.sh
  tests/test-backlog-start-guard.sh
  tests/test-backlog-hidden-guard.sh
  tests/test-task-252-metrics.sh
)

bash -n "${scripts[@]}" "${tests[@]}" tests/verify.sh
shellcheck -S error "${scripts[@]}" "${tests[@]}" tests/verify.sh
for test in "${tests[@]}"; do
  bash "$test"
done
