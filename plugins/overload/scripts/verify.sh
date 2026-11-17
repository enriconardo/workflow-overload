#!/usr/bin/env bash
set -euo pipefail

# Runs the config's `check` and, when it is green, records the hash of the
# tree it checked: commit.sh and integrate.sh refuse any other tree. A check
# changes no file: a run that changed one git does not ignore is red,
# whatever its exit.
#
#   verify.sh [--integrate] [--lines <n>]
#
# On a task's branch with recorded suites and a `run_tests`, the recorded
# test files run too, after a green check, and must all pass: a chunk's tests
# that `check` leaves out (too slow, another folder) still run at every
# verify of the chunks that follow.
#
# --integrate runs the config's `check_integrate` too, after a green check:
# the slow but local tests, once per task before the final review and again
# after a sync with main. Green, it records the branch and main's commit for
# integrate.sh.
#
# The full output goes to a file; the terminal gets its last lines on red
# (80 by default) and a single line on green, so that the caller needs no
# pipe. On a task's branch, a red run adds to the journal's red streak and
# the third one in a row says to stop and ask the human. With an empty
# `check` in the config, nothing runs and the tree is recorded as unchecked.

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
in_project
require_config

lines=80
integrate=0
while (($#)); do
  case "$1" in
    --lines)
      [[ "${2:-}" =~ ^[0-9]+$ ]] || die "--lines takes a number."
      lines="$2"
      shift 2
      ;;
    --integrate)
      integrate=1
      shift
      ;;
    *) die "usage: verify.sh [--integrate] [--lines <n>]" ;;
  esac
done

command="$(cfg check)"
run_tests="$(cfg run_tests)"
slow=""
((integrate)) && slow="$(cfg check_integrate)"
state="$(state_dir)"
output="$state/verify-output.txt"
branch="$(current_branch)"
tree="$(work_tree_hash)"

task=0
if [[ -f "$JOURNAL_FILE" && -n "$branch" && "$branch" != "$(cfg main)" ]]; then
  task=1
fi

# What ran, for the last line, and what did not, said once.
ran=()
notes=""
[[ -n "$command" ]] || notes+="; the config has no 'check' command, nothing checked"
((integrate)) && [[ -z "$slow" ]] && notes+="; the config has no 'check_integrate', nothing more to run"

started="$(date +%s)"
status=0
failed=""
: >"$output"
set +e
if [[ -n "$command" ]]; then
  ran+=(check)
  run_project "$command" >>"$output" 2>&1
  status=$?
  ((status == 0)) || failed=check
fi
suite=()
if ((status == 0 && task)) && [[ -n "$run_tests" ]]; then
  while IFS= read -r file; do
    [[ -n "$file" && -f "$file" ]] && suite+=("$file")
  done < <(bash "$OVERLOAD_SCRIPTS/suite.sh" files)
fi
if ((${#suite[@]})); then
  ran+=("the recorded tests")
  echo "== the recorded tests: ${suite[*]}" >>"$output"
  # Through a pipe, as red-check.sh: a report written to /dev/stdout would
  # truncate the file and write over the runner's other lines.
  run_project "$(with_files "$run_tests" "${suite[@]}")" 2>&1 | cat >"$state/verify-suite-output.txt"
  runner=$?
  python3 "$OVERLOAD_SCRIPTS/junit.py" --passes "$state/verify-suite-output.txt" "${suite[@]}" >>"$output"
  status=$?
  if ((status == 0 && runner != 0)); then
    echo "the runner exited $runner though every test passed (output: $state/verify-suite-output.txt)" >>"$output"
    status=$runner
  fi
  ((status == 0)) || failed="the recorded tests"
fi
if ((status == 0)) && [[ -n "$slow" ]]; then
  ran+=(check_integrate)
  echo "== check_integrate" >>"$output"
  run_project "$slow" >>"$output" 2>&1
  status=$?
  ((status == 0)) || failed=check_integrate
fi
set -e
seconds=$(($(date +%s) - started))

# A --fix, a snapshot written, a report git does not ignore: the tree the
# check looked at is no longer the one in place.
changed=""
after="$(work_tree_hash)"
[[ "$after" == "$tree" ]] || changed="$(git diff --name-only --no-renames "$tree" "$after")"

if ((status == 0)) && [[ -z "$changed" ]]; then
  printf '%s %s %s\n' "$tree" "${branch:-HEAD}" "$(now)" >"$(verified_file)"
  if ((integrate)); then
    printf '%s %s %s %s\n' "$tree" "${branch:-HEAD}" "$(now)" \
      "$(git rev-parse -q --verify "refs/heads/$(cfg main)" || echo none)" >"$(integrated_file)"
  fi
  ((task)) && bash "$OVERLOAD_SCRIPTS/journal.sh" set verify_red_streak 0
  if ((${#ran[@]})); then
    printf -v what '%s, ' "${ran[@]}"
    echo "verify: green in ${seconds}s (${what%, })${notes}; tree ${tree:0:12} recorded (full output: $output)."
  else
    echo "verify: ${notes#; }; tree ${tree:0:12} recorded."
  fi
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
  echo "verify: red (exit $status) in ${seconds}s on ${failed}; full output: $output."
fi
if ((task)); then
  streak="$(bash "$OVERLOAD_SCRIPTS/journal.sh" inc verify_red_streak)"
  if ((streak >= 3)); then
    echo "verify: red $streak times in a row. Stop and ask the human: retry with their guidance, or stop the task (skip is not available on a red verify)."
  fi
fi
exit 1
