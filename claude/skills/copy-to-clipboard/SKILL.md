---
name: copy-to-clipboard
description: 명령·텍스트·키를 사용자 로컬 클립보드에 넣는다(SSH·herdr·Herdr 앱 너머, OSC 52). "클립보드에 넣어줘 / 복사해줘 / 키 포함해서 클립보드로" 라고 하거나 `/copy-to-clipboard` 를 적었을 때.
allowed_tools: [Bash]
---

# /copy-to-clipboard

원격 셸의 출력을 사용자가 드래그해 복사하게 하지 않는다 — 줄바꿈·들여쓰기가 깨지고, 시크릿이면
응답에 찍는 순간 대화 기록에 남는다. OSC 52 escape 를 터미널에 보내 터미널이 로컬 클립보드에 넣게 한다.

## 1. 내용 만들기

`$ARGUMENTS` 나 대화에서 넣을 내용을 정한다. 셸 변수 `P` 에 담는다.

- **시크릿(토큰·키·비밀번호)은 출력에 찍지 않는다.** 금고에서 꺼낸 값을 바로 변수에 넣고(`T=$(bw get …)`),
  같은 Bash 호출 안에서 `P` 를 조립해 넘긴다. `echo $T`·`set -x` 금지.
- 명령이면 그대로 붙여 실행할 수 있는 모양으로 만든다(여러 줄이면 `\` 이음).

## 2. 보내기

```bash
printf '%s' "$P" | clip
```

`clip`(kil9conf `rc/bin/clip`)이 PATH 에 있으면 그것을 쓴다. Bash 도구는 controlling tty 가 없지만
`clip` 이 조상 프로세스의 tty 를 찾아 쓴다. 디버그는 `CLIP_DEBUG=1`.

`clip` 이 없으면 같은 일을 직접 한다 — 조상 중 처음 tty 가 잡히는 프로세스에 쓴다:

```bash
pid=$$; while [ "$pid" -gt 1 ]; do t=$(ps -o tty= -p $pid | tr -d ' '); case $t in ''|'?'|'??') ;; *) break;; esac; pid=$(ps -o ppid= -p $pid | tr -d ' '); done
printf '\033]52;c;%s\007' "$(printf '%s' "$P" | base64 | tr -d '\n')" > /dev/$t
```

tmux 안이면 `\033Ptmux;\033…\033\\` 로 감싸야 한다(`clip` 은 알아서 한다).

## 3. 알리기

응답에는 넣은 내용을 보여 주되 시크릿은 앞 몇 글자만 남기고 가린다(`Bearer bca_21…`). 성공 여부는
이쪽에서 알 수 없다 — escape 를 받아 클립보드에 넣는 것은 터미널이고 실패해도 신호가 없다. "붙여넣어
확인해 달라" 를 한 줄 붙인다. 비어 있다고 하면 의심 순서는 (1) 크기(base64 약 75KB 초과 시 잘림)
(2) 터미널의 OSC 52 미지원 — `clip --test` 로 가른다.

메시지방·이슈 등 **밖으로 나갈 글**에 넣을 초안이면 시크릿은 `<api-key>` 같은 자리표시로 두고, 실제 값이
든 것은 클립보드로만 건넨다.
