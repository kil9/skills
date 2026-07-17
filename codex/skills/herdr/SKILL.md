---
name: herdr
description: "Control herdr from inside it. Manage workspaces and tabs, split panes, spawn agents, read output, and wait for state changes — all via CLI commands that talk to the running herdr instance over a local unix socket. Use when running inside herdr (HERDR_ENV=1)."
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

### run a server and wait until it is ready

```bash
NEW_PANE=$(herdr pane split 1-2 --direction right --no-focus | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"]["pane"]["pane_id"])')
herdr pane run "$NEW_PANE" "npm run dev"
herdr wait output "$NEW_PANE" --match "ready" --timeout 30000
herdr pane read "$NEW_PANE" --source recent --lines 20
```

### run tests in a separate pane and inspect the result

```bash
herdr pane split 1-2 --direction down --no-focus
herdr pane run 1-3 "cargo test"
herdr wait output 1-3 --match "test result" --timeout 60000
herdr pane read 1-3 --source recent --lines 30
```

### check what another agent is working on

```bash
herdr pane list
herdr pane read 1-1 --source recent --lines 80
```

### watch another pane robustly

use this pattern when you need to coordinate with a sibling pane:

```bash
# inspect what is already there
herdr pane read 1-3 --source recent --lines 40

# wait only for the next output you expect
herdr wait output 1-3 --match "ready" --timeout 30000

# if you need to inspect the same transcript the waiter matched,
# read the unwrapped recent text directly
herdr pane read 1-3 --source recent-unwrapped --lines 40
```

### spawn a new agent and give it a task

use `herdr agent start` — it splits, launches, and registers the agent under a name in one step (kil9 note, verified 2026-07):

```bash
# pin the spawn to YOUR tab, skip permission prompts, retrieve the result via file
herdr agent start reviewer --workspace "$HERDR_WORKSPACE_ID" --tab "$HERDR_TAB_ID" \
  --split right --no-focus --cwd /path/to/repo \
  -- claude --dangerously-skip-permissions "review the test coverage in src/api/. write the result to /path/to/repo/scratchpad/reviewer.md"
herdr agent wait reviewer --status idle --timeout 600000     # wait for completion (idle, NOT done)
cat /path/to/repo/scratchpad/reviewer.md                     # retrieve via file, not pane read
```

five non-obvious traps, all verified 2026-07 (each burns a fresh session if you skip it):

- **pin the landing spot with `--workspace`/`--tab`.** `agent start --split` splits from whichever pane is focused in the herdr UI, which may be a *different* workspace than yours — the spawned agent lands there (and can vanish), not beside you. `agent start` has no anchor-pane flag, so pass `--workspace "$HERDR_WORKSPACE_ID" --tab "$HERDR_TAB_ID"` (your own env vars) to force it into your tab. fallback: `herdr pane split "$HERDR_PANE_ID" ...` explicitly, then `pane run` claude into the returned pane id (you lose the name registration and auto-`--cwd`).
- **unattended runs need `--dangerously-skip-permissions`.** a spawned claude starts in the default interactive permission mode and goes `blocked` (see `pane list` status) on the very first tool call, waiting on a "Do you want to proceed?" prompt. add `--dangerously-skip-permissions` (or a suitable `--permission-mode`) so it runs to completion. an already-blocked pane can be approved with `herdr pane send-keys <id> Enter` (default highlight is "1. Yes"), but every new command re-prompts, so spawn with skip from the start.
- **retrieve the result via a file, not `pane read`.** claude's TUI collapses its final answer, so `pane read --source recent/visible/recent-unwrapped` often returns nothing usable. put "write the result to <repo>/scratchpad/<name>.md" in the task and `cat` that file. reserve `pane read` for progress checks.
- **wait for `idle`, never `done`** (see the wait-status section above).
- **a fresh cwd triggers claude's folder-trust prompt.** on the first run in a directory claude has never seen, an "Is this a project you trust?" prompt appears before the task starts — `--dangerously-skip-permissions` does NOT bypass it, and herdr detects the pane as **idle** (not blocked), so `wait --status working` times out and an idle wait releases immediately (falsely). if the working-wait times out right after spawn, confirm with `pane read --source visible`, then approve with `herdr pane send-keys <id> Enter` (default highlight is "1. Yes, I trust this folder"). already-trusted directories (existing repos) don't prompt.

`--cwd` is required in practice: without it the new pane inherits the herdr server's cwd (usually `~`), not your repo.

to send a follow-up task, note that `herdr agent send` writes literal text without pressing Enter. use `herdr pane run <pane_id> "<text>"` to submit, or follow `agent send` with `herdr pane send-keys <pane_id> Enter`.

### spawn an antigravity (agy) agent

herdr natively detects `agy` as an agent (working spinner / blocked permission-prompt rules built in), so the same start/wait/read pattern works (kil9 note, verified 2026-07):

```bash
herdr agent start helper --split right --no-focus --cwd /path/to/repo -- agy --dangerously-skip-permissions -i "summarize what script/foo.sh does"
herdr agent wait helper --status working --timeout 30000
herdr agent wait helper --status idle --timeout 600000
herdr agent read helper --source visible --lines 60
```

two agy-specific caveats:

- `-i` (`--prompt-interactive`) is required — unlike claude, agy does not treat a positional argument as the prompt; without `-i` the task never starts.
- right after the idle transition, `agent read --source recent` can return an empty string. read with `--source visible` instead.

for a one-shot task that needs no pane, run `agy -p "<prompt>"` headless from your own shell (`--print-timeout` defaults to 5m).

### coordinate with another agent

```bash
herdr agent wait 1-1 --status idle --timeout 120000
herdr pane read 1-1 --source recent --lines 100
```

## notes

- `workspace list`, `workspace create`, `tab list`, `tab create`, `tab get`, `tab focus`, `tab rename`, `tab close`, `pane list`, `pane get`, `pane split`, `wait output`, and `wait agent-status` print json on success.
- `pane read` prints text, not json.
- `pane read --format ansi` or `pane read --ansi` returns a rendered ANSI snapshot for TUI feedback loops.
- `pane read --source recent-unwrapped` is useful when you want to inspect the same unwrapped transcript that `wait output --source recent` matches against.
- `pane send-text`, `pane send-keys`, and `pane run` print nothing on success.
- parse ids from `workspace create`, `tab create`, and `pane split` responses when you need new ids. `workspace create` returns `result.workspace`, `result.tab`, and `result.root_pane`. `tab create` returns `result.tab` and `result.root_pane`. for `pane split`, the new pane id is at `result.pane.pane_id`.
- use `pane read` for current output that already exists. use `wait output` for future output you expect next.
- `--no-focus` on split, tab create, and workspace create keeps your current terminal context focused.
- without `--label`, workspace create keeps cwd-based naming and tab create keeps numbered naming.
- `--label` on tab create and workspace create applies the custom name immediately.
- if you are running inside herdr, the `HERDR_ENV` environment variable is set to `1`.
