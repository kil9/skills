---
description: 레거시 PLAN.md 저장소를 backlog 백엔드로 전환한다. "backlog 로 옮겨줘 / PLAN.md 전환해줘" 라고 할 때. 신규 계획 수립은 /init-backlog 다. 구현은 시작하지 않는다.
allowed_tools: [Bash, Read, Edit, Write, Glob, Grep, AskUserQuestion, Skill]
---

전환할 대상: `$ARGUMENTS`

PLAN.md(또는 `PLAN_*.md`)의 미완료 작업·아이디어·산문을 backlog 로 **충실히 옮기고** PLAN 파일은 아카이브로
보존한다. 계획을 새로 짜지 않는다(그건 `/init-backlog`). 구현은 시작하지 않는다. 공통 전제는
[`../references/backlog-basics.md`](../references/backlog-basics.md).

- PLAN 파일이 없으면 이관할 것이 없다 — `/init-backlog` 안내.
- `backlog/` 가 이미 있으면 재실행이거나 부분 전환이다. 초기화를 건너뛰고 아직 없는 항목만 옮긴다(제목 대조로
  중복 생성 금지).

## 도구

- `bash ~/.claude/skills/migrate-to-backlog/plan-context.sh --dump` — 모든 PLAN 파일 전문과 파일별 T/I/M 번호.
  표기가 비표준(`T1`, `NU-3`)이면 번호 계산보다 원문을 믿는다.
- 초기화가 필요하면 `backlog init "<프로젝트명>" --defaults --integration-mode none --zero-padded-ids 0` 후
  `bash ~/.claude/skills/init-backlog/backlog-config-standard.sh`(`/init-backlog` 과 같은 표준).

## 매핑

| PLAN | backlog |
|---|---|
| 미완료 `T-N` (`[ ]` `[→]` `[!]`) | `task create`(원 항목을 Description 에). `[→]` → In Progress, `[!]` → Blocked + 사유 |
| 완료 `[x]` | 옮기지 않는다 — 아카이브 원문에 남는다 |
| 아이디어 `I-N` | `draft create`(구상 무손실, `--ac` 없음) |
| `M-N`(실제로 쓰였으면) | `milestone add` + 태스크 `-m` |
| 배경·목표·설계 결정 등 산문 | `doc create` 후 `doc update <id> --content`, 뚜렷한 결정 블록은 `decision create` |

- 완료 조건이 원문에 드러나면 그대로 `--ac` 로, 불명확한 항목만 모아 묻는다. 계획을 재협상하지 않는다.
- **의존은 2차로 건다** — 선행이 아직 안 만들어졌을 수 있으니 전부 만든 뒤 `구 T-N → 새 task-N` 매핑으로
  `task edit --dep`. 선행이 `[x]` 였으면 이미 충족이므로 생략.

## PLAN 아카이브

지우지 않고 맨 위에 헤더를 붙인다(이미 동결 헤더가 있으면 문구만 정리):

```markdown
> **아카이브 (YYYY-MM-DD)**: 이 파일은 backlog 백엔드로 전환되어 더 이상 갱신하지 않는다.
> 미완료 태스크는 backlog(`backlog/`)로 이관됨 — 조회는 `/next-backlog`. 아이디어는 draft 로 이관.
> 완료 이력·전환 시 옮기지 않은 서술의 아카이브로만 유지한다.
```

## 보고

구 T-N → 새 task-N(상태), 구 I-N → draft, doc/decision, 아카이브한 파일. 완료 이력은 아카이브 원문에 남아
있다고 밝히고 멈춘다. 이후 진행은 `/start-backlog`, 추가는 `/add-backlog`.
