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

**ids** — a workspace id is an opaque token like `wHW`; its tabs and panes are namespaced under it,
`wHW:t1` and `wHW:p2` (kil9 note, verified 2026-08-04 on herdr 0.8.0 — the old positional `1` /
`1:1` / `1-1` shapes are gone). a pane's number is scoped to its workspace, not its tab: `wHW:p2` may
well live in `wHW:t2`. never assemble an id from parts; read whole ids out of responses.

`workspace list` also carries a separate human-facing `number` (`1`, `2`, …) — that is the sidebar
position, **not** an id. passing it where a `workspace_id` is expected fails.

important: ids are for the current live session only. re-read them from `workspace list`, `tab list`,
`pane list`, `pane current`, or create/split responses when you need a current id. do not guess that
an older `wHW:p3` is still the same pane later.

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
does not create panes (kil9 note, re-verified 2026-08-04 on herdr 0.8.0 — the old one-step
`agent start --split --cwd -- claude ...` form no longer exists):

```bash
# 1) make the pane. --current anchors to YOUR pane; --cwd lives here now, not on agent start.
PID=$(herdr pane split --current --direction right --no-focus --cwd /path/to/repo \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"]["pane"]["pane_id"])')

# 2) attach the agent AND hand it the task in the same call — everything after `--` is the
#    agent's own argv, and a positional arg there is claude's initial prompt.
#    no retry loop needed on 0.8.0: agent start blocks until the pane is interactive-ready.
herdr agent start reviewer --kind claude --pane "$PID" \
  -- --model opus --effort medium --dangerously-skip-permissions \
  "review the test coverage in src/api/. write the result to /path/to/repo/scratchpad/reviewer.md"

# 3) wait for any terminal state. bare wait = idle, done, OR blocked.
herdr agent wait reviewer --timeout 600000
cat /path/to/repo/scratchpad/reviewer.md      # retrieve via file, not pane read
```

**do not open with `agent wait --until working` on 0.8.0.** `agent start` now returns only once the
pane is interactive-ready (`interactive_ready: true` in its response), which takes long enough that a
short task can already be *finished* by the time it returns — the working transition then never
arrives and the wait burns its whole timeout (measured 2026-08-04: a full 60s on a task that had
already written its output file). the old race it guarded against — a terminal-state wait matching
the *previous* state — is real but only for prompts you submit yourself into an already-live agent
(step 2 doesn't have it, since the agent was not in a terminal state before you attached it). when
you do need that guard, give it a short timeout and ignore its failure:

```bash
herdr agent wait reviewer --until working --timeout 10000 || true
herdr agent wait reviewer --timeout 600000
```

**hand the first task over in argv, not as a separate submit step.** typing it in afterwards is where
this recipe breaks: neither `pane run` nor `agent prompt` reliably submits into a claude pane — the
text just sits at the `❯` prompt with the agent idle, and one `pane send-keys <id> Enter` then runs it
immediately. **this is not limited to the moment right after `agent start`**; re-measured 2026-08-04
on 0.8.0, a `pane run` sent to an agent that had *already completed a turn* also left its text
unsubmitted (the earlier "works fine once the agent has completed a turn" note was wrong). so: opening
prompt in argv, and for every follow-up, `pane run` (or `pane send-text`) then verify with
`pane read --source visible` and send Enter yourself if the text is still sitting there.

nine non-obvious traps (each burns a fresh session if you skip it). the six about spawning, waiting,
and submitting were re-verified 2026-08-04 against herdr 0.8.0 by actually spawning a worker; the last
three (permissions, result retrieval, folder trust) were not re-run and carry over from 0.7.5:

- **anchor with `--current`, not `$HERDR_PANE_ID`.** the `HERDR_*` env vars are captured at pane start and go **stale** when the pane is later moved — a real session had `HERDR_WORKSPACE_ID=wAJ` while it was actually sitting in `wAQ`, and every spawn using it failed. `--current` asks the server where you are right now. (herdr also reassigns pane/workspace ids as panes open and close, so never cache them across steps.)
- **`agent start` needs `--kind` and an existing pane.** signature is `agent start <NAME> --kind <KIND> --pane <ID> [-- AGENT_ARGV...]`. `--workspace`, `--tab`, `--split`, `--no-focus`, and `--cwd` are all gone from it; the canonical executable comes from `--kind` (`claude`, `codex`, `agy`, …), so `-- claude ...` becomes `-- <claude's own flags>`.
- **`agent start` right after `pane split` no longer needs a retry loop** — it waits for interactive readiness itself (`--timeout <MS>`, default 30000, max 300000) and answers with `interactive_ready: true`. this reverses the 0.7.5 advice to retry the identical command, and it is *why* the working-wait above now backfires. if it does fail, it is a real failure — retrying blind just re-burns the readiness timeout.
- **`agent prompt` does not press Enter.** it types the text into the input box and leaves it there — the same trap the old `agent send` had, under a new name. its `--wait` then fails with `agent_prompt_stalled` ("no observed state change... state_change_seq remained N"), which reads like the agent hung when nothing was ever submitted. `pane run` is no better (see above) — check and send Enter yourself.
- **never wait on `--until idle`.** a finished pane you have not looked at reports `done`, not `idle`, so an idle wait runs to the timeout (measured: a full 300s while the task had finished in 19s). the bare `agent wait <name> --timeout <MS>` matches idle, done, **and** blocked — which also means a permission prompt wakes you instead of hanging. `--status` is spelled `--until` now. (`done` for an unfocused worker re-confirmed on 0.8.0; note a pane can also settle straight to `idle`, which is exactly why the bare wait is the only safe form.)
- **`agent wait --until working` is a trap on the spawn path.** see the recipe above: `agent start` returns interactive-ready, by which point a short task may already be done, and the transition never comes. keep it only for prompts submitted into a live agent, with a short timeout and `|| true`.
- **unattended runs need `--dangerously-skip-permissions`.** a spawned claude starts in the default interactive permission mode and goes `blocked` (see `pane list` status) on the very first tool call, waiting on a "Do you want to proceed?" prompt. an already-blocked pane can be approved with `herdr pane send-keys <id> Enter` (default highlight is "1. Yes"), but every new command re-prompts, so spawn with skip from the start.
- **retrieve the result via a file, not `pane read`.** claude's TUI collapses its final answer, so `pane read --source recent/visible/recent-unwrapped` often returns nothing usable. put "write the result to <repo>/scratchpad/<name>.md" in the task and `cat` that file. reserve `pane read` for progress checks. note also that claude may render a *suggested* follow-up in the input box, so text sitting at the `❯` prompt is not proof that your own input landed.
- **a fresh cwd triggers claude's folder-trust prompt.** on the first run in a directory claude has never seen, an "Is this a project you trust?" prompt appears before the task starts — `--dangerously-skip-permissions` does NOT bypass it, and herdr detects the pane as **idle** (not blocked), so the working-wait times out. confirm with `pane read --source visible`, then approve with `herdr pane send-keys <id> Enter` (default highlight is "1. Yes, I trust this folder"). already-trusted directories (existing repos) don't prompt.

`--cwd` on the split is required in practice: without it the new pane inherits the herdr server's cwd (usually `~`), not your repo. `pane split --env KEY=VALUE` sets env for the launched shell — use it to forward `CLAUDE_CONFIG_DIR` when you run under a ccs profile.

this path is also the only place you control **effort**: `--effort <level>` in the agent's argv works and is visible in the spawned pane's banner (`Opus 5 with medium effort`). pick the level per the effort policy in the global rules — the Agent-tool path has no effort knob at all.

**what a pane actually costs** (kil9 note, measured 2026-07-25 on herdr 0.7.5 with Opus 5, same trivial task; the earlier numbers were Haiku on 2026-07-12). startup + one turn is ~6s (split 0.06s + `agent start` 3.2s + first response 2.7s), on par with the old ~7s. the prefix (first-turn `cache_write`) is 67k for a pane (two samples: 66,684 / 66,763) vs 50k for an Agent-tool subagent — 1.3x, same order of magnitude. so the real cost of a pane is not tokens but the **completion-detection round trip and orchestration chores**, a constant per task. a fork reuses the leader's prefix cache, so anything a fork can do is always cheapest that way.

**a pane sometimes pays the prefix twice.** in one of those two samples the second turn came back with `cache_read=0` and regenerated the prefix, putting total `cache_write` at 134k against 68k for the healthy sample. the Agent-tool path never did this. it is probabilistic — one measurement will not show it — and when it hits, the pane costs double.

## command groups this skill does not cover

these exist on 0.8.0 and are not described anywhere above — reach for `herdr <group> --help` before
assuming a capability is missing:

- `herdr worktree list|create|open|remove` — git worktree-backed workspaces, first-class. relevant to any parallel-worker flow that would otherwise hand-roll `git worktree add`.
- `herdr integration install|uninstall|status` — built-in per-agent integrations (this is what an opencode pane needs before its history is readable).
- `herdr api snapshot|schema` — the whole live session as one json document, and the bundled socket-api schema. `api snapshot` is usually cheaper than several `list` calls.
- `herdr agent explain` — why herdr detected (or failed to detect) an agent in a pane. the first thing to run when a spawn "worked" but no agent shows up.
- `herdr pane neighbor|edges|layout|zoom|swap|process-info` — geometry and layout queries, plus what is actually running in a pane.
- `herdr session`, `herdr notification show`, `herdr config`, `herdr channel`.

## further reading

- recipes for the other branches — run a server, run tests, watch or coordinate with another pane: [`references/recipes.md`](references/recipes.md)
- spawning an `agy` agent instead of claude: [`references/agy-spawn.md`](references/agy-spawn.md)
- which commands print json vs text, and where ids live in the response: [`references/output-shapes.md`](references/output-shapes.md)
- full command reference: [`references/commands.md`](references/commands.md)
