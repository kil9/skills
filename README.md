# kil9/skills

개인용 에이전트 스킬 모음. Claude Code 를 원본으로 하고 Codex 미러를 함께 관리한다.

## 구조

```
claude/skills/<skill>/   # 원본 (SKILL.md + 부속 스크립트 실체)
claude/agents/<name>.md  # Claude Code 서브에이전트 정의 (claude 전용, 미러 없음)
codex/skills/<skill>/    # 미러 (SKILL.md + agents/openai.yaml, 스크립트는 상대 심링크)
```

- 미러는 claude 본문에 **도구명 치환만** 얹은 사본이다. 독자 재작성·확장은 금지 — 드리프트가 보이면 claude 원본 기준으로 재생성한다. 새 범용 스킬은 claude·codex 를 함께 맞춘다.
  - codex: `AskUserQuestion`→`request_user_input`, `` `/스킬` ``→`` `$스킬` ``, 서브에이전트→worker agent(+`tool_search` 노출).
  - **gemini(Antigravity) 미러는 두지 않는다.** 2026-07-20 에 갱신을 멈췄고(Antigravity 를 거의 안 써서 스킬마다 세 번째 사본을 다시 쓰는 토큰이 값을 못 했다), 2026-07-23 에 실물 `gemini/skills/`(+ 소비용 `.agents/skills` 심링크)를 지웠다. 남겨 둔 stale 사본이 스킬 이름을 바꾸거나 본문을 고칠 때마다 "이것도 같이 고쳐야 하나" 를 되묻게 만드는 값이 유지 비용의 전부였기 때문이다. 다시 쓰기로 하면 **claude 원본에서 새로 굽는다** — 옛 사본을 되살리지 말 것(지운 시점에 이미 loop-task·next-task 시절 이름이었다). 원문은 git history 에 있고, 치환 규칙은 참고용으로 남긴다: →`ask_question`, `invoke_subagent`, `view_file` 등.
  - backlog 스킬군(init-backlog, add-task, add-milestone, add-draft, next-backlog, start-backlog, parallel-tasks, migrate-to-backlog, cleanup-tasks, loop-backlog 등)은 CLI(backlog) 기반이라 backlog CLI 명령 블록은 두 에이전트 공통 무치환이고, 치환은 인터뷰 도구명·스킬 참조 표기·워커 오케스트레이션 문단 정도다.
- 부속 스크립트(`.sh` 뿐 아니라 `GLOSSARY.md` 같은 부속 문서도)는 claude 원본에만 실체를 두고 미러에는 상대 심링크를 둔다(드리프트 원천 차단).
- **fable-advisor 는 claude 전용(미러 없음).** 이 스킬의 본질이 Claude 의 Fable 5 모델을 자문역 서브에이전트로 띄우는 것인데 Codex CLI 엔 Fable 이 없어 대응물이 없다. 퇴화 미러(기본 모델 2차 의견)는 값이 유지비를 못 해 두지 않는다 — claude/agents 와 같은 부류다.
- **에이전트에 대응물이 없어 보이는 개념**은 치환이 아니라 판단이 필요하다. 3단으로 가른다.
  1. **기계적 치환**(항상): 도구명·호출 표기·frontmatter 축소.
  2. **대응물 매핑**(허용 — `AskUserQuestion`→`request_user_input` 선례와 같은 부류): 문장 구조·단계·완료 기준은 그대로 두고 명사만 바꾼다. 판별법은 *치환 후 diff 가 명사 교체뿐인가* — 문장을 새로 지으면 규칙 밖이다. 예: learn 의 auto-memory→`~/.codex/AGENTS.local.md`, 글로벌 `~/.claude/CLAUDE.md`→`~/.codex/AGENTS.md`. publish-til §2-2 처럼 **능력 결핍에서 온 순수 호출 경로**도 여기 든다(claude 는 래스터를 못 만들어 codex 에 위임하는데, codex 미러는 자기 `image_generation` 을 직접 쓴다 — 래퍼만 벗기고 프롬프트 사양은 무변경).
  3. **대응물 없음**: 그 개념이 *실행 에이전트의 행위*가 아니라 **작성 대상 산출물(스킬)의 내용**이면 **무치환 유지**한다. skill-creator 본문의 `disable-model-invocation` 논의가 그렇다 — 이 repo 의 스킬 원본은 Claude 포맷이라, codex 가 스킬을 편집할 때도 배워야 할 것은 Claude frontmatter 그 자체다. 치환하면 오히려 오답이 된다. 실행 행위인데 개념이 없을 때만 괄호 한 줄 보정을 얹고, 문장 삭제는 그 줄이 오동작을 유발할 때로 한정한다.

## 설치

에이전트별 스킬 디렉터리에 개별 스킬을 심링크한다. 예:

```bash
git clone https://github.com/kil9/skills.git ~/work/skills
for s in ~/work/skills/claude/skills/*/; do
  ln -sfn "$s" ~/.claude/skills/"$(basename "$s")"
done
```

Codex 는 `~/.codex/skills/` 를 읽는다.

## 스킬 개요

| 분류 | 스킬 |
|---|---|
| backlog·플랜 워크플로 | add-draft, add-milestone, add-task, cleanup-tasks, init-backlog, loop-backlog, loop-plan, make-a-plan, migrate-to-backlog, next-backlog, parallel-tasks, start-backlog |
| git 워크플로 | commit, cip, cipd, sync |
| 에이전트 메타 | fable-advisor, grill, handoff, learn, skill-creator, zip-it |
| 에이전트 운용 | herdr, kill-agents, shoot-and-forget |
| 저장소·퍼블리시 유틸 | init-project, goversion-to-gomod, scan-bugs, paste-image, publish-til, kil9-writing-style, explain-diff |
| 개인 워크플로 | manage-gmail-inbox |

각 스킬의 동작·호출법은 해당 디렉터리의 `SKILL.md` 가 정본이다.

서브에이전트(`claude/agents/`): review-cleancode, review-logic, review-performance, review-security — scan-bugs 등 리뷰 스킬이 병렬로 띄우는 diff 리뷰 4종.

## 라이선스

[MIT](LICENSE)
