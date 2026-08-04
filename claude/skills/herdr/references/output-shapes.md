# what each command prints

lookup table for parsing herdr output. read it when you need to pull an id out of a response or
you are unsure whether a command returns json or text.

- `workspace list`, `workspace create`, `tab list`, `tab create`, `tab get`, `tab focus`, `tab rename`, `tab close`, `pane list`, `pane get`, `pane current`, `pane split`, `pane close`, `pane wait-output`, `agent list`, `agent get`, `agent start`, and `agent wait` print json on success.
- `pane read` prints text, not json.
- errors are json too, on stdout, with a nonzero exit: `{"error":{"code":"timeout","message":"…"},"id":"…"}`. check the exit code — don't try to parse a `result` that isn't there.
- ids are namespaced strings (`wHW`, `wHW:t1`, `wHW:p2`), so always pull them out as whole values; never split or rebuild them.
- `pane read --format ansi` or `pane read --ansi` returns a rendered ANSI snapshot for TUI feedback loops.
- `pane read --source recent-unwrapped` is useful when you want to inspect the same unwrapped transcript that `pane wait-output --source recent` matches against.
- `pane send-text`, `pane send-keys`, and `pane run` print nothing on success.
- parse ids from `workspace create`, `tab create`, and `pane split` responses when you need new ids. `workspace create` returns `result.workspace`, `result.tab`, and `result.root_pane`. `tab create` returns `result.tab` and `result.root_pane`. for `pane split`, the new pane id is at `result.pane.pane_id`.
- `agent start` returns the attached agent at `result.agent`, including `interactive_ready` and the harness's own session id at `result.agent_session.value` — and echoes the argv it launched at `result.argv`, which is the quickest way to confirm your `--` flags landed where you meant.
- `herdr api snapshot` gives the whole live session in one json document — cheaper than several `list` calls when you need more than one thing.
- use `pane read` for current output that already exists. use `pane wait-output` for future output you expect next.
- `--no-focus` on split, tab create, and workspace create keeps your current terminal context focused.
- without `--label`, workspace create keeps cwd-based naming and tab create keeps numbered naming.
- `--label` on tab create and workspace create applies the custom name immediately.
- if you are running inside herdr, the `HERDR_ENV` environment variable is set to `1`.
