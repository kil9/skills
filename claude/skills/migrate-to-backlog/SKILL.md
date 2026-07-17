---
description: 레거시 PLAN.md 저장소를 backlog 백엔드로 전환한다. 미완료 T-N 은 backlog task 로, I-N 은 draft 로, 산문(배경·설계 결정)은 backlog/docs/ 로 옮기고, PLAN 파일은 아카이브 헤더를 달아 보존한다. 완료(`[x]`) 항목은 옮기지 않고 아카이브 원문에 남긴다. 구현은 시작하지 않는다.
allowed_tools: [Bash, Read, Edit, Write, Glob, Grep, AskUserQuestion, Skill]
---

전환할 대상: `$ARGUMENTS`

이 스킬은 **레거시 PLAN.md 저장소를 backlog 백엔드로 전환**한다. 계획을 새로 짜지 않는다 — 이미 PLAN
에 있는 미완료 작업·아이디어·산문을 backlog 로 **충실히 이관**하고 PLAN 파일을 아카이브로 보존한다.

`/init-backlog` 과의 경계: init-backlog 은 기존 PLAN 을 건드리지 않고 인터뷰로 **새 계획**을 세운다.
migrate 는 그 반대로, 기존 PLAN 의 내용을 backlog 로 **옮기는** 전용 스킬이다. 그래서 init-backlog 을
돌려도 채워지지 않는 공백(레거시 PLAN 의 자동 이관)을 메운다.

**backlog CLI 조회는 항상 `--plain`.** board·browser 등 인터랙티브 명령은 실행하지 않는다. CLI 옵션이
낯설면 `backlog <command> --help` 로 확인한다.

## 0. 전제·모드 판별

- repo 루트에 **PLAN.md(또는 `PLAN_*.md`)가 없으면** 이관할 대상이 없다. `/init-backlog` 으로 새로
  계획을 세우도록 안내하고 멈춘다.
- **이미 `backlog/` 가 있으면** 부분 전환이거나 재실행이다. 초기화(§2)는 건너뛰고, 아직 backlog 에 없는
  미완료 항목만 골라 이관한다(중복 생성 금지 — `backlog task list --plain` 으로 기존 제목을 대조한다).
- 둘 다 없는 새 저장소면 이관이 아니라 신규 계획이므로 `/init-backlog` 로 보낸다.
- **CLI 없으면 중단.** `command -v backlog` 로 확인한다. 없으면 태스크 파일 손편집으로 폴백하지 말고
  (`SECTION:` 마커·ordinal·AC 포맷이 조용히 어긋난다) `bash "${K9HOME:-$HOME/kil9conf}/bootstrap/install-backlog-md.sh"`
  설치를 안내한 뒤 멈춘다.

## 1. 대상 파악 (전문 덤프)

이 SKILL.md 와 같은 디렉터리의 `plan-context.sh --dump` 를 Bash **1회** 호출해 모든 PLAN 파일 전문과
파일별 T/I/M 번호를 한 번에 받는다. Glob/Grep 으로 따로 찾지 않는다.

```bash
bash ~/.claude/skills/migrate-to-backlog/plan-context.sh --dump
```

exit 1(플랜 파일 없음)이면 §0 대로 `/init-backlog` 안내 후 멈춘다. 덤프에서 다음을 식별한다.

- **미완료 태스크**: `[ ]` TODO / `[→]` IN_PROGRESS / `[!]` BLOCKED 의 `T-N`. `[x]` DONE 은 **이관 대상이
  아니다**(§6 아카이브 원문에 그대로 남긴다).
- **아이디어**: "아이디어 (보류)" 섹션의 `I-N`.
- **산문**: 배경·현재 상태·설계/결정 이력 등 태스크가 아닌 서술 블록.
- `M-N` 은 태스크를 묶는 상위 단위다(실행 단위 아님). 마일스톤이 실제로 쓰였으면 §4 에서 backlog
  milestone 으로 옮긴다.

표기가 비표준(`T1`, `NU-3` 등)이면 헬퍼의 번호 계산 대신 덤프 원문을 근거로 판단한다. PLAN 파일이
여럿이면 각각을 순회한다(파일별로 어떤 항목을 옮겼는지 보고에서 밝힌다).

## 2. backlog 초기화 (`backlog/` 없을 때만)

`backlog init` 부터 config 표준까지 migrate 가 직접 수행한다(사용자를 다른 스킬로 보내지 않는다). 이미
초기화돼 있으면 이 절 전체를 건너뛴다.

```bash
backlog init "<프로젝트명>" --defaults --integration-mode none --zero-padded-ids 0
```

`--integration-mode none` 으로 에이전트 지침 자동 주입을 막는다. 이어서 `backlog/config.yml` 을
공유 스크립트로 표준에 맞춘다(멱등). 항목을 손으로 확인하지 않는다.

```bash
bash ~/.claude/skills/init-backlog/backlog-config-standard.sh
```

`/init-backlog` 과 같은 스크립트다 — 표준이 한 곳에만 있어야 두 스킬이 어긋나지 않는다.

## 3. 산문 이관 → `backlog/docs/`

PLAN 의 서술 블록(배경·문제·목표·비목표·제약·접근/설계 결정·검증 방법)을 doc 으로 옮긴다. 세션 리셋
후에도 이 문서 + 태스크만으로 재개 가능할 만큼 담는다. 완료 태스크의 **결정 이력**처럼 앞으로도 참조할
가치가 있는 산문은 함께 옮긴다(단순 완료 로그는 아카이브 원문에 두고 옮기지 않아도 된다).

```bash
backlog doc create "<제목>"
backlog doc update <docId> --content "<본문 마크다운>"
```

`doc create` 는 본문을 받지 않으므로 생성 후 `doc update --content` 로 채운다. PLAN 에 설계 결정 블록이
뚜렷하면 doc 대신 `backlog decision create` 로 옮겨도 된다(Context/Decision/Consequences 채움).

## 4. 미완료 태스크 이관 → `backlog task`

미완료 `T-N` 마다 태스크를 만든다. **원 항목 내용을 충실히 옮기고, 부족한 완료 조건만 인터뷰로 보강**한다
(계획을 새로 협상하지 않는다 — AC 공백만 메운다).

1. **AC 확정.** 원 항목 본문에 완료 조건이 드러나면 그대로 `--ac` 로 옮긴다. 여러 T-N 을 훑어 **완료
   조건이 불명확한 항목만 모아** `AskUserQuestion` 으로 AC 를 확정한다(항목당 추측으로 채우지 않는다).
   `backlog task create` 는 `--ac` 를 최소 1개 요구한다.

2. **생성.** Description 에 원 PLAN 항목을 담고, AC 를 붙여 만든다.

   ```bash
   backlog task create "<제목>" --ac "<완료 조건>" --priority <high|medium|low> -l solo --plain
   ```

   - `--ac` 는 항목마다 반복. `-l solo` 는 원 항목에 "단독실행: 필요" 가 있을 때만.
   - 의존(`--dep`)은 대상 태스크가 아직 안 만들어졌을 수 있으므로 **1차 생성 때는 생략**한다.

3. **의존·상태 2차 반영.** 모든 미완료 태스크를 만든 뒤, `구 T-N → 새 task-N` 매핑을 세워 의존과 상태를
   `backlog task edit` 로 건다.

   - 의존: `backlog task edit <새id> --dep <새선행id>` (구 T-N 의존을 새 ID 로 치환). 선행이 완료
     `[x]` 였으면 그 의존은 이미 충족이므로 생략한다.
   - `[→]` → `backlog task edit <id> -s "In Progress"`.
   - `[!]` → `backlog task edit <id> -s Blocked --notes "<원 BLOCKED 사유 첫 줄>"`.
   - `[ ]` 는 기본 To Do 이므로 손대지 않는다.

4. 마일스톤이 실제로 쓰였으면 `backlog milestone add "<이름>"` 후 태스크 생성 시 `-m "<이름>"` 로 배정한다.

## 5. 아이디어 이관 → draft

"아이디어 (보류)" 섹션의 `I-N` 마다 draft 를 만든다. 구상을 **손실 없이** 담는다(승격은 `/add-task`
몫이므로 여기서 태스크로 올리지 않는다).

```bash
backlog draft create "<짧은 제목>" \
  -d "<원 I-N 구상 무손실 기록>

PLAN 이관: <오늘 날짜>. 착수 전 상세 인터뷰 필요."
```

## 6. PLAN 아카이브 (삭제하지 않음)

이관을 마친 PLAN 파일은 **지우지 않고** 맨 위에 아카이브 헤더를 붙여 보존한다. 완료 `[x]` 이력과 옮기지
않은 서술이 여기 남는다.

```markdown
> **아카이브 (YYYY-MM-DD)**: 이 파일은 backlog 백엔드로 전환되어 더 이상 갱신하지 않는다.
> 미완료 태스크는 backlog(`backlog/`)로 이관됨 — 조회는 `/next-task`. 아이디어는 draft 로 이관.
> 완료 이력·전환 시 옮기지 않은 서술의 아카이브로만 유지한다.
```

기존 PLAN 본문(완료 항목 포함)은 그대로 둔다. 여러 PLAN 파일이면 각각에 헤더를 붙인다. PLAN 이 이미
"동결/아카이브" 헤더를 갖고 있으면 문구만 위 형식으로 정리하고 중복 추가하지 않는다.

## 7. 보고 (구현 시작하지 않음)

옮긴 것을 요약한다: 생성한 태스크(구 T-N → 새 task-N, 상태), draft(구 I-N), doc/decision, 아카이브한
PLAN 파일. 옮기지 않은 것(완료 `[x]` 이력)이 아카이브 원문에 남아 있음을 밝힌다. **여기서 멈춘다 —
구현은 시작하지 않는다.** 이관된 태스크의 소비는 `/start-task`(순차)·`/parallel-tasks`(병렬) 몫이고,
다음 착수 후보 조회는 `/next-task`, 태스크·아이디어 추가는 `/add-task`·`/add-draft` 임을 안내한다.
