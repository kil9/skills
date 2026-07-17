# kil9/skills

개인용 에이전트 스킬 모음. Claude Code 를 원본으로 하고 Codex·Gemini(Antigravity) 미러를 함께 관리한다.

## 구조

```
claude/skills/<skill>/   # 원본 (SKILL.md + 부속 스크립트 실체)
codex/skills/<skill>/    # 미러 (SKILL.md + agents/openai.yaml, 스크립트는 상대 심링크)
gemini/skills/<skill>/   # 미러 (SKILL.md 만, 스크립트는 상대 심링크)
.agents/skills           # → gemini/skills (Antigravity 소비용)
```

- 미러는 claude 본문에 도구명 치환만 얹은 사본이다(codex: `AskUserQuestion`→`request_user_input`, `/스킬`→`$스킬` 등). 독자 재작성은 하지 않고, 드리프트가 보이면 claude 원본 기준으로 재생성한다.
- 부속 스크립트는 claude 원본에만 실체를 두고 미러에는 상대 심링크를 둔다.
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

## 라이선스

[MIT](LICENSE)
