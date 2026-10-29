---
name: learn
description: 이번 세션에서 Claude Code 가 배운 것을 스킬·auto-memory·문서 중 맞는 곳에 영속화한다. 미래 세션이 같은 실수를 반복하거나 같은 탐색 비용을 다시 지불하지 않게 하는 것이 목적이다.
allowed_tools: [Bash, Read, Edit, Write, Glob, Grep, AskUserQuestion, Skill]
disable-model-invocation: true
---

# Learn — 이번 세션의 학습을 영속화

**독자는 미래의 Claude Code 세션이다. 사용자가 아니다.**

목적은 하나다: 다음 세션이 **같은 실수를 반복하지 않게**, **같은 탐색 비용을 다시 지불하지 않게** 하는 것. 그래서 결과물은 사람이 읽는 글이 아니라 에이전트가 읽는 지침(스킬·auto-memory·AGENTS.md)이다.

> **`/publish-til` 과 혼동 금지.** 그쪽은 *사용자가* 읽고 배우는 공개 TIL 페이지를 만든다(kil9/til → GitHub Pages). 이 스킬은 *Claude Code 가* 배우는 쪽이며 아무것도 게시하지 않는다. 두 이름은 안 겹치지만 "배운 것"이라는 말이 같아 헷갈릴 수 있다 — 기준은 **"이 글의 독자가 누구인가"** 다. 사용자가 읽을 산문을 쓰고 있다면 스킬을 잘못 고른 것이다.

> **쌓인 것을 정리하는 것은 `/cleanup-memory` 다.** 이 스킬은 새로 배운 것을 *추가*하고, 그쪽은 이미
> 쌓인 것을 감사해 낡은 현재값을 걷어내고 함정을 repo doc 으로 내린다. 세션을 닫기 전에 진행 상태·
> 남은 일까지 함께 남기는 것은 `/wrap` 이다(이 스킬의 범위를 포함한다).

무엇을 남기고 어디에 어떻게 쓰는지는 [`../references/persist-learnings.md`](../references/persist-learnings.md)
가 정본이다.

## 절차

1. 대화를 훑어 후보를 추린다. 없으면 그렇게 보고하고 끝낸다 — 없는데 억지로 만들지 않는다.
2. 각 후보의 목적지를 위 문서의 목적지 표로 정한다.
3. 후보가 여럿이거나 목적지가 애매하면 AskUserQuestion 으로 무엇을 어디에 남길지 확정한다.
4. 확정된 것만 위 문서의 쓰는 법대로 기록한다.
