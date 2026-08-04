# herdr recipes (branches other than spawning an agent)

each heading is a separate branch — read the one you need. spawning an agent is the exception:
that recipe and its nine traps live in [`../SKILL.md`](../SKILL.md) because they burn a session
when skipped.

### run a server and wait until it is ready

```bash
NEW_PANE=$(herdr pane split wHW:p2 --direction right --no-focus | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"]["pane"]["pane_id"])')
herdr pane run "$NEW_PANE" "npm run dev"
herdr pane wait-output "$NEW_PANE" --match "ready" --timeout 30000
herdr pane read "$NEW_PANE" --source recent --lines 20
```

### run tests in a separate pane and inspect the result

```bash
herdr pane split wHW:p2 --direction down --no-focus
herdr pane run wHW:p3 "cargo test"
herdr pane wait-output wHW:p3 --match "test result" --timeout 60000
herdr pane read wHW:p3 --source recent --lines 30
```

### check what another agent is working on

```bash
herdr pane list
herdr pane read wHW:p1 --source recent --lines 80
```

### watch another pane robustly

use this pattern when you need to coordinate with a sibling pane:

```bash
# inspect what is already there
herdr pane read wHW:p3 --source recent --lines 40

# wait only for the next output you expect
herdr pane wait-output wHW:p3 --match "ready" --timeout 30000

# if you need to inspect the same transcript the waiter matched,
# read the unwrapped recent text directly
herdr pane read wHW:p3 --source recent-unwrapped --lines 40
```

### coordinate with another agent

```bash
herdr agent wait wHW:p1 --timeout 120000     # no --until: idle, done, or blocked
herdr pane read wHW:p1 --source recent --lines 100
```
