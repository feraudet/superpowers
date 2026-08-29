#!/usr/bin/env bash
#
# Tests for statusline/superpowers-statusline.
set -uo pipefail

# An exported CDPATH makes cd echo the directory it landed in, which would end
# up inside these command substitutions.
CDPATH=''

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATUSLINE="$REPO_ROOT/statusline/superpowers-statusline"
SDD_WORKSPACE="$REPO_ROOT/skills/subagent-driven-development/scripts/sdd-workspace"

FAILURES=0
TEST_ROOT="$(mktemp -d)"

cleanup() {
  rm -rf "$TEST_ROOT"
}
trap cleanup EXIT

pass() {
  echo "  [PASS] $1"
}

fail() {
  echo "  [FAIL] $1"
  FAILURES=$((FAILURES + 1))
}

skip() {
  echo "  [SKIP] $1 ($2)"
}

assert_contains() {
  local description="$1" haystack="$2" needle="$3"
  case "$haystack" in
    *"$needle"*) pass "$description" ;;
    *)
      fail "$description"
      echo "    expected to contain: $needle"
      echo "    actual: $haystack"
      ;;
  esac
}

assert_not_contains() {
  local description="$1" haystack="$2" needle="$3"
  case "$haystack" in
    *"$needle"*)
      fail "$description"
      echo "    expected NOT to contain: $needle"
      echo "    actual: $haystack"
      ;;
    *) pass "$description" ;;
  esac
}

assert_equals() {
  local description="$1" actual="$2" expected="$3"
  if [ "$actual" = "$expected" ]; then
    pass "$description"
  else
    fail "$description"
    echo "    expected: '$expected'"
    echo "    actual:   '$actual'"
  fi
}

# Build a project directory with a git repo on the given branch.
make_project() {
  local name="$1" branch="${2:-main}"
  local dir="$TEST_ROOT/$name"

  mkdir -p "$dir/docs/superpowers/plans"
  git -C "$dir" init -q
  git -C "$dir" config user.email test@example.com
  git -C "$dir" config user.name Test
  git -C "$dir" checkout -q -b "$branch" 2>/dev/null
  printf 'seed\n' >"$dir/README.md"
  git -C "$dir" add README.md
  git -C "$dir" commit -qm seed
  printf '%s' "$dir"
}

# write_plan <path> <total-steps> <checked-steps> [tasks]
write_plan() {
  local path="$1" total="$2" checked="$3" tasks="${4:-1}"
  local per_task step task box

  {
    echo "# Test Plan"
    echo
    step=0
    for ((task = 1; task <= tasks; task++)); do
      echo "## Task $task: Task number $task"
      echo
      per_task=$((total / tasks))
      for ((box = 0; box < per_task; box++)); do
        step=$((step + 1))
        if [ "$step" -le "$checked" ]; then
          echo "- [x] **Step $step: done**"
        else
          echo "- [ ] **Step $step: todo**"
        fi
        echo
      done
    done
  } >"$path"
}

# write_ledger <project> <plan-basename> <plan-path-line> <complete-task-numbers...>
write_ledger() {
  local project="$1" slug="$2" plan_line="$3"
  shift 3
  local dir="$project/.superpowers/sdd/${slug}"
  local n

  mkdir -p "$dir"
  {
    echo "# SDD ledger — plan: $plan_line"
    for n in "$@"; do
      echo "Task $n: complete"
    done
  } >"$dir/progress.md"
}

run_statusline() {
  local dir="$1"
  shift
  printf '{"workspace":{"current_dir":"%s"},"model":{"display_name":"Opus"}}' "$dir" \
    | "$STATUSLINE" "$@"
}

echo "Testing superpowers-statusline"

# --- no plan -----------------------------------------------------------------
project="$(make_project no-plan)"
output="$(run_statusline "$project" --segment --no-color)"
assert_equals "no plan directory yields an empty segment" "$output" ""

output="$(run_statusline "$project" --no-color)"
assert_contains "full line still shows the project directory" "$output" "no-plan"
assert_contains "full line still shows the branch" "$output" "main"

# --- plan with no checkboxes -------------------------------------------------
project="$(make_project no-boxes)"
printf '# Notes\n\nJust prose.\n' >"$project/docs/superpowers/plans/2026-01-01-notes.md"
output="$(run_statusline "$project" --segment --no-color)"
assert_equals "plan without checkboxes is ignored" "$output" ""

# --- step counting -----------------------------------------------------------
project="$(make_project counting)"
write_plan "$project/docs/superpowers/plans/2026-01-01-add-widgets.md" 10 3 2
output="$(run_statusline "$project" --segment --no-color)"
assert_contains "reports the plan name" "$output" "add-widgets"
assert_contains "reports checked/total steps" "$output" "3/10 steps"
assert_contains "reports the percentage" "$output" "30%"
assert_contains "renders a progress bar" "$output" "▰▱"

# --- task tracking -----------------------------------------------------------
assert_contains "reports the current task" "$output" "task 1/2"
assert_contains "reports the current task title" "$output" "Task number 1"

write_plan "$project/docs/superpowers/plans/2026-01-01-add-widgets.md" 10 6 2
output="$(run_statusline "$project" --segment --no-color)"
assert_contains "advances to the task holding the next unchecked step" "$output" "task 2/2"

# --- completion --------------------------------------------------------------
write_plan "$project/docs/superpowers/plans/2026-01-01-add-widgets.md" 10 10 2
output="$(run_statusline "$project" --segment --no-color)"
assert_contains "reports 100% when every step is checked" "$output" "100%"
assert_contains "uses the done marker when every step is checked" "$output" "✓"
assert_not_contains "drops the current task once the plan is finished" "$output" "task 1/2"
assert_contains "reports finished tasks once the plan is finished" "$output" "2/2 tasks"

# --- branch matching ---------------------------------------------------------
project="$(make_project branch-match feature/add-widgets-xyz12)"
write_plan "$project/docs/superpowers/plans/2026-01-01-add-widgets.md" 10 1 1
write_plan "$project/docs/superpowers/plans/2026-02-02-other-project.md" 10 5 1
touch -t 202602020000 "$project/docs/superpowers/plans/2026-02-02-other-project.md"
touch -t 202601010000 "$project/docs/superpowers/plans/2026-01-01-add-widgets.md"
output="$(run_statusline "$project" --segment --no-color)"
assert_contains "branch name selects its plan over a newer one" "$output" "add-widgets"

# --- in-progress preference --------------------------------------------------
project="$(make_project in-progress main)"
write_plan "$project/docs/superpowers/plans/2026-01-01-started.md" 10 4 1
write_plan "$project/docs/superpowers/plans/2026-02-02-untouched.md" 10 0 1
touch -t 202602020000 "$project/docs/superpowers/plans/2026-02-02-untouched.md"
touch -t 202601010000 "$project/docs/superpowers/plans/2026-01-01-started.md"
output="$(run_statusline "$project" --segment --no-color)"
assert_contains "prefers a plan with work in flight" "$output" "started"

# --- explicit selection ------------------------------------------------------
output="$(run_statusline "$project" --segment --no-color --plan "$project/docs/superpowers/plans/2026-02-02-untouched.md")"
assert_contains "--plan overrides auto-detection" "$output" "untouched"

output="$(SUPERPOWERS_STATUSLINE_PLAN="$project/docs/superpowers/plans/2026-02-02-untouched.md" \
  run_statusline "$project" --segment --no-color)"
assert_contains "SUPERPOWERS_STATUSLINE_PLAN overrides auto-detection" "$output" "untouched"

# --- committed plans are archive ---------------------------------------------
# Repositories accumulate finished plans, and nothing ticks a plan's checkboxes
# off as the work lands, so a committed plan's checkbox state says nothing about
# whether any work is in flight. Only a plan git reports as modified or
# untracked counts as evidence — unless the branch or a ledger names it.
project="$(make_project archive main)"
write_plan "$project/docs/superpowers/plans/2026-01-01-long-done.md" 100 5 4
git -C "$project" add -A
git -C "$project" commit -qm "archive the plan"
output="$(run_statusline "$project" --segment --no-color)"
assert_equals "a committed, unmodified plan is not reported" "$output" ""

printf -- '- [x] **Step 101: a fresh tick**\n' >>"$project/docs/superpowers/plans/2026-01-01-long-done.md"
output="$(run_statusline "$project" --segment --no-color)"
assert_contains "the same plan reports once it is modified" "$output" "long-done"

git -C "$project" checkout -q -- docs/superpowers/plans/2026-01-01-long-done.md
output="$(run_statusline "$project" --segment --no-color)"
assert_equals "and goes quiet again once the edit is reverted" "$output" ""

# The branch naming a plan is evidence, committed or not.
project="$(make_project archive-branch-match feature/long-done)"
write_plan "$project/docs/superpowers/plans/2026-01-01-long-done.md" 10 3 2
git -C "$project" add -A
git -C "$project" commit -qm "archive the plan"
output="$(run_statusline "$project" --segment --no-color)"
assert_contains "a committed plan named by the branch still reports" "$output" "long-done"

# So is a ledger.
project="$(make_project archive-ledger main)"
write_plan "$project/docs/superpowers/plans/2026-01-01-under-sdd.md" 10 0 2
git -C "$project" add -A
git -C "$project" commit -qm "archive the plan"
write_ledger "$project" "2026-01-01-under-sdd" "docs/superpowers/plans/2026-01-01-under-sdd.md" 1
output="$(run_statusline "$project" --segment --no-color)"
assert_contains "a committed plan under a live ledger still reports" "$output" "1/2 tasks"

# --- custom plan directories -------------------------------------------------
project="$(make_project custom-dirs)"
mkdir -p "$project/planning"
write_plan "$project/planning/2026-01-01-custom-home.md" 4 2 1
output="$(SUPERPOWERS_STATUSLINE_PLAN_DIRS=planning run_statusline "$project" --segment --no-color)"
assert_contains "SUPERPOWERS_STATUSLINE_PLAN_DIRS is honored" "$output" "custom-home"

# --- legacy docs/plans -------------------------------------------------------
project="$(make_project legacy-dir)"
mkdir -p "$project/docs/plans"
write_plan "$project/docs/plans/2026-01-01-legacy.md" 4 1 1
output="$(run_statusline "$project" --segment --no-color)"
assert_contains "docs/plans is searched too" "$output" "legacy"

# --- subdirectory of the repo ------------------------------------------------
mkdir -p "$project/src/deep"
output="$(run_statusline "$project/src/deep" --segment --no-color)"
assert_contains "plans are found from a subdirectory of the repo" "$output" "legacy"

# --- harness JSON shapes -----------------------------------------------------
project="$(make_project json-shapes)"
write_plan "$project/docs/superpowers/plans/2026-01-01-json.md" 4 1 1
output="$(printf '{"cwd":"%s"}' "$project" | "$STATUSLINE" --segment --no-color)"
assert_contains "falls back to .cwd when workspace is absent" "$output" "json"

output="$(printf 'not json at all' | "$STATUSLINE" --segment --no-color --dir "$project")"
assert_contains "--dir wins over unparseable stdin" "$output" "json"

output="$("$STATUSLINE" --segment --no-color --dir "$project" </dev/null)"
assert_contains "works with no stdin at all" "$output" "json"

# --- SDD ledger --------------------------------------------------------------
# subagent-driven-development never ticks the plan's checkboxes; it records
# "Task N: complete" in .superpowers/sdd/<plan>/progress.md. That ledger is the
# progress an SDD run actually produces, so it wins over the checkboxes.
project="$(make_project ledger)"
plan="$project/docs/superpowers/plans/2026-01-01-ledger-plan.md"
write_plan "$plan" 12 0 4
write_ledger "$project" "2026-01-01-ledger-plan" "docs/superpowers/plans/2026-01-01-ledger-plan.md" 1 2
output="$(run_statusline "$project" --segment --no-color)"
assert_contains "counts tasks the ledger closed" "$output" "2/4 tasks"
assert_contains "reports ledger progress as a percentage" "$output" "50%"
assert_contains "names the first task the ledger has not closed" "$output" "task 3/4"
assert_not_contains "does not report unticked checkboxes as steps" "$output" "0/12 steps"

write_ledger "$project" "2026-01-01-ledger-plan" "docs/superpowers/plans/2026-01-01-ledger-plan.md" 1 2 3 4
output="$(run_statusline "$project" --segment --no-color)"
assert_contains "a ledger with every task closed reads 100%" "$output" "100%"
assert_contains "a finished ledger uses the done marker" "$output" "✓"

# The completion line SDD actually writes carries a commit-range parenthetical.
project="$(make_project ledger-real-format)"
plan="$project/docs/superpowers/plans/2026-01-01-real-format.md"
write_plan "$plan" 8 0 4
mkdir -p "$project/.superpowers/sdd/2026-01-01-real-format"
{
  echo "# SDD ledger — plan: docs/superpowers/plans/2026-01-01-real-format.md"
  echo "- Task 1: complete (commits a1b2c3d..e4f5a6b, review clean)"
  echo "- Task 2: complete (commits e4f5a6b..c7d8e9f, 2 parked)"
} >"$project/.superpowers/sdd/2026-01-01-real-format/progress.md"
output="$(run_statusline "$project" --segment --no-color)"
assert_contains "reads SDD's real completion lines" "$output" "2/4 tasks"

# A plan with no checkboxes at all is still reportable once it has a ledger.
project="$(make_project ledger-no-boxes)"
plan="$project/docs/superpowers/plans/2026-01-01-headings-only.md"
{
  echo "# Headings Only"
  echo
  echo "## Task 1: First"
  echo
  echo "## Task 2: Second"
} >"$plan"
write_ledger "$project" "2026-01-01-headings-only" "$plan" 1
output="$(run_statusline "$project" --segment --no-color)"
assert_contains "a checkbox-free plan with a ledger still reports" "$output" "1/2 tasks"

# A ledger whose first line names a different plan belongs to that plan.
project="$(make_project ledger-mismatch)"
plan="$project/docs/superpowers/plans/2026-01-01-mine.md"
write_plan "$plan" 4 1 2
mkdir -p "$project/.superpowers/sdd/2026-01-01-mine"
{
  echo "# SDD ledger — plan: docs/superpowers/plans/2026-01-01-someone-else.md"
  echo "Task 1: complete"
  echo "Task 2: complete"
} >"$project/.superpowers/sdd/2026-01-01-mine/progress.md"
output="$(run_statusline "$project" --segment --no-color)"
assert_contains "a ledger naming another plan is ignored" "$output" "1/4 steps"

# The pre-plan-scoping flat ledger path is another plan's progress, not ours.
project="$(make_project ledger-flat)"
plan="$project/docs/superpowers/plans/2026-01-01-flat.md"
write_plan "$plan" 4 1 2
mkdir -p "$project/.superpowers/sdd"
printf '# SDD ledger — plan: %s\nTask 1: complete\nTask 2: complete\n' "$plan" \
  >"$project/.superpowers/sdd/progress.md"
output="$(run_statusline "$project" --segment --no-color)"
assert_contains "the legacy flat ledger path is not read" "$output" "1/4 steps"

# The workspace path is the skill's to define: resolve it with SDD's own script
# rather than a copy of its logic, so a change there fails this test.
project="$(make_project ledger-via-sdd-script)"
plan="$project/docs/superpowers/plans/2026-01-01-via-script.md"
write_plan "$plan" 9 0 3
workspace="$(cd "$project" && "$SDD_WORKSPACE" docs/superpowers/plans/2026-01-01-via-script.md)"
{
  echo "# SDD ledger — plan: docs/superpowers/plans/2026-01-01-via-script.md"
  echo "- Task 1: complete (commits 1111111..2222222, review clean)"
} >"$workspace/progress.md"
output="$(run_statusline "$project" --segment --no-color)"
assert_contains "reads the ledger where sdd-workspace puts it" "$output" "1/3 tasks"

# SDD runs in a worktree, where the ledger sits under that worktree's root.
project="$(make_project ledger-worktree)"
worktree="$TEST_ROOT/ledger-worktree-linked"
git -C "$project" worktree add -q -b sdd/widgets "$worktree" 2>/dev/null
mkdir -p "$worktree/docs/superpowers/plans"
write_plan "$worktree/docs/superpowers/plans/2026-01-01-in-worktree.md" 6 0 3
write_ledger "$worktree" "2026-01-01-in-worktree" "docs/superpowers/plans/2026-01-01-in-worktree.md" 1 2
output="$(run_statusline "$worktree" --segment --no-color)"
assert_contains "finds the ledger inside a linked worktree" "$output" "2/3 tasks"

# With no branch match, a plan under a live ledger beats a plan with ticked boxes.
project="$(make_project ledger-priority)"
write_plan "$project/docs/superpowers/plans/2026-01-01-ticked.md" 10 4 2
write_plan "$project/docs/superpowers/plans/2026-02-02-under-sdd.md" 10 0 2
write_ledger "$project" "2026-02-02-under-sdd" "docs/superpowers/plans/2026-02-02-under-sdd.md" 1
touch -t 202601010000 "$project/docs/superpowers/plans/2026-01-01-ticked.md"
touch -t 202602020000 "$project/docs/superpowers/plans/2026-02-02-under-sdd.md"
output="$(run_statusline "$project" --segment --no-color)"
assert_contains "a plan with a live ledger outranks one with ticked boxes" "$output" "under-sdd"

# --- colors ------------------------------------------------------------------
project="$(make_project rendering)"
write_plan "$project/docs/superpowers/plans/2026-01-01-json.md" 4 1 1

output="$(run_statusline "$project" --segment --no-color)"
assert_not_contains "--no-color emits no escape sequences" "$output" $'\033'

output="$(NO_COLOR=1 run_statusline "$project" --segment)"
assert_not_contains "NO_COLOR emits no escape sequences" "$output" $'\033'

output="$(run_statusline "$project" --segment)"
assert_contains "colors are on by default" "$output" $'\033'

# --- styles ------------------------------------------------------------------
output="$(run_statusline "$project" --segment --no-color --style compact)"
assert_not_contains "compact style drops the plan name" "$output" "json"
assert_contains "compact style keeps the counts" "$output" "1/4"

output="$(run_statusline "$project" --segment --no-color --ascii)"
assert_contains "ascii style uses ascii bar characters" "$output" "#--"
assert_not_contains "ascii style avoids unicode" "$output" "▰"

output="$(run_statusline "$project" --segment --no-color --width 4)"
assert_contains "--width 4 renders a four-cell bar" "$output" "▰▱▱▱ 25%"

output="$(run_statusline "$project" --segment --no-color)"
assert_contains "the default bar is ten cells wide" "$output" "▰▰▰▱▱▱▱▱▱▱ 25%"

# --- stdin that never closes -------------------------------------------------
# A harness writes its JSON and closes stdin. A stdin that is neither a tty nor
# closed — a manual run from inside a script, cron, a harness that leaves its
# own stdin open — must not hang the statusline.
project="$(make_project idle-stdin)"
write_plan "$project/docs/superpowers/plans/2026-01-01-idle.md" 4 1 1
if command -v timeout >/dev/null 2>&1; then
  fifo="$TEST_ROOT/idle-stdin.fifo"
  mkfifo "$fifo"

  sleep 30 >"$fifo" &
  holder=$!
  output="$(timeout 10 "$STATUSLINE" --segment --no-color --dir "$project" <"$fifo")" || output="TIMED OUT"
  kill "$holder" 2>/dev/null
  wait "$holder" 2>/dev/null
  assert_contains "an open, idle stdin does not hang the statusline" "$output" "idle"

  sleep 30 >"$fifo" &
  holder=$!
  output="$(timeout 10 "$STATUSLINE" --segment --no-color \
    --plan "$project/docs/superpowers/plans/2026-01-01-idle.md" <"$fifo")" || output="TIMED OUT"
  kill "$holder" 2>/dev/null
  wait "$holder" 2>/dev/null
  assert_contains "an open, idle stdin gives up rather than blocking" "$output" "idle"

  rm -f "$fifo"
else
  skip "an open, idle stdin does not hang the statusline" "no timeout command"
fi

# --- resilience --------------------------------------------------------------
project="$(make_project resilience)"
write_plan "$project/docs/superpowers/plans/2026-01-01-json.md" 4 1 1

output="$(run_statusline "$project" --segment --no-color --width bogus)"
assert_contains "a bogus width falls back to the default" "$output" "json"

if "$STATUSLINE" --nope </dev/null >/dev/null 2>&1; then
  fail "unknown options exit non-zero"
else
  pass "unknown options exit non-zero"
fi

help_text="$("$STATUSLINE" --help </dev/null)"
assert_contains "--help documents the options" "$help_text" "--segment"
assert_contains "--help reaches the end of the header" "$help_text" "NO_COLOR"

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "All tests passed."
  exit 0
fi
echo "$FAILURES test(s) failed."
exit 1
