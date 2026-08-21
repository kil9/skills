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

`idle` and `done` are the **same underlying ready-for-input state**, split by whether the work has been
seen: `done` is that state reached by background work in a tab you have not looked at. what marks it
seen is focusing the tab, or targeting the pane/agent with a *focus* command — **CLI reads do not mark
it seen**, so polling with `agent get` or `pane read` will never turn a `done` into an `idle`. this is
exactly why the bare wait (matching both) is the only safe form.

`blocked` means herdr recognized an approval or question UI. `unknown` means an agent is present but
herdr cannot classify it confidently — it is **not** evidence that the work finished.

plain shells still exist as panes, but herdr's sidebar agent section intentionally focuses on detected agents rather than listing every shell.

**ids** — a workspace id is an opaque handle like `w19`; its tabs and panes are namespaced under it,
`w19:t1` and `w19:p4` (kil9 note, verified 2026-08-21 on herdr 0.8.2 — the old positional `1` /
`1:1` / `1-1` shapes are gone, and the letter-pair shape `wHW` of 0.8.0 is now a number). a pane's
number is scoped to its workspace, not its tab: `w19:p2` may well live in `w19:t2`. never assemble an
id from parts; read whole ids out of responses.

`workspace list` also carries a separate human-facing `number` (`1`, `2`, …) — that is the sidebar
position, **not** an id. passing it where a `workspace_id` is expected fails.

important: ids are for the current live session only. re-read them from `workspace list`, `tab list`,
`pane list`, `pane current`, or create/split responses when you need a current id. do not guess that
an older `w19:p3` is still the same pane later. `pane move` in particular **mints a new pane id** when
it crosses into another workspace — continue with `.result.move_result.pane.pane_id`, not the value you
passed in (the old one comes back as `.result.move_result.previous_pane_id` and only resolves for the
moved process's own inherited context).

**agent names** must match `[a-z][a-z0-9_-]{0,31}` and be unique among live agents; a name follows the
pane's current occupant and is cleared when that agent exits or is replaced. agent commands take a live
name or the hosting pane id — never a terminal id or a bare kind label. (the hololive naming rule in the
global instructions fits: lowercase transliterations like `suisei-opus` are valid names as-is.)

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

# 2) attach the agent. everything after `--` is the agent's own argv (flags only here).
#    no retry loop needed on 0.8.0: agent start blocks until the pane is interactive-ready.
herdr agent start reviewer --kind claude --pane "$PID" \
  -- --model opus --effort medium --dangerously-skip-permissions

# 3) submit the task and wait in one call. --wait settles on idle, done, OR blocked.
herdr agent prompt reviewer \
  "review the test coverage in src/api/. write the result to /path/to/repo/scratchpad/reviewer.md" \
  --wait --timeout 600000
cat /path/to/repo/scratchpad/reviewer.md      # retrieve via file, not pane read
```

**`agent prompt` submits atomically on 0.8.0** — text plus an encoded Enter in one request, honoring
the pane's live bracketed-paste mode. this reverses the 0.7.5 rule that it "does not press Enter", and
it is why the opening prompt no longer has to ride in argv (measured 2026-08-04: `agent prompt … --wait`
returned in 11s with the task's output file written). passing the prompt as a positional argv arg to
claude still works and is fine when you want the task visible in the pane's own scrollback from the
first frame; both are supported.

**do not open with `agent wait --until working` on 0.8.0.** `agent start` now returns only once the
pane is interactive-ready (`interactive_ready: true` in its response), which takes long enough that a
short task can already be *finished* by the time it returns — the working transition then never
arrives and the wait burns its whole timeout (measured 2026-08-04: a full 60s on a task that had
already written its output file). `agent prompt --wait` has its own guard and needs no help: a prompt
sent from a non-working state must produce an observed lifecycle change within 5s or herdr returns
`agent_prompt_stalled` rather than hanging. reach for `--until` only for a state-specific wait, e.g.
`agent wait <name> --until blocked` to catch an already-running agent asking for input.

**prefer `agent prompt` over `pane run` for anything typed into an agent.** `pane run` types and
presses Enter for an ordinary shell reliably (verified 2026-08-04), but into a claude TUI it has been
seen to leave its text sitting unsubmitted at the `❯` prompt with the agent idle — observed once on
0.8.0 right after a completed turn, **and not reproduced** on a later identical attempt the same day,
so treat it as probabilistic rather than as a rule about timing. `agent prompt` is the surface with the
atomic-submit guarantee. if you do use `pane run` on an agent, verify with `pane read --source visible`
and send Enter yourself (`pane send-keys <id> Enter`) when the text is still there.

nine non-obvious traps (each burns a fresh session if you skip it). the six about spawning, waiting,
and submitting were re-verified 2026-08-04 against herdr 0.8.0 by actually spawning a worker; the last
three (permissions, result retrieval, folder trust) were not re-run and carry over from 0.7.5:

- **anchor with `--current`, not `$HERDR_PANE_ID`.** the `HERDR_*` env vars are captured at pane start and go **stale** when the pane is later moved — a real session had `HERDR_WORKSPACE_ID=wAJ` while it was actually sitting in `wAQ`, and every spawn using it failed. `--current` asks the server where you are right now. (pane ids are **not** recycled — measured 2026-08-21 on 0.8.2, split -> close -> split handed out `p5` then `p6` — so a stale id fails loudly rather than aiming at someone else's pane. re-read ids anyway: a pane can be closed or moved out from under you.)
- **`agent start` needs `--kind` and an existing pane.** signature is `agent start <NAME> --kind <KIND> --pane <ID> [-- AGENT_ARGV...]`. `--workspace`, `--tab`, `--split`, `--no-focus`, and `--cwd` are all gone from it; the canonical executable comes from `--kind` (`claude`, `codex`, `agy`, …), so `-- claude ...` becomes `-- <claude's own flags>`.
- **`agent start` right after `pane split` no longer needs a retry loop** — it waits for interactive readiness itself (`--timeout <MS>`, default 30000, max 300000) and answers with `interactive_ready: true`. this reverses the 0.7.5 advice to retry the identical command, and it is *why* the working-wait above now backfires. if it does fail, it is a real failure — retrying blind just re-burns the readiness timeout.
- **`agent prompt` presses Enter now** (0.8.0), atomically and bracketed-paste-aware. the 0.7.5 trap — text left sitting in the input box, `--wait` then reporting `agent_prompt_stalled` as if the agent hung — is gone; that error code now means what it says, a genuine absence of any lifecycle change within 5s. `pane run` into an agent is the one that has been seen to swallow Enter (above), so prompt through the agent surface.
- **a blocked agent refuses prompts outright** (0.8.2, from `agent prompt --help`): submission is rejected with `agent_blocked` *before any input is sent*, so a worker sitting on a permission or trust dialog cannot be nudged with `agent prompt` at all. read the dialog (`agent read`/`pane read --source visible`) and answer it with `send-keys` first. the bundled 0.8.2 skill says `agent start` likewise returns `agent_not_ready` immediately when the agent comes up blocked, while keeping the name usable for `agent read` and `agent send-keys` (not re-measured here) — that is the shape the folder-trust trap below now takes.
- **never wait on `--until idle`.** a finished pane you have not looked at reports `done`, not `idle`, so an idle wait runs to the timeout (measured: a full 300s while the task had finished in 19s). the bare `agent wait <name> --timeout <MS>` matches idle, done, **and** blocked — which also means a permission prompt wakes you instead of hanging. `--status` is spelled `--until` now. (`done` for an unfocused worker re-confirmed on 0.8.0; note a pane can also settle straight to `idle`, which is exactly why the bare wait is the only safe form.)
- **`agent wait --until working` is a trap on the spawn path.** see the recipe above: `agent start` returns interactive-ready, by which point a short task may already be done, and the transition never comes. keep it only for prompts submitted into a live agent, with a short timeout and `|| true`.
- **unattended runs need `--dangerously-skip-permissions`.** a spawned claude starts in the default interactive permission mode and goes `blocked` (see `pane list` status) on the very first tool call, waiting on a "Do you want to proceed?" prompt. an already-blocked pane can be approved with `herdr pane send-keys <id> Enter` (default highlight is "1. Yes"), but every new command re-prompts, so spawn with skip from the start.
- **retrieve the result via a file, not `pane read`.** claude's TUI collapses its final answer, so `pane read --source recent/visible/recent-unwrapped` often returns nothing usable — the pane runs on the terminal's alternate screen, and rows that scroll off it never enter herdr's host scrollback, so a bigger `--lines` cannot recover them. put "write the result to <repo>/scratchpad/<name>.md" in the task from the start and `cat` that file. **the bundled skill disagrees here** — it says to ask for file output only as a fallback after a failed read. for claude workers we ask up front on purpose: the failed read is the common case, not the exception, and discovering it afterwards costs a whole extra round trip to an agent that has already gone idle. reserve `pane read` for progress checks. note also that claude may render a *suggested* follow-up in the input box, so text sitting at the `❯` prompt is not proof that your own input landed.
- **a fresh cwd triggers claude's folder-trust prompt.** on the first run in a directory claude has never seen, an "Is this a project you trust?" prompt appears before the task starts — `--dangerously-skip-permissions` does NOT bypass it, and herdr detects the pane as **idle** (not blocked), so the working-wait times out. confirm with `pane read --source visible`, then approve with `herdr pane send-keys <id> Enter` (default highlight is "1. Yes, I trust this folder"). already-trusted directories (existing repos) don't prompt.

**pick the split direction from the pane's geometry**, not by habit: `herdr pane layout --pane <id>`
(or `--current`) reports it — split a wide pane `right`, a narrow or tall one `down`. repeated
same-direction splits leave columns too narrow to read.

`--cwd` on the split is required in practice: without it the new pane inherits the herdr server's cwd (usually `~`), not your repo. `pane split --env KEY=VALUE` sets env for the launched shell — use it to forward `CLAUDE_CONFIG_DIR` when you run under a ccs profile.

this path is also the only place you control **effort**: `--effort <level>` in the agent's argv works and is visible in the spawned pane's banner (`Opus 5 with medium effort`). pick the level per the effort policy in the global rules — the Agent-tool path has no effort knob at all.

**what a pane actually costs** (kil9 note, measured 2026-07-25 on herdr 0.7.5 with Opus 5, same trivial task; the earlier numbers were Haiku on 2026-07-12). startup + one turn is ~6s (split 0.06s + `agent start` 3.2s + first response 2.7s), on par with the old ~7s. the prefix (first-turn `cache_write`) is 67k for a pane (two samples: 66,684 / 66,763) vs 50k for an Agent-tool subagent — 1.3x, same order of magnitude. so the real cost of a pane is not tokens but the **completion-detection round trip and orchestration chores**, a constant per task. a fork reuses the leader's prefix cache, so anything a fork can do is always cheapest that way.

**a pane sometimes pays the prefix twice.** in one of those two samples the second turn came back with `cache_read=0` and regenerated the prefix, putting total `cache_write` at 134k against 68k for the healthy sample. the Agent-tool path never did this. it is probabilistic — one measurement will not show it — and when it hits, the pane costs double.

## the binary ships its own skill — read it when in doubt

`herdr --skill` (0.8.0+) prints the agent skill bundled with the running binary: ~195 lines stating
herdr's own contract for ids, lifecycle states, spawning, and reading. it is version-locked to the
binary in your PATH, so it cannot drift the way this file can. **this file is the measured layer on
top of it** — the traps below are things the bundled skill does not tell you, and where the two
disagree, prefer whichever was verified more recently and say so. (a 2026-08-04 pass reconciled them
on 0.8.0; the bundled skill was right about error streams, `wait-output` semantics, and atomic prompt
submission, and this file keeps its own line on retrieving results by file. 0.8.2 rewrote the bundled
skill wholesale — new id examples, geometry-driven splits, `agent_blocked`/`agent_not_ready`, and a
much narrower trigger clause telling an agent to use herdr only when the user names it. a 2026-08-21
pass folded its facts in; the trigger clause is deliberately **not** adopted — when to reach for a
pane is decided by the global rules, not by the vendor's default.)

## safety rules that cost a session when broken

- never `herdr server stop` from inside an active session, and never kill the main herdr process — it takes every pane's processes with it. use a named test session for experiments that need their own server.
- do not close workspaces, tabs, or panes you did not create.
- `--no-focus` for background work; the user's focus is theirs.
- omitting a target does not mean "me" — it can resolve to the UI-focused pane, which may belong to the user or another client. use `--current`, an explicit id, or a live agent name.

## command groups this skill does not cover

these exist on 0.8.2 and are not described anywhere above — reach for `herdr <group> --help` before
assuming a capability is missing:

- `herdr worktree list|create|open|remove` — git worktree-backed workspaces, first-class. relevant to any parallel-worker flow that would otherwise hand-roll `git worktree add`.
- `herdr integration install|uninstall|status` — built-in per-agent integrations (this is what an opencode pane needs before its history is readable).
- `herdr api snapshot|schema` — the whole live session as one json document, and the bundled socket-api schema. `api snapshot` is usually cheaper than several `list` calls.
- `herdr agent explain` — why herdr detected (or failed to detect) an agent in a pane. the first thing to run when a spawn "worked" but no agent shows up. `--file PATH --agent LABEL` runs the same detector over a captured transcript.
- `herdr agent attach [--takeover]` — hand an already-running pane agent over to this session.
- `herdr pane neighbor|edges|layout|zoom|swap|process-info` — geometry and layout queries, plus what is actually running in a pane.
- `herdr session list|attach|stop|delete`, `herdr notification show`, `herdr config check|reset-keys`, `herdr channel show|set`.

## further reading

- recipes for the other branches — run a server, run tests, watch or coordinate with another pane: [`references/recipes.md`](references/recipes.md)
- spawning an `agy` agent instead of claude: [`references/agy-spawn.md`](references/agy-spawn.md)
- which commands print json vs text, and where ids live in the response: [`references/output-shapes.md`](references/output-shapes.md)
- full command reference: [`references/commands.md`](references/commands.md)
