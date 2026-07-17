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

## wait for output

block until specific text appears in a pane. useful for waiting on servers, builds, and tests.

for `--source recent`, matching uses unwrapped recent terminal text, so pane width and soft wrapping do not break matches. `pane read --source recent` still shows the pane as rendered. if you want to inspect the same transcript that the waiter matches, use `pane read --source recent-unwrapped`.

```bash
herdr wait output 1-3 --match "ready on port 3000" --timeout 30000
```

with regex:

```bash
herdr wait output 1-3 --match "server.*ready" --regex --timeout 30000
```

if it times out, exit code is `1`.

## wait for an agent status

block until another agent reaches a specific status:

```bash
herdr agent wait 1-1 --status idle --timeout 60000
```

`herdr agent wait` accepts pane ids, unique agent names, and detected agent labels.

do not wait for `done` (kil9 note, verified 2026-07). `done` is a UI notification state — idle plus "you have not looked at that pane yet". if the finished pane is visible on the active tab it is marked seen immediately and skips `done` entirely, so a wait on `done` can hang forever. always wait for `idle` to detect completion; `herdr agent wait` rejects `--status done` explicitly. the legacy `herdr wait agent-status` accepts `done` silently and only takes pane ids — prefer `herdr agent wait`.

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
