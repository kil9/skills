# what each command prints

lookup table for parsing herdr output. read it when you need to pull an id out of a response or
you are unsure whether a command returns json or text.

- `workspace list`, `workspace create`, `tab list`, `tab create`, `tab get`, `tab focus`, `tab rename`, `tab close`, `pane list`, `pane get`, `pane current`, `pane split`, `pane close`, `pane wait-output`, `agent list`, `agent get`, `agent start`, and `agent wait` print json on success.
- `pane read` prints text, not json.
- errors are json too, but on **stderr** with exit status 1: `{"error":{"code":"timeout","message":"…"},"id":"…"}`. stdout stays empty, so a bare `cmd | python3 -c ...` sees nothing and dies on an empty parse rather than showing you the error. CLI *syntax* errors exit 2. check the exit code first; only parse `result` after a 0.
- ids are namespaced strings (`wHW`, `wHW:t1`, `wHW:p2`), so always pull them out as whole values; never split or rebuild them.
- `pane read --format ansi` or `pane read --ansi` returns a rendered ANSI snapshot for TUI feedback loops.
- `pane read --source recent-unwrapped` is useful when you want to inspect the same unwrapped transcript that `pane wait-output --source recent` matches against.
- `pane send-text`, `pane send-keys`, and `pane run` print nothing on success.
- parse ids from `workspace create`, `tab create`, and `pane split` responses when you need new ids. `workspace create` returns `result.workspace`, `result.tab`, and `result.root_pane`. `tab create` returns `result.tab` and `result.root_pane`. for `pane split`, the new pane id is at `result.pane.pane_id`.
- `agent start` returns the attached agent at `result.agent`, including `interactive_ready` and the harness's own session id at `result.agent_session.value` — and echoes the argv it launched at `result.argv`, which is the quickest way to confirm your `--` flags landed where you meant.
- `herdr api snapshot` gives the whole live session in one json document — cheaper than several `list` calls when you need more than one thing.
- `pane wait-output` searches the selected snapshot **immediately**, so output that is already on screen matches at once and returns in ~0s (verified 2026-08-04). it is not a future-only watcher — you do not have to race it against the command you are waiting on. use `pane read` when you want the text itself rather than a match.
- `--no-focus` on split, tab create, and workspace create keeps your current terminal context focused.
- without `--label`, workspace create keeps cwd-based naming and tab create keeps numbered naming.
- `--label` on tab create and workspace create applies the custom name immediately.
- if you are running inside herdr, the `HERDR_ENV` environment variable is set to `1`.
