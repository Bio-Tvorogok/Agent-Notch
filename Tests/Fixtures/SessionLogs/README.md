# Session-log regression fixtures

All records are synthetic. Shapes come from the ClaudeLine and CodexLine parsers
in Sources/NotchCore/Parsers.swift and the DetailReader vendor readers at
fc1a6fde0dbc3ec4922eb43c3fb5082eb2884196. These are parser contracts, not captures
from a particular installed CLI version. No session content or personal paths
were copied. The project path is a placeholder; commands are parsed, never run.

- `claude/parent.jsonl`: a parent session with a sidechain record that must not
  leak into its card. The two `agent-*.jsonl` files become direct and workflow
  subagents in the temporary home; one hands back, one remains working.
- `codex/current.jsonl`: session metadata, turn context, nested `exec` calls,
  structured tool output and a pending human approval.
- `codex/legacy.jsonl`: `session_id`, `local_shell_call`, text tool output and
  the older `agent_message` response payload.
- `codex/resumed.jsonl`: a thread created October 1 and resumed October 13.
  Checks install it twelve date folders back and set its mtime to the poll time.
- `codex/truncated.jsonl`: ends inside a tool argument, without a newline.
  `truncated-suffix.txt` completes the JSON value but still omits the newline.
  The recovery check appends that suffix, polls, then appends the newline.
- `codex/rotated.jsonl`: replaces the current fixture at the same path, with a
  distinct inode and larger contents. The previous approval must disappear.

The checks use a fixed clock and private temporary homes. Date directories use
Calendar.current, matching discovery, so no local midnight boundary is assumed.
Run `sh scripts/test.sh` from the checkout.

`fixtureResumedDiscovery` (a fresh log in an older date folder appears in the
scanner's rows) now runs on every test run.

One known-bug check is skipped by default. Run
`NOTCH_EXPECTED_FAIL=1 sh scripts/test.sh` to include it; it is an ordinary
assertion and makes the command exit nonzero while the bug remains:

- `EXPECTED-FAIL fixtureTruncatedTail`: the detail card should wait for a
  newline before showing the completed tail command, as the scanner does.
  Invalid partial JSON is already ignored; this check covers the interval
  after its remaining bytes arrive but before its newline arrives.

## Sensitivity check

The six default checks pass with production sources extracted from the baseline
revision above. With the opt-in flag, exactly the two known-bug checks fail.
A separate temporary copy with these deliberate reader regressions fails all
six default checks (15 assertions); the checkout's readers were never edited:

| Check | Temporary reader regression |
| --- | --- |
| Claude subagents | Remove ClaudeLine's parent sidechain filter |
| Current Codex | Skip nested `exec` command extraction |
| Legacy Codex | Remove the `session_id` metadata fallback |
| Resumed readers | Stop reopening turns on `task_started` |
| Truncated recovery | Advance the scanner offset past incomplete bytes |
| Rotation | Stop resetting on inode replacement |

This demonstrates sensitivity to regressions, not failure against the unchanged
baseline: supported-format checks intentionally pass before these test additions.
