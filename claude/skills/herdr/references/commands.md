# herdr command reference

lookup-only crud syntax for `herdr` tabs, panes, workspaces, and waits. the skill body keeps the
concepts, recipes, and traps; this file holds the command shapes you look up rather than memorize.
`herdr <subcommand> --help` is authoritative if this drifts.

ids below (`wHW`, `wHW:t2`, `wHW:p1`) are **illustrative, not real** — read live ones out of
`pane list` / `pane current` / `workspace list` / a create response. the live shape on 0.8.2 is
`w19` / `w19:t1` / `w19:p4`, and ids are never recycled after a close. verified against herdr 0.8.2
on 2026-08-21.

## tab management

list tabs in the current workspace:

```bash
herdr tab list --workspace wHW
```

create a new tab:

```bash
herdr tab create --workspace wHW
```

without `--label`, the new tab keeps the default numbered tab name.

create and name it in one step:

```bash
herdr tab create --workspace wHW --label "logs"
```

rename it:

```bash
herdr tab rename wHW:t2 "logs"
```

note: the sidebar's agents panel shows `workspace · tab-label` only when the workspace has
**two or more tabs**. with a single tab, only the workspace name shows — even if the tab has a
custom label (kil9 note, verified 2026-07). the tab label still appears in the tab row at the
top of the workspace view.

focus it:

```bash
herdr tab focus wHW:t2
```

close it:

```bash
herdr tab close wHW:t2
```

## read another pane

see what is on another pane's screen:

```bash
herdr pane read wHW:p1 --source recent --lines 50
```

`pane read` takes the pane id **positionally only** — it has no `--pane` / `--current` (it errors with
`unknown option: --current`). resolve your own id with `pane current --current` first.

- `--source visible` = current viewport
- `--source recent` = recent scrollback as rendered in the pane (default)
- `--source recent-unwrapped` = recent terminal text with soft wraps joined back together
- `--source detection` = the slice herdr's own agent detector looks at; pair it with `agent explain`.
  `pane read --help` on 0.8.2 omits it but the command still accepts it (verified 2026-08-21);
  `agent read` documents it.

`--format text|ansi`, `--ansi`, and `--raw` control how much escape sequence survives. note the CLI
spells the third source with a hyphen (`recent-unwrapped`) while the socket API wire value is
snake_case (`recent_unwrapped`) — don't carry one spelling into the other.

## split a pane and run a command

split your pane to the right and keep focus on your current pane:

```bash
herdr pane split wHW:p2 --direction right --no-focus
```

that prints json with the new pane nested at `result.pane.pane_id`. parse that value, then run a command in that pane:

```bash
NEW_PANE=$(herdr pane split wHW:p2 --direction right --no-focus | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"]["pane"]["pane_id"])')
herdr pane run "$NEW_PANE" "npm run dev"
```

split downward instead:

```bash
herdr pane split wHW:p2 --direction down --no-focus
```

to split from *your own* pane without knowing its id, use `--current` instead of a pane id — safer
than `$HERDR_PANE_ID`, which is captured at pane start and goes stale if the pane is later moved:

```bash
herdr pane split --current --direction right --no-focus --cwd /path/to/repo
```

`--cwd` sets the new shell's directory (otherwise it inherits the herdr server's cwd, usually `~`)
and `--env KEY=VALUE` sets env for it.

## wait for output

block until specific text appears in a pane. useful for waiting on servers, builds, and tests.

it matches against the snapshot **as it already is**, then keeps watching — text printed before you
called it still matches, immediately (verified 2026-08-04). so there is no race to lose by starting
the waiter late, and equally: a stale line from an earlier run can satisfy it. `--regex` takes a Rust
regular expression. omitting `--timeout` waits indefinitely.

for `--source recent`, matching uses unwrapped recent terminal text, so pane width and soft wrapping do not break matches. `pane read --source recent` still shows the pane as rendered. if you want to inspect the same transcript that the waiter matches, use `pane read --source recent-unwrapped`.

```bash
herdr pane wait-output wHW:p3 --match "ready on port 3000" --timeout 30000
```

with regex — `--regex` takes the pattern itself and replaces `--match`, it is not a modifier on it:

```bash
herdr pane wait-output wHW:p3 --regex "server.*ready" --timeout 30000
```

if it times out, exit code is `1`.

## wait for an agent status

block until another agent reaches a terminal state:

```bash
herdr agent wait wHW:p1 --timeout 60000
```

`herdr agent wait` accepts pane ids, unique agent names, and detected agent labels. the flag is
`--until <STATUS>` (repeatable); the old `--status` spelling is gone, and the top-level
`herdr wait output` / `herdr wait agent-status` commands are gone with it — they now live under
`pane wait-output` and `agent wait`.

**prefer the bare wait above, with no `--until`** (kil9 note, re-verified 2026-07-25 on 0.7.5). it
matches `idle`, `done`, or `blocked`, so it catches completion however herdr labels it *and* wakes on
a permission prompt instead of hanging. the older advice — "always wait for `idle`, never `done`" —
backfires here: `done` is idle plus "you have not looked at that pane yet", and a worker pane you
spawned unfocused stays unseen, so it settles on `done` and **never** reaches `idle`. a measured
`--until idle` wait burned its full 300s timeout on a task that had finished in 19s. (`--until done`
has the mirror-image failure if you *are* looking at the pane, which is why neither one alone is
safe.)

one more race: right after you submit a prompt **into an already-live agent**, it is still in its
previous state, so a terminal-state wait can return in milliseconds having matched nothing new. guard
that case with `--until working --timeout 10000 || true` before the bare wait.

do **not** put that guard on the spawn path. on 0.8.0 `agent start` returns only once the pane is
interactive-ready, so a short task can be finished before it returns and the working transition never
arrives — measured 2026-08-04, a full 60s timeout on a task whose output file already existed. the
skill body's spawn recipe covers this.

## submit a prompt to an agent

```bash
herdr agent prompt reviewer "<task text>" --wait --timeout 600000
```

sends the text and an encoded Enter in one atomic request, bracketed-paste aware. if the agent is
**already blocked** on an approval or question dialog the submission is refused with `agent_blocked`
and no bytes are written — answer the dialog with `send-keys` before prompting. `--wait` settles on
idle, done, or blocked — the same defaults as a bare `agent wait`, so don't restate them with `--until`.
if no lifecycle change is observed within 5s of a submission from a non-working state, it returns
`agent_prompt_stalled`; a shorter `--timeout` returns `timeout` instead. it tracks lifecycle state, not
turns, so if the agent was already working, that in-flight turn's completion can satisfy the wait.

keys go through the agent surface too, validated before any byte is written:

```bash
herdr agent send-keys reviewer esc
herdr agent send-keys reviewer ctrl+c
```

## send text or keys to a pane

send text without pressing Enter:

```bash
herdr pane send-text wHW:p1 "hello from claude"
```

press Enter or other keys:

```bash
herdr pane send-keys wHW:p1 Enter
```

`pane run` sends the text and then a real `Enter` key in one request:

```bash
herdr pane run wHW:p1 "echo hello"
```

## workspace management

create a new workspace:

```bash
herdr workspace create --cwd /path/to/project
```

without `--label`, the new workspace keeps the default cwd-based name.

create and name one in one step:

```bash
herdr workspace create --cwd /path/to/project --label "api server"
```

create one without focusing it:

```bash
herdr workspace create --no-focus
```

focus a workspace:

```bash
herdr workspace focus wHV
```

rename:

```bash
herdr workspace rename wHW "api server"
```

close:

```bash
herdr workspace close wHV
```

## move a pane to another tab or workspace

`herdr pane move` relocates an existing pane. it has three forms — into an existing tab, into a brand-new tab, or detached into a brand-new workspace. the pane keeps its running process (shell, agent, server) across the move.

move a pane into another tab (works across workspaces — pass a `tab_id` from any workspace) and dock it with a split:

```bash
herdr pane move wHW:p2 --tab wHV:t1 --split right
```

- `--split right|down` is required and sets how it docks in the target tab.
- `--target-pane ID` docks it next to a specific pane in that tab (default: the tab's active pane).
- `--ratio FLOAT` sets the split ratio.
- **the pane's id changes** when the move crosses workspaces (ids are workspace-qualified). take the new one from `.result.move_result.pane.pane_id`; `.result.move_result.previous_pane_id` holds the old value, which afterwards resolves only for the moved process's own inherited context — not as a target you can pass back in.

break a pane out into a new tab (same workspace by default, or `--workspace ID` for another):

```bash
herdr pane move wHW:p2 --new-tab --label "logs"
```

detach a pane into a brand-new workspace of its own (this is the "split it into a new space" case):

```bash
herdr pane move wHW:p2 --new-workspace --label "api server" --tab-label "server"
```

- `--label` names the new workspace; `--tab-label` names its first tab.
- all three forms take `--focus` / `--no-focus` to control whether focus follows the moved pane (default follows).

note: unlike most `pane` subcommands, `pane move` takes the pane id positionally and does not accept `--current` / `--pane`. from a keybinding, use the `HERDR_ACTIVE_PANE_ID` env var (see the config's `[[keys.command]]` entries); from a script, resolve the focused pane first with `herdr pane current`.

## close a pane

```bash
herdr pane close wHW:p3
```

## git worktree workspaces

herdr can own the worktree, not just a pane inside one — a worktree workspace is created, opened, and
torn down as a unit. use this instead of hand-rolling `git worktree add` when spawning parallel
workers on branches.

```bash
herdr worktree create --cwd /path/to/repo --branch feat/x --base main --label "feat x" --no-focus
herdr worktree list --cwd /path/to/repo
herdr worktree open --cwd /path/to/repo --branch feat/x
herdr worktree remove --workspace wHZ            # --force to discard a dirty checkout
```

`--path` places the checkout explicitly (otherwise herdr picks the location); `--workspace` targets an
existing workspace instead of making a new one. `remove` takes the **workspace** id, not a path — it
is removing the workspace and its checkout together, so it is not a safe substitute for
`git worktree remove` when something else still has the directory open.
