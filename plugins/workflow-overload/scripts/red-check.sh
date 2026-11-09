#!/usr/bin/env bash
set -euo pipefail

# Checks that the recorded suite fails for the right reason before any code
# is written: every recorded test runs, and fails on an assertion or on a
# stub's NotImplemented, not on an import or a load error (junit.py). Runs
# the config's `test_files`, its `{files}` replaced by the recorded test
# files, through the `exec` prefix; the command prints JUnit XML.
#
#   red-check.sh

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
in_project
require_config
on_task_branch

command="$(cfg test_files)"
[[ -n "$command" ]] || die "the config has no 'test_files': the command that runs given test files and prints JUnit XML, with {files} where the files go."
[[ "$command" == *'{files}'* ]] || die "the config's test_files has no {files} placeholder."

mapfile -t files < <(bash "$OVERLOAD_SCRIPTS/suite.sh" files)
((${#files[@]})) || die "no suite recorded on this branch: the test-author records it with suite.sh record."
bash "$OVERLOAD_SCRIPTS/suite.sh" check

quoted=""
for file in "${files[@]}"; do
  quoted+="$(printf '%q' "$file") "
done
state="$(state_dir)"
output="$state/red-check-output.txt"
set +e
run_project "${command//\{files\}/${quoted% }}" >"$output" 2>&1
set -e

status=0
python3 "$OVERLOAD_SCRIPTS/junit.py" --types "$(cfg red_types)" "$output" "${files[@]}" || status=$?
printf '%s\t%s\t%s\t%s\n' "$(now)" "$(current_branch)" "red-check" "$([[ $status == 0 ]] && echo valid || echo invalid)" >>"$state/runs.log"
((status == 2)) && echo "The runner's output is in $output."
exit "$status"
