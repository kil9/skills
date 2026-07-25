---
name: herdr
description: Control herdr from inside it: workspaces, tabs, panes, spawning agents, reading output, waiting on state. Use when running inside herdr (HERDR_ENV=1).
---

# herdr — agent skill

before using this skill, check that `HERDR_ENV=1`. if it is not set to `1`, say you are not running inside a herdr-managed pane and stop. do not inspect or control the focused herdr pane from outside herdr.

you are running inside herdr, a terminal-native agent multiplexer. herdr gives you workspaces, tabs, and panes — each pane is a real terminal with its own shell, agent, server, or log stream — and you can control all of it from the cli.

this means you can:

- see what other panes and agents are doing
- create tabs for separate subcontexts inside one workspace
- split panes and run commands in them
- start servers, watch logs, and run tests in sibling panes
- wait for specific output before continuing
- wait for another agent to finish
- spawn more agent instances

the `herdr` binary is available in your PATH. its workspace, tab, pane, and wait commands talk to the running herdr instance over a local unix socket.

if you need the raw protocol or full api reference, read the [socket api docs](https://herdr.dev/docs/socket-api/).

## concepts

**workspaces** are project contexts. each workspace has one or more tabs. unless manually renamed, a workspace's label follows the first tab's root pane — usually the repo name, otherwise the root pane's current folder name.

**tabs** are subcontexts inside a workspace. each tab has one or more panes.

**panes** are terminal splits inside a tab. each pane runs its own process — a shell, an agent, a server, anything.

**agent status** is detected automatically by herdr. the api exposes one public field for it:

- `agent_status` — `idle`, `working`, `blocked`, `done`, `unknown`

`done` means the agent finished, but you have not looked at that finished pane yet.

plain shells still exist as panes, but herdr's sidebar agent section intentionally focuses on detected agents rather than listing every shell.

**ids** — workspace ids look like `1`, `2`. tab ids look like `1:1`, `1:2`, `2:1`. pane ids look like `1-1`, `1-2`, `2-1`. these are compact public ids for the current live session.

important: ids can compact when tabs, panes, or workspaces are closed. do not treat them as durable ids. re-read ids from `workspace list`, `tab list`, `pane list`, or create/split responses when you need a current id. do not guess that an older `1-3` is still the same pane later.

## discover yourself

see what panes exist and which one is focused:

```bash
herdr pane list
```

the focused pane is yours. other panes are your neighbors.

list workspaces:

```bash
herdr workspace list
```

## command reference

crud syntax for tabs, panes, workspaces, and waits lives in
**[`references/commands.md`](references/commands.md)** — read it when you need a command shape.
`herdr <subcommand> --help` is authoritative if it drifts. the sections below are what you cannot
look up: recipes that compose these commands, and traps learned by failing.

## recipes

### spawn a new agent and give it a task

spawning takes **three** commands: make the pane, attach the agent with its task, wait. `agent start`
does not create panes (kil9 note, re-verified 2026-07-25 on herdr 0.7.5 — the old one-step
`agent start --split --cwd -- claude ...` form no longer exists):

```bash
# 1) make the pane. --current anchors to YOUR pane; --cwd lives here now, not on agent start.
PID=$(herdr pane split --current --direction right --no-focus --cwd /path/to/repo \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"]["pane"]["pane_id"])')

# 2) attach the agent AND hand it the task in the same call — everything after `--` is the
#    agent's own argv, and a positional arg there is claude's initial prompt.
#    retry: this fails fast if the new pane has not reached its shell prompt yet.
for i in 1 2 3; do
  herdr agent start reviewer --kind claude --pane "$PID" \
    -- --model opus --effort medium --dangerously-skip-permissions \
    "review the test coverage in src/api/. write the result to /path/to/repo/scratchpad/reviewer.md" \
    && break
done

# 3) catch the working transition, then wait for any terminal state.
herdr agent wait reviewer --until working --timeout 60000
herdr agent wait reviewer --timeout 600000    # no --until: matches idle, done, OR blocked
cat /path/to/repo/scratchpad/reviewer.md      # retrieve via file, not pane read
```

**hand the first task over in argv, not as a separate submit step.** typing it in afterwards is where
this recipe breaks: `pane run` normally types *and* presses Enter, but right after `agent start` the
Enter is swallowed and the text just sits at the `❯` prompt with the agent idle forever (observed
2026-07-25 — the working-wait burned its full 60s, and one `agent send-keys <name> Enter` then ran the
task immediately). the same `pane run` works fine once the agent has completed a turn, so use it for
follow-ups and coaching, not for the opening prompt. if you must type the first prompt in, verify with
`pane read --source visible` and send Enter yourself when the text is still sitting there.

nine non-obvious traps (each burns a fresh session if you skip it). the first six were re-verified
2026-07-25 against herdr 0.7.5 by actually spawning workers; the rest carry over from 2026-07:

- **anchor with `--current`, not `$HERDR_PANE_ID`.** the `HERDR_*` env vars are captured at pane start and go **stale** when the pane is later moved — a real session had `HERDR_WORKSPACE_ID=wAJ` while it was actually sitting in `wAQ`, and every spawn using it failed. `--current` asks the server where you are right now. (herdr also reassigns pane/workspace ids as panes open and close, so never cache them across steps.)
- **`agent start` needs `--kind` and an existing pane.** signature is `agent start <NAME> --kind <KIND> --pane <ID> [-- AGENT_ARGV...]`. `--workspace`, `--tab`, `--split`, `--no-focus`, and `--cwd` are all gone from it; the canonical executable comes from `--kind` (`claude`, `codex`, `agy`, …), so `-- claude ...` becomes `-- <claude's own flags>`.
- **`agent start` immediately after `pane split` can fail.** the new pane must already be at an interactive shell prompt; if it isn't, the call errors out in milliseconds instead of waiting, and the next command reports `agent_not_found`. **retry the identical command** — it succeeds on the next attempt. don't try to gate on the prompt with `pane wait-output --match '$ '`: that assumes a prompt shape, and it timed out against a themed zsh prompt that has no `$ ` in it.
- **`agent prompt` does not press Enter.** it types the text into the input box and leaves it there — the same trap the old `agent send` had, under a new name. its `--wait` then fails with `agent_prompt_stalled` ("no observed state change... state_change_seq remained N"), which reads like the agent hung when nothing was ever submitted. use `pane run <pane_id> "<text>"` for follow-ups (it submits), and put the *first* prompt in argv per the note above.
- **never wait on `--until idle`.** a finished pane you have not looked at reports `done`, not `idle`, so an idle wait runs to the timeout (measured: a full 300s while the task had finished in 19s). the bare `agent wait <name> --timeout <MS>` matches idle, done, **and** blocked — which also means a permission prompt wakes you instead of hanging. `--status` is spelled `--until` now.
- **waiting right after submitting can match the *previous* state.** the agent is still `idle`/`done` for a moment, so a terminal-state wait returns in ~10ms having matched nothing new. wait `--until working` first, then wait for the terminal state.
- **unattended runs need `--dangerously-skip-permissions`.** a spawned claude starts in the default interactive permission mode and goes `blocked` (see `pane list` status) on the very first tool call, waiting on a "Do you want to proceed?" prompt. an already-blocked pane can be approved with `herdr pane send-keys <id> Enter` (default highlight is "1. Yes"), but every new command re-prompts, so spawn with skip from the start.
- **retrieve the result via a file, not `pane read`.** claude's TUI collapses its final answer, so `pane read --source recent/visible/recent-unwrapped` often returns nothing usable. put "write the result to <repo>/scratchpad/<name>.md" in the task and `cat` that file. reserve `pane read` for progress checks. note also that claude may render a *suggested* follow-up in the input box, so text sitting at the `❯` prompt is not proof that your own input landed.
- **a fresh cwd triggers claude's folder-trust prompt.** on the first run in a directory claude has never seen, an "Is this a project you trust?" prompt appears before the task starts — `--dangerously-skip-permissions` does NOT bypass it, and herdr detects the pane as **idle** (not blocked), so the working-wait times out. confirm with `pane read --source visible`, then approve with `herdr pane send-keys <id> Enter` (default highlight is "1. Yes, I trust this folder"). already-trusted directories (existing repos) don't prompt.

`--cwd` on the split is required in practice: without it the new pane inherits the herdr server's cwd (usually `~`), not your repo. `pane split --env KEY=VALUE` sets env for the launched shell — use it to forward `CLAUDE_CONFIG_DIR` when you run under a ccs profile.

this path is also the only place you control **effort**: `--effort <level>` in the agent's argv works and is visible in the spawned pane's banner (`Opus 5 with medium effort`). pick the level per the effort policy in the global rules — the Agent-tool path has no effort knob at all.

**what a pane actually costs** (kil9 note, measured 2026-07-25 on herdr 0.7.5 with Opus 5, same trivial task; the earlier numbers were Haiku on 2026-07-12). startup + one turn is ~6s (split 0.06s + `agent start` 3.2s + first response 2.7s), on par with the old ~7s. the prefix (first-turn `cache_write`) is 67k for a pane (two samples: 66,684 / 66,763) vs 50k for an Agent-tool subagent — 1.3x, same order of magnitude. so the real cost of a pane is not tokens but the **completion-detection round trip and orchestration chores**, a constant per task. a fork reuses the leader's prefix cache, so anything a fork can do is always cheapest that way.

**a pane sometimes pays the prefix twice.** in one of those two samples the second turn came back with `cache_read=0` and regenerated the prefix, putting total `cache_write` at 134k against 68k for the healthy sample. the Agent-tool path never did this. it is probabilistic — one measurement will not show it — and when it hits, the pane costs double.

## further reading

- recipes for the other branches — run a server, run tests, watch or coordinate with another pane: [`references/recipes.md`](references/recipes.md)
- spawning an `agy` agent instead of claude: [`references/agy-spawn.md`](references/agy-spawn.md)
- which commands print json vs text, and where ids live in the response: [`references/output-shapes.md`](references/output-shapes.md)
- full command reference: [`references/commands.md`](references/commands.md)
