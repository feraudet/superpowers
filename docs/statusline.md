# Project progress in your statusline

Superpowers plans track work as checkboxes: `writing-plans` produces a plan
under `docs/superpowers/plans/`, and `executing-plans` /
`subagent-driven-development` tick the boxes off as tasks land. That file is
the project's progress — but you only see it when you open it.

`statusline/superpowers-statusline` turns that plan into a statusline segment,
so the harness shows how far the current project has gotten on every turn:

```
superpowers · claude/add-widgets · ⚡ add-widgets ▰▰▰▰▰▰▱▱▱▱ 61% · task 4/7: Wire the CLI flag · 22/36 steps
```

- `⚡ add-widgets` — the plan being tracked (`✓` once every step is checked)
- `▰▰▰▰▰▰▱▱▱▱ 61%` — checked steps as a share of all steps in the plan
- `task 4/7: …` — the task holding the next unchecked step
- `22/36 steps` — checked/total steps

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
the plans that contain checkboxes, the script picks:

1. the plan whose filename matches the current git branch —
   `docs/superpowers/plans/2026-08-28-add-widgets.md` matches branch
   `claude/add-widgets-x7f2`, the date prefix and punctuation ignored;
2. otherwise the most recently modified plan with work in flight (some steps
   checked, some not);
3. otherwise the most recently modified plan with steps in it.

Plans with no checkboxes are ignored, and so is a project with no plans — the
segment is simply empty.

Point it somewhere else with `--plan path/to/plan.md`, or set
`SUPERPOWERS_STATUSLINE_PLAN` for a whole session.

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

If that prints nothing, the project has no plan file with `- [ ]` checkboxes in
a searched directory. Plans written by `writing-plans` always do; a plan kept
elsewhere needs `SUPERPOWERS_STATUSLINE_PLAN_DIRS` or `--plan`.

**The wrong plan is tracked.** Repositories accumulate finished plans. Name the
branch after the plan, or set `SUPERPOWERS_STATUSLINE_PLAN`.

**Percentages look coarse.** The bar counts steps, not effort — a plan's steps
are deliberately bite-sized but not equal in size.

## Tests

```bash
tests/statusline/test-superpowers-statusline.sh
```
