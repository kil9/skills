# spawning an antigravity (agy) agent

branch-only: read this when the agent you need to spawn is `agy`, not `claude`. for claude, the
recipe in [`../SKILL.md`](../SKILL.md) is authoritative and the nine traps there apply here too.

### spawn an antigravity (agy) agent

herdr natively detects `agy` as an agent (working spinner / blocked permission-prompt rules built in), so the same start/wait/read pattern works (kil9 note, verified 2026-07). **the syntax below was mechanically updated to 0.7.5 alongside the claude recipe but not re-run on agy** — expect the same traps and trust the claude recipe over this one where they disagree:

```bash
PID=$(herdr pane split --current --direction right --no-focus --cwd /path/to/repo \
  | python3 -c 'import sys,json; print(json.load(sys.stdin)["result"]["pane"]["pane_id"])')
herdr agent start helper --kind agy --pane "$PID" -- --dangerously-skip-permissions -i "summarize what script/foo.sh does"
herdr agent wait helper --until working --timeout 30000
herdr agent wait helper --timeout 600000
herdr agent read helper --source visible --lines 60
```

two agy-specific caveats:

- `-i` (`--prompt-interactive`) is required — unlike claude, agy does not treat a positional argument as the prompt; without `-i` the task never starts.
- right after the idle transition, `agent read --source recent` can return an empty string. read with `--source visible` instead.

for a one-shot task that needs no pane, run `agy -p "<prompt>"` headless from your own shell (`--print-timeout` defaults to 5m).
