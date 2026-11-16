---
name: herdr-sidepanel
description: Chrome 사이드패널에서 지금 보는 페이지를 그 페이지를 만든 Herdr 세션(claude)에 묻는 확장 herdr-sidepanel 을 설치·사용·고장 대응한다. "사이드패널 깔아줘 / 브라우저에서 Herdr 세션에 묻고 싶어 / 사이드패널이 답을 안 준다 / native host 오류" 라고 할 때, 또는 Herdr 세션에 `[브라우저 사이드패널에서 온 질문]` 이 들어와 그 경로를 알아야 할 때.
---

코드와 정본 문서는 저장소 `kil9/herdr-sidepanel`(github.com, private, 클론 위치 관례 `~/work/kil9/herdr-sidepanel`)에
있다. 이 스킬은 그 저장소로 가는 길과, 문서만 보고는 놓치기 쉬운 것만 담는다.

| 알고 싶은 것 | 정본 |
|---|---|
| 설치·확장 로드·쓰는 법·문제 대응 표·시험 | 저장소 `README.md` |
| 설계·확정 사항·session id 매핑 방법과 그 근거 | `backlog/docs/doc-1` |
| 확장 ↔ host 메시지 | `README.md` '메시지 프로토콜' |

## 설치

1. 클론이 없으면 `gh repo clone kil9/herdr-sidepanel ~/work/kil9/herdr-sidepanel`. 있으면 pull.
2. README '설치(Windows)' 를 따른다 — 스크립트 한 번(`install\install-windows.ps1`)과 Chrome 의 '압축해제된 확장
   프로그램 로드'. 확장 로드는 Chrome UI 조작이라 사용자 몫이다: 폴더 경로를 알려 주고 끝낸다.

완료: `reg query "HKCU\Software\Google\Chrome\NativeMessagingHosts\dev.kil9.herdr_sidepanel"` 가 manifest 경로를 보이고,
`python host\nm_client.py '{"type":"list"}'` 가 세션 목록을 돌려준다.

## 고장 대응

README '문제가 생겼을 때' 표의 증상부터 찾는다. 확장 없이 경로를 끊어서 보는 순서:

1. `python host\nm_client.py '{"type":"ping"}'` — host 가 뜨는가(`%LOCALAPPDATA%\herdr-sidepanel\host.log`).
2. `python host\ask.py <hc 주소> "테스트"` — hc 전송과 jsonl 회수가 되는가.
3. 그래도 안 되면 doc-1 '미해결 → 확정' 의 매핑(`/proc/<claude pid>/fd` 의 `/tmp/claude-<uid>/<project>/<session-id>/`)을
   그 머신에서 손으로 확인한다.

## 놓치기 쉬운 것

- **'복제해서 묻기' 세션은 `ca`(`start_claude auto`)로 뜬다.** 쿼터 넉넉한 ccs 프로필을 고르고
  `--dangerously-skip-permissions` 로 떠서 Q&A 중 바로 고칠 수 있다(2026-11-16, 읽기 전용이던 것을 바꿈). 원래 세션과
  같은 작업 트리를 쓰므로 거기서 고친 것은 원래 세션의 작업과 섞인다 — 커밋 전에 `git status` 로 본다.
- Git Bash 에서 `hc run ... -- /usr/bin/zsh` 처럼 원격 절대경로를 넘기면 `C:/Program Files/Git/usr/bin/zsh` 로 바뀐다.
  셸에서 손으로 재현할 때는 `MSYS_NO_PATHCONV=1` 을 붙인다. 원격 spawn 은 PATH 가 없어 셸도 절대경로로 준다.
- 확장 ID 는 manifest 의 `key` 로 고정돼 있다. `key` 를 지우거나 다른 사본을 로드하면 ID 가 바뀌어 host 가
  `forbidden` 으로 거절한다.
- Herdr 세션 쪽에서 보면 질문은 `[브라우저 사이드패널에서 온 질문 …]` 머리말(제목·URL·선택·보이는 본문)과 함께 온다.
  URL 의 해시가 사용자가 지금 보는 위치다(슬라이드 덱이면 장 번호).
