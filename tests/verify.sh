#!/bin/bash
set -euo pipefail

repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$repo_root"

scripts=(claude/skills/references/backlog-context.sh)
tests=(tests/test-backlog-context.sh tests/test-task-252-metrics.sh)

bash -n "${scripts[@]}" "${tests[@]}" tests/verify.sh
shellcheck -S error "${scripts[@]}" "${tests[@]}" tests/verify.sh
for test in "${tests[@]}"; do
  bash "$test"
done
