# Project progress in your statusline

A superpowers project leaves two records of how far it has gotten, and neither
one is visible while you work:

- **The SDD ledger.** `subagent-driven-development` writes
  `.superpowers/sdd/<plan-basename>/progress.md`, appending `Task N: complete`
  as each task passes review. This is the record an autonomous run actually
  produces.
- **The plan's checkboxes.** `writing-plans` emits every step as `- [ ]`. No
  skill ticks them for you today — they are ticked when you or your agent
  update the plan file by hand.

`statusline/superpowers-statusline` reads whichever of the two exists and
renders it as a statusline segment, so a long autonomous run shows its progress
on every turn:

```
superpowers · claude/add-widgets · ⚡ add-widgets ▰▰▰▰▰▰▱▱▱▱ 67% · task 3/3: Docs · 2/3 tasks
```

- `⚡ add-widgets` — the plan being tracked (`✓` once it is finished)
- `▰▰▰▰▰▰▱▱▱▱ 67%` — how much of it is done
- `task 3/3: Docs` — the first task that is not yet complete
- `2/3 tasks` — the unit being counted: `tasks` when the count comes from an
  SDD ledger, `steps` when it comes from the plan's checkboxes

## Install

### Claude Code

Find the script inside your installed plugin:

```bash
find ~/.claude/plugins -name superpowers-statusline -type f | head -1
```

Then point `statusLine` at it in `~/.claude/settings.json` (use the absolute
path — `statusLine` does not expand `${CLAUDE_PLUGIN_ROOT}`):

```json
{
  "statusLine": {
    "type": "command",
    "command": "/absolute/path/to/statusline/superpowers-statusline",
    "padding": 0
  }
}
```

On Windows, point at `statusline/run-statusline.cmd` instead; it locates Git
Bash and runs the script.

The script is self-contained — bash, awk, git — so copying it to
`~/.claude/superpowers-statusline` and pointing `statusLine` there works too,
and survives plugin upgrades unchanged.

### Other harnesses

Any harness whose statusline runs a command works the same way. The script
reads the project directory from the harness's status JSON on stdin
(`.workspace.current_dir`, then `.cwd`), and falls back to the working
directory when there is no JSON — so `--dir` covers harnesses that pass
nothing at all.

## Keeping your own statusline

By default the script prints a whole line: directory, branch, then progress.
If you already have a statusline you like, ask for just the progress segment
with `--segment` and paste it into your own script:

```bash
#!/usr/bin/env bash
input=$(cat)
progress=$(printf '%s' "$input" | /path/to/superpowers-statusline --segment)
printf '%s — %s\n' "$(my-existing-statusline <<<"$input")" "$progress"
```

`--segment` prints nothing at all when there is no plan to report, so the rest
of your line stays clean.

## Which plan gets tracked

Plans are searched for in `docs/superpowers/plans/`, `docs/plans/`, and
`plans/`, relative to the current directory and to the repository root. Among
the plans that have steps or a ledger, the script picks:

1. the plan whose filename matches the current git branch —
   `docs/superpowers/plans/2026-08-28-add-widgets.md` matches branch
   `claude/add-widgets-x7f2`, the date prefix and punctuation ignored;
2. otherwise a plan with a live SDD ledger — one whose first line,
   `# SDD ledger — plan: <path>`, names that plan;
3. otherwise the most recently modified plan with checkboxes in flight (some
   ticked, some not);
4. otherwise the most recently modified plan with steps in it.

Plans with neither checkboxes nor a ledger are ignored, and so is a project
with no plans — the segment is simply empty.

Point it somewhere else with `--plan path/to/plan.md`, or set
`SUPERPOWERS_STATUSLINE_PLAN` for a whole session.

### Ledger before checkboxes

When a plan has both, the ledger wins: an SDD run closes tasks in the ledger
and never touches the plan's checkboxes, so counting boxes during such a run
would report 0% from start to finish.

Ledger identity is checked the way `subagent-driven-development` checks it. A
ledger whose first line names a different plan is that plan's progress and is
left alone, and the pre-plan-scoping flat path `.superpowers/sdd/progress.md`
is never read. The ledger is git-ignored scratch: after a `git clean -fdx` the
segment falls back to counting checkboxes.

## Options

| Option | Effect |
| --- | --- |
| `--segment` | Print only the progress segment |
| `--plan PATH` | Track this plan instead of auto-detecting one |
| `--dir PATH` | Use this project directory instead of the one on stdin |
| `--style full\|compact` | `compact` drops the plan name and task, keeping bar and counts |
| `--width N` | Progress bar width (default 10, max 40) |
| `--ascii` | ASCII bar and separators instead of Unicode |
| `--no-color` | No ANSI escapes |

Environment equivalents: `SUPERPOWERS_STATUSLINE_PLAN`,
`SUPERPOWERS_STATUSLINE_PLAN_DIRS` (colon-separated directories to search),
`SUPERPOWERS_STATUSLINE_STYLE`, `SUPERPOWERS_STATUSLINE_WIDTH`, and `NO_COLOR`.

## Troubleshooting

**Nothing shows up.** Run it by hand from the project:

```bash
statusline/superpowers-statusline --dir . --segment
```

If that prints nothing, the project has no plan with `- [ ]` checkboxes or a
ledger in a searched directory. A plan kept somewhere else needs
`SUPERPOWERS_STATUSLINE_PLAN_DIRS` or `--plan`.

**It sits at 0%.** The plan is being counted by its checkboxes and nothing is
ticking them — expected if you are running `executing-plans`, which tracks
progress in todos rather than in the plan file. Progress appears by itself
under `subagent-driven-development`, which keeps the ledger.

**The wrong plan is tracked.** Repositories accumulate finished plans. Name the
branch after the plan, or set `SUPERPOWERS_STATUSLINE_PLAN`.

**Percentages look coarse.** The bar counts steps or tasks, not effort — a
plan's units are deliberately bite-sized but not equal in size.

## Tests

```bash
tests/statusline/test-superpowers-statusline.sh
```
