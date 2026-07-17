---
name: kill-agents
description: Claude Code 고아 teammate(서브에이전트) 잔재를 한 방에 정리한다. /clear·재시작 후에도 tmux pane 에 남은 pp-*@session-* 프로세스·pane, 그리고 팀 로스터(config.json)에 박제돼 UI 에 계속 뜨는 죽은 멤버를 모두 제거한다. "고아 에이전트 정리 / 팀원이 안 없어짐 / kill agents / killagents" 요청 시 사용.
---


Claude Code 팀(parallel-plan 등)으로 띄운 teammate 의 **잔재를 모두 정리**한다. 부모 세션을
`/clear`·재시작으로 끝낸 뒤에도 팀원이 사라지지 않을 때 호출한다.

추가 지시가 있으면 힌트로 사용한다: `$ARGUMENTS`

---

## 0. 잔재의 두 종류 (왜 안 없어지나)

`/clear` 는 **대화만** 비운다. 아래 둘은 별개 레이어라 따로 정리해야 한다:

1. **살아있는 프로세스/pane** — split-pane teammate(`pp-*@session-*`)가 부모 종료 후에도
   tmux pane 에 고아로 남아 백그라운드에서 토큰·리소스를 계속 먹는다. UI "닫기"로 안 잡힌다.
2. **로스터 상태 잔재** — 작업을 끝내 프로세스는 죽었는데 팀 config(`teams/*/config.json`)의
   `members` 배열에 `isActive:false` 로 **박제**돼, UI 로스터에 `○pp-NNN` 으로 계속 뜬다.
   살아있는 프로세스가 아니라 **상태 파일 잔재**라, 프로세스 정리만으로는 안 사라진다.

정리 스크립트(`kill-orphan-agents.sh`)가 **둘 다** 처리한다.

## 1. 정리 실행 (한 방)

```
~/work/kil9quant 또는 어디서든:
~/kil9conf/script/kill-orphan-agents.sh
```

> ⚠ 셸 alias `killagents` 는 **비대화형 run_command 툴 PATH 에 없다**(`command not found`).
> 반드시 **풀패스**로 실행한다: `~/kil9conf/script/kill-orphan-agents.sh`.
> (스크립트가 없으면 §3 수동 폴백.)

스크립트가 순서대로 수행하는 일:
1. `--agent-id ...@session-` teammate 프로세스 식별 (메인 claude 는 `--agent-id` 없어 안전).
2. 그 프로세스를 pane_pid 로 가진 **tmux pane 닫기**(현재 pane·일반 셸 pane 은 절대 제외).
3. pane 없이 남은 프로세스 TERM → 안 죽으면 KILL.
4. **로스터 정리**: `teams/*/config.json` 에서 pane 이 실제로 사라졌고 비활성인 tmux 멤버만
   `members` 에서 빼고 `inboxes/<name>.json` 도 삭제. team-lead·in-process·pane 생존·isActive
   멤버는 보존. (tmux 미가동 시 pane 검증 불가라 안전하게 건너뜀.)

## 2. 결과 보고

스크립트 stdout 을 요약한다(종료한 프로세스/pane, 로스터에서 제거한 멤버, 없으면 "정리할 잔재 없음"). TUI 로스터가 즉시 갱신 안 되면 한 번 더 `/clear` 하거나 세션을 재시작하면 반영된다고 안내한다.

## 3. 수동 폴백 (스크립트가 없을 때만)

스크립트가 없거나 실패하면 직접 점검한다 — **현재 pane·메인 claude 는 절대 건드리지 않는다**:

- 살아있는 teammate 프로세스 확인:
  `ps -axo pid,etime,command | grep -- '--agent-id [^ ]*@session-' | grep -v grep`
- 그 PID 를 pane_pid 로 가진 pane 만 닫기:
  `tmux list-panes -a -F '#{pane_id} #{pane_pid}'` 로 매칭 후 `tmux kill-pane -t <pane>`.
- 로스터 잔재: `~/.ccs/instances/*/teams/*/config.json` 의 `members` 에서 pane 이 사라진
  `backendType:"tmux"`·`isActive:false` 멤버만 제거하고 `inboxes/<name>.json` 도 삭제.
  (편집 전 `config.json` 을 백업하고, team-lead·산 멤버는 반드시 보존.)

## 금지 사항

- 현재 pane·메인 claude 프로세스·사용자의 일반 셸 pane 은 절대 종료하지 않는다.
- `isActive:true` 이거나 pane 이 살아있는 멤버는 로스터에서 지우지 않는다(스폰 중일 수 있음).
- tmux 가 안 떠 있으면 pane 검증이 불가하므로 로스터 정리를 강행하지 않는다.
