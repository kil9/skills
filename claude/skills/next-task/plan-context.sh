#!/bin/bash
# 플랜 계열 스킬 공통 헬퍼: 플랜 파일 결정·계열별 다음 번호 계산·(옵션) 전문 덤프를 한 번에.
# 사용법: plan-context.sh [--dump]
#   기본   : primary 플랜 파일 + 파일별 T/I/M 현재 최대 번호와 다음 번호
#   --dump : 각 플랜 파일 전문을 헤더와 함께 출력 (next-plan 등 전체 파악용)
# 플랜 파일이 하나도 없으면 exit 1 — 호출측(스킬)이 make-a-plan 을 안내한다.
# 번호 계산은 표준 표기(T-N/I-N/M-N)만 인식한다. 비표준 표기(T1, NU-3 등)는 정규화하지
# 않으므로 덤프 원문을 근거로 모델이 판단한다.
set -euo pipefail

dump=0
[ "${1:-}" = "--dump" ] && dump=1

files=()
[ -f PLAN.md ] && files+=(PLAN.md)
while IFS= read -r f; do
  files+=("$f")
done < <(ls -1t PLAN_*.md 2>/dev/null || true)

if [ ${#files[@]} -eq 0 ]; then
  echo "error: PLAN.md / PLAN_*.md 없음" >&2
  exit 1
fi

echo "## primary"
echo "${files[0]}"

echo
echo "## numbers (파일별 현재 최대 → 다음 번호)"
for f in "${files[@]}"; do
  line="$f:"
  for k in T I M; do
    max=$(grep -oE "\b$k-[0-9]+" "$f" | sed "s/^$k-//" | sort -n | tail -1 || true)
    if [ -n "$max" ]; then
      line+="  $k-max=$k-$max next=$k-$((max + 1))"
    else
      line+="  $k=none next=$k-1"
    fi
  done
  echo "$line"
done

if [ "$dump" -eq 1 ]; then
  for f in "${files[@]}"; do
    echo
    echo "===== $f ====="
    cat "$f"
  done
fi
