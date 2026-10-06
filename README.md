# kil9/skills

개인용 에이전트 스킬 모음. Claude Code 만 대상으로 한다.

## 구조

```
claude/skills/<skill>/   # SKILL.md + 부속 스크립트 실체
claude/agents/<name>.md  # Claude Code 서브에이전트 정의
```

- **gemini(Antigravity) 미러는 두지 않는다.** 2026-07-20 에 갱신을 멈췄고(Antigravity 를 거의 안 써서 스킬마다 세 번째 사본을 다시 쓰는 토큰이 값을 못 했다), 2026-07-23 에 실물 `gemini/skills/`(+ 소비용 `.agents/skills` 심링크)를 지웠다. 남겨 둔 stale 사본이 스킬 이름을 바꾸거나 본문을 고칠 때마다 "이것도 같이 고쳐야 하나" 를 되묻게 만드는 값이 유지 비용의 전부였기 때문이다. 다시 쓰기로 하면 **claude 원본에서 새로 굽는다** — 옛 사본을 되살리지 말 것(지운 시점에 이미 loop-task·next-task 시절 이름이었다). 원문은 git history 에 있고, 치환 규칙은 참고용으로 남긴다: →`ask_question`, `invoke_subagent`, `view_file` 등.
- **codex 미러는 두지 않는다.** 2026-10-06 에 `codex/skills/`·`codex/agents/` 를 지웠다 — 당분간 codex 를 안 쓰고, 스킬을 고칠 때마다 사본을 맞추는 비용이 값을 못 했다. codex 를 다시 쓸 때 삭제 커밋 직전 이력에서 한 번에 재정비한다. 그때까지 스킬을 고칠 때 codex 쪽은 신경 쓰지 않는다. codex 전용이던 `sol-advisor`·`lunamax-threads`·`opus-threads` 도 함께 사라졌다.

## 설치

에이전트별 스킬 디렉터리에 개별 스킬을 심링크한다. 예:

```bash
git clone https://github.com/kil9/skills.git ~/work/skills
for s in ~/work/skills/claude/skills/*/; do
  ln -sfn "$s" ~/.claude/skills/"$(basename "$s")"
done
```

## 스킬 개요

| 분류 | 스킬 |
|---|---|
| backlog 워크플로 | add-backlog, ask-backlog, cleanup-backlog, init-backlog, migrate-to-backlog, next-backlog, start-backlog |
| git 워크플로 | commit, cip, cipd, sync |
| 에이전트 메타 | fable-advisor, grill, handoff, learn, skill-creator, zip-it |
| 에이전트 운용 | afk, herdr, kill-agents, shoot-and-forget |
| 저장소·퍼블리시 유틸 | init-project, paste-image, publish-til, kil9-writing-style, explain-diff, show-me (upstream humanlayer/skills, MIT, 원문 그대로) |
| 디자인 | impeccable (upstream 4.0.4, 명시 호출 전용, 내장 이미지 생성만 사용), design-loop (수상작 기준 채점·개선 반복, 고치는 손은 impeccable) |
| 개인 워크플로 | manage-gmail-inbox |

각 스킬의 동작·호출법은 해당 디렉터리의 `SKILL.md` 가 정본이다.

서브에이전트: `claude/agents/*.md` 에 review-cleancode, review-logic,
review-performance, review-security 4종을 둔다.

## 라이선스

[MIT](LICENSE)
