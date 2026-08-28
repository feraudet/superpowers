#!/usr/bin/env bash
#
# Tests for statusline/superpowers-statusline.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATUSLINE="$REPO_ROOT/statusline/superpowers-statusline"

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

# --- colors ------------------------------------------------------------------
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

# --- resilience --------------------------------------------------------------
output="$(run_statusline "$project" --segment --no-color --width bogus)"
assert_contains "a bogus width falls back to the default" "$output" "json"

if "$STATUSLINE" --nope </dev/null >/dev/null 2>&1; then
  fail "unknown options exit non-zero"
else
  pass "unknown options exit non-zero"
fi

if "$STATUSLINE" --help </dev/null | grep -q -- "--segment"; then
  pass "--help documents the options"
else
  fail "--help documents the options"
fi

echo
if [ "$FAILURES" -eq 0 ]; then
  echo "All tests passed."
  exit 0
fi
echo "$FAILURES test(s) failed."
exit 1
