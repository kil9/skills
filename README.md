# kil9/skills

개인용 에이전트 스킬 모음. Claude Code 를 원본으로 하고 Codex·Gemini(Antigravity) 미러를 함께 관리한다.

## 구조

```
claude/skills/<skill>/   # 원본 (SKILL.md + 부속 스크립트 실체)
claude/agents/<name>.md  # Claude Code 서브에이전트 정의 (claude 전용, 미러 없음)
codex/skills/<skill>/    # 미러 (SKILL.md + agents/openai.yaml, 스크립트는 상대 심링크)
gemini/skills/<skill>/   # 미러 (SKILL.md 만, 스크립트는 상대 심링크)
.agents/skills           # → gemini/skills (Antigravity 소비용)
```

- 미러는 claude 본문에 **도구명 치환만** 얹은 사본이다. 독자 재작성·확장은 금지 — 드리프트가 보이면 claude 원본 기준으로 재생성한다. 새 범용 스킬은 세 곳을 함께 맞춘다.
  - codex: `AskUserQuestion`→`request_user_input`, `` `/스킬` ``→`` `$스킬` ``, 서브에이전트→worker agent(+`tool_search` 노출).
  - gemini: →`ask_question`, `invoke_subagent`, `view_file` 등.
  - backlog 스킬군(init-backlog, add-task, add-milestone, add-draft, next-task, start-task, parallel-tasks, migrate-to-backlog, cleanup-tasks, loop-task 등)은 CLI(backlog) 기반이라 backlog CLI 명령 블록은 세 에이전트 공통 무치환이고, 치환은 인터뷰 도구명·스킬 참조 표기·워커 오케스트레이션 문단 정도다.
- 부속 스크립트는 claude 원본에만 실체를 두고 미러에는 상대 심링크를 둔다(드리프트 원천 차단).
- 일부 스킬(learn, skill-creator)은 Claude 고유 도구에 의존해 의도적으로 미러하지 않는다.

## 설치

에이전트별 스킬 디렉터리에 개별 스킬을 심링크한다. 예:

```bash
git clone https://github.com/kil9/skills.git ~/work/skills
for s in ~/work/skills/claude/skills/*/; do
  ln -sfn "$s" ~/.claude/skills/"$(basename "$s")"
done
```

Codex 는 `~/.codex/skills/`, Antigravity 는 repo 의 `.agents/skills` 를 그대로 읽는다.

## 스킬 개요

| 분류 | 스킬 |
|---|---|
| backlog·플랜 워크플로 | add-draft, add-milestone, add-task, cleanup-tasks, init-backlog, loop-plan, loop-task, make-a-plan, migrate-to-backlog, next-task, parallel-tasks, start-task |
| git 워크플로 | commit, cip, cipd, sync |
| 에이전트 메타 | grill, handoff, learn, skill-creator, zip-it |
| 에이전트 운용 | herdr, kill-agents, shoot-and-forget |
| 저장소·퍼블리시 유틸 | init-project, goversion-to-gomod, scan-bugs, paste-image, publish-til, kil9-writing-style |

각 스킬의 동작·호출법은 해당 디렉터리의 `SKILL.md` 가 정본이다.

서브에이전트(`claude/agents/`): review-cleancode, review-logic, review-performance, review-security — scan-bugs 등 리뷰 스킬이 병렬로 띄우는 diff 리뷰 4종.

## 라이선스

[MIT](LICENSE)
