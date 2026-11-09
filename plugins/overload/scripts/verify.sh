#!/usr/bin/env bash
set -euo pipefail

# Runs the config's `verify` through its `exec` prefix and, when it is green,
# records the hash of the tree it checked: commit.sh and integrate.sh refuse
# any other tree. Every run, green or red, goes to the clone's run log, which
# the measures read.
#
#   verify.sh [--lines <n>]
#
# The full output goes to a file; the terminal gets its last lines on red
# (80 by default) and a single line on green, so that the caller needs no
# pipe. On a task's branch, a red run adds to the journal's red streak and
# the third one in a row says to stop and ask the human.

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
in_project
require_config

lines=80
if [[ "${1:-}" == --lines ]]; then
  [[ "${2:-}" =~ ^[0-9]+$ ]] || die "--lines takes a number."
  lines="$2"
fi

command="$(cfg verify)"
[[ -n "$command" ]] || die "the config has no 'verify' command."

state="$(state_dir)"
output="$state/verify-output.txt"
branch="$(current_branch)"
tree="$(work_tree_hash)"
started="$(date +%s)"

set +e
run_project "$command" >"$output" 2>&1
status=$?
set -e
seconds=$(($(date +%s) - started))

result=red
((status == 0)) && result=green
printf '%s\t%s\t%s\t%s\t%s\n' "$(now)" "${branch:-HEAD}" "$tree" "$result" "$seconds" >>"$state/runs.log"

task=0
if [[ -f "$JOURNAL_FILE" && -n "$branch" && "$branch" != "$(cfg main)" ]]; then
  task=1
fi

if ((status == 0)); then
  printf '%s %s %s\n' "$tree" "${branch:-HEAD}" "$(now)" >"$(verified_file)"
  ((task)) && bash "$OVERLOAD_SCRIPTS/journal.sh" set verify_red_streak 0
  echo "verify: green in ${seconds}s, tree ${tree:0:12} recorded (full output: $output)."
  exit 0
fi

rm -f "$(verified_file)"
tail -n "$lines" "$output"
echo
echo "verify: red (exit $status) in ${seconds}s; full output: $output."
if ((task)); then
  streak="$(bash "$OVERLOAD_SCRIPTS/journal.sh" inc verify_red_streak)"
  if ((streak >= 3)); then
    echo "verify: red $streak times in a row. Stop and ask the human: retry with their guidance, or stop the task (skip is not available on a red verify)."
  fi
fi
exit 1
