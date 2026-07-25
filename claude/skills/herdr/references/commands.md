# herdr command reference

lookup-only crud syntax for `herdr` tabs, panes, workspaces, and waits. the skill body keeps the
concepts, recipes, and traps; this file holds the command shapes you look up rather than memorize.
`herdr <subcommand> --help` is authoritative if this drifts.

## tab management

list tabs in the current workspace:

```bash
herdr tab list --workspace 1
```

create a new tab:

```bash
herdr tab create --workspace 1
```

without `--label`, the new tab keeps the default numbered tab name.

create and name it in one step:

```bash
herdr tab create --workspace 1 --label "logs"
```

rename it:

```bash
herdr tab rename 1:2 "logs"
```

note: the sidebar's agents panel shows `workspace · tab-label` only when the workspace has
**two or more tabs**. with a single tab, only the workspace name shows — even if the tab has a
custom label (kil9 note, verified 2026-07). the tab label still appears in the tab row at the
top of the workspace view.

focus it:

```bash
herdr tab focus 1:2
```

close it:

```bash
herdr tab close 1:2
```

## read another pane

see what is on another pane's screen:

```bash
herdr pane read 1-1 --source recent --lines 50
```

- `--source visible` = current viewport
- `--source recent` = recent scrollback as rendered in the pane
- `--source recent-unwrapped` = recent terminal text with soft wraps joined back together

## split a pane and run a command

split your pane to the right and keep focus on your current pane:

```bash
herdr pane split 1-2 --direction right --no-focus
```

that prints json with the new pane nested at `result.pane.pane_id`. parse that value, then run a command in that pane:

```bash
NEW_PANE=$(herdr pane split 1-2 --direction right --no-focus | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"]["pane"]["pane_id"])')
herdr pane run "$NEW_PANE" "npm run dev"
```

split downward instead:

```bash
herdr pane split 1-2 --direction down --no-focus
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

for `--source recent`, matching uses unwrapped recent terminal text, so pane width and soft wrapping do not break matches. `pane read --source recent` still shows the pane as rendered. if you want to inspect the same transcript that the waiter matches, use `pane read --source recent-unwrapped`.

```bash
herdr pane wait-output 1-3 --match "ready on port 3000" --timeout 30000
```

with regex — `--regex` takes the pattern itself and replaces `--match`, it is not a modifier on it:

```bash
herdr pane wait-output 1-3 --regex "server.*ready" --timeout 30000
```

if it times out, exit code is `1`.

## wait for an agent status

block until another agent reaches a terminal state:

```bash
herdr agent wait 1-1 --timeout 60000
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

one more race: right after you submit a prompt the agent is still in its previous state, so a
terminal-state wait can return in milliseconds having matched nothing new. wait `--until working`
first, then do the bare wait.

## send text or keys to a pane

send text without pressing Enter:

```bash
herdr pane send-text 1-1 "hello from claude"
```

press Enter or other keys:

```bash
herdr pane send-keys 1-1 Enter
```

`pane run` sends the text and then a real `Enter` key in one request:

```bash
herdr pane run 1-1 "echo hello"
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
herdr workspace focus 2
```

rename:

```bash
herdr workspace rename 1 "api server"
```

close:

```bash
herdr workspace close 2
```

## move a pane to another tab or workspace

`herdr pane move` relocates an existing pane. it has three forms — into an existing tab, into a brand-new tab, or detached into a brand-new workspace. the pane keeps its running process (shell, agent, server) across the move.

move a pane into another tab (works across workspaces — pass a `tab_id` from any workspace) and dock it with a split:

```bash
herdr pane move 1-2 --tab 2:1 --split right
```

- `--split right|down` is required and sets how it docks in the target tab.
- `--target-pane ID` docks it next to a specific pane in that tab (default: the tab's active pane).
- `--ratio FLOAT` sets the split ratio.

break a pane out into a new tab (same workspace by default, or `--workspace ID` for another):

```bash
herdr pane move 1-2 --new-tab --label "logs"
```

detach a pane into a brand-new workspace of its own (this is the "split it into a new space" case):

```bash
herdr pane move 1-2 --new-workspace --label "api server" --tab-label "server"
```

- `--label` names the new workspace; `--tab-label` names its first tab.
- all three forms take `--focus` / `--no-focus` to control whether focus follows the moved pane (default follows).

note: unlike most `pane` subcommands, `pane move` takes the pane id positionally and does not accept `--current` / `--pane`. from a keybinding, use the `HERDR_ACTIVE_PANE_ID` env var (see the config's `[[keys.command]]` entries); from a script, resolve the focused pane first with `herdr pane current`.

## close a pane

```bash
herdr pane close 1-3
```
