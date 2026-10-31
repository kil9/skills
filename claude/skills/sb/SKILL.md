---
description: /start-backlog 의 짧은 별칭. 사용자가 프롬프트에 `/sb` 를 적었을 때(문장 끝 포함) 부른다. 모델은 스스로 고를 때 이 별칭 대신 본체를 부르는 편이 낫다.
allowed_tools: [Skill]
---

`Skill("start-backlog", args: "$ARGUMENTS")` 를 그대로 호출하고, 그 스킬의 지시를 따른다. 인자가 비었으면 args 없이 호출한다.
