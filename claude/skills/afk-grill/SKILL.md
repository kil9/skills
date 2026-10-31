---
description: /afk grill 의 짧은 별칭 — 떠나기 전에 물을 것을 모아 한 번에 묻는 출문 점검 모드. 사용자가 프롬프트에 `/afk-grill` 을 적었을 때(문장 끝 포함) 부른다. 모델은 스스로 고를 때 이 별칭 대신 본체 afk 를 grill 인자로 부르는 편이 낫다.
allowed_tools: [Skill]
---

`Skill("afk", args: "grill $ARGUMENTS")` 를 그대로 호출하고, 그 스킬의 지시를 따른다. 인자가 비었으면 args 를 `grill` 로 호출한다.
