# kil9/skills

개인용 에이전트 스킬 모음. Claude Code 만 대상으로 한다.

## 구조

```
claude/skills/<skill>/   # SKILL.md + 부속 스크립트 실체
claude/skills/references/ # 여러 스킬이 함께 쓰는 절차·스크립트(스킬 아님)
claude/agents/<name>.md  # Claude Code 서브에이전트 정의
```

- **두 스킬 이상에 같은 절차를 복사하지 않는다.** 복사본은 한쪽만 고쳐져 어긋난다. 두 번째 사본이 생길 때 `claude/skills/references/` 로 끌어올리고 각 스킬에는 경로만 남긴다(예: `vi-pane.md`). 사내 repo(skills-naver)도 `~/.claude/skills/references/…` 로 가리킨다. 경로가 깨지면 `tests/check-skill-refs.sh` 가 `verify.sh` 에서 잡는다.

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
| backlog 워크플로 | add-backlog, ask-backlog, cleanup-backlog, init-backlog, migrate-to-backlog, next-backlog, start-backlog (짧은 별칭: ab·nb·sb, 사용자 직접 호출 전용) |
| git 워크플로 | commit, cip, cipd, sync |
| 에이전트 메타 | fable-advisor, grill, handoff, review-loop, skill-creator, wrap (세션을 닫기 전 기록, 옛 learn 을 흡수), zip-it |
| 에이전트 운용 | afk (기본은 묻지 않고 진행, `grill`·afk-grill 이면 출문 전에 한 번에 묻기), herdr, kill-agents |
| 저장소·퍼블리시 유틸 | init-project, paste-image, publish-til, explain-diff, show-me (upstream humanlayer/skills, MIT, 원문 그대로) |
| 글쓰기 | kil9-writing-style (kil9 말투), korean-polish (한국어 윤문: daleseo/korean-skills·epoko77-ai/im-not-ai·nomadamas/k-skill 합성, MIT) |
| 디자인 | impeccable (upstream 4.0.4, 명시 호출 전용, 내장 이미지 생성만 사용), design-loop (수상작 기준 채점·개선 반복, 고치는 손은 impeccable), kil9-design-style (kil9 화면 취향의 정본·기록장 — 위 둘이 먼저 읽는다) |
| 개인 워크플로 | manage-gmail-inbox |

각 스킬의 동작·호출법은 해당 디렉터리의 `SKILL.md` 가 정본이다.

서브에이전트: `claude/agents/*.md` 에 review-cleancode, review-logic,
review-performance, review-security 4종을 둔다.

## 라이선스

[MIT](LICENSE)
