#!/usr/bin/env bash
set -euo pipefail

# Runs the config's `verify` through its `exec` prefix and, when it is green,
# records the hash of the tree it checked: commit.sh and integrate.sh refuse
# any other tree. A check changes no file: a run that changed one git does
# not ignore is red, whatever its exit. Every run, green or red, goes to the
# clone's run log, which the measures read.
#
#   verify.sh [--lines <n>]
#
# The full output goes to a file; the terminal gets its last lines on red
# (80 by default) and a single line on green, so that the caller needs no
# pipe. On a task's branch, a red run adds to the journal's red streak and
# the third one in a row says to stop and ask the human. With an empty
# `verify` in the config, nothing runs and the tree is recorded as unchecked.

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
state="$(state_dir)"
output="$state/verify-output.txt"
branch="$(current_branch)"
tree="$(work_tree_hash)"

# A project with no check of its own: the tree is recorded, so that commits
# still take only the tree the step looked at, and the run log says that
# nothing was checked.
if [[ -z "$command" ]]; then
  printf '%s\t%s\t%s\t%s\t%s\n' "$(now)" "${branch:-HEAD}" "$tree" none 0 >>"$state/runs.log"
  printf '%s %s %s\n' "$tree" "${branch:-HEAD}" "$(now)" >"$(verified_file)"
  echo "verify: the config has no 'verify' command, nothing checked; tree ${tree:0:12} recorded."
  exit 0
fi

started="$(date +%s)"

set +e
run_project "$command" >"$output" 2>&1
status=$?
set -e
seconds=$(($(date +%s) - started))

# A --fix, a snapshot written, a report git does not ignore: the tree the
# check looked at is no longer the one in place.
changed=""
after="$(work_tree_hash)"
[[ "$after" == "$tree" ]] || changed="$(git diff --name-only --no-renames "$tree" "$after")"

result=red
((status == 0)) && [[ -z "$changed" ]] && result=green
printf '%s\t%s\t%s\t%s\t%s\n' "$(now)" "${branch:-HEAD}" "$tree" "$result" "$seconds" >>"$state/runs.log"

task=0
if [[ -f "$JOURNAL_FILE" && -n "$branch" && "$branch" != "$(cfg main)" ]]; then
  task=1
fi

if [[ "$result" == green ]]; then
  printf '%s %s %s\n' "$tree" "${branch:-HEAD}" "$(now)" >"$(verified_file)"
  ((task)) && bash "$OVERLOAD_SCRIPTS/journal.sh" set verify_red_streak 0
  echo "verify: green in ${seconds}s, tree ${tree:0:12} recorded (full output: $output)."
  exit 0
fi

rm -f "$(verified_file)"
if ((status != 0)); then
  tail -n "$lines" "$output"
  echo
fi
if [[ -n "$changed" ]]; then
  echo "verify: red (exit $status) in ${seconds}s: the check changed files git does not ignore, which a check never does (a --fix, a snapshot written, a report not ignored). They stay as it left them:"
  printf '%s\n' "$changed" | sed 's/^/  /'
  echo "Full output: $output."
else
  echo "verify: red (exit $status) in ${seconds}s; full output: $output."
fi
if ((task)); then
  streak="$(bash "$OVERLOAD_SCRIPTS/journal.sh" inc verify_red_streak)"
  if ((streak >= 3)); then
    echo "verify: red $streak times in a row. Stop and ask the human: retry with their guidance, or stop the task (skip is not available on a red verify)."
  fi
fi
exit 1
