#!/usr/bin/env bash
set -euo pipefail

# Checks that the recorded suite fails for the right reason before any code
# is written: every recorded test runs, and fails on an assertion or on a
# stub's NotImplemented, not on an import or a load error (junit.py). Runs
# the config's `test_files`, its `{files}` replaced by the recorded test
# files, through the `exec` prefix; the command prints JUnit XML.
#
# A recorded file that exists in HEAD holds tests from before the chunk,
# which may pass. Their names come from a first run of those files as HEAD
# has them, put in place for that run only.
#
#   red-check.sh
#
# With an empty `test_files` in the config, the check is skipped and logged.

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
in_project
require_config
on_task_branch

command="$(cfg test_files)"
if [[ -z "$command" ]]; then
  printf '%s\t%s\t%s\t%s\n' "$(now)" "$(current_branch)" "red-check" skipped >>"$(state_dir)/runs.log"
  echo "red check skipped: the config has no 'test_files', the command that runs given test files and prints JUnit XML."
  exit 0
fi
[[ "$command" == *'{files}'* ]] || die "the config's test_files has no {files} placeholder."

mapfile -t files < <(bash "$OVERLOAD_SCRIPTS/suite.sh" files)
((${#files[@]})) || die "no suite recorded on this branch: the test-author records it with suite.sh record."
bash "$OVERLOAD_SCRIPTS/suite.sh" check

# Runs the command with {files} replaced by the given files, quoted.
run_files() {
  local quoted="" file
  for file in "$@"; do
    quoted+="$(printf '%q' "$file") "
  done
  set +e
  run_project "${command//\{files\}/${quoted% }}"
  set -e
}

state="$(state_dir)"
output="$state/red-check-output.txt"
existing="$state/red-check-existing.txt"
: >"$existing"

old=()
for file in "${files[@]}"; do
  [[ -f "$file" ]] && git cat-file -e "HEAD:$file" 2>/dev/null && old+=("$file")
done
if ((${#old[@]})); then
  # The recorded versions wait in a copy, put back whatever happens.
  backup="$(mktemp -d)"
  restore() {
    local file
    for file in "${old[@]}"; do
      cp -- "$backup/$file" "$file"
    done
    rm -rf -- "$backup"
  }
  trap restore EXIT
  for file in "${old[@]}"; do
    mkdir -p -- "$backup/$(dirname -- "$file")"
    cp -- "$file" "$backup/$file"
    git show "HEAD:$file" >"$file"
  done
  run_files "${old[@]}" >"$state/red-check-head.txt" 2>&1
  restore
  trap - EXIT
  python3 "$OVERLOAD_SCRIPTS/junit.py" --list "$state/red-check-head.txt" "${old[@]}" >"$existing" || true
fi

run_files "${files[@]}" >"$output" 2>&1

status=0
rm -f "$state/red-check-green.txt"
python3 "$OVERLOAD_SCRIPTS/junit.py" --types "$(cfg red_types)" --existing "$existing" --green "$state/red-check-green.txt" "$output" "${files[@]}" || status=$?
printf '%s\t%s\t%s\t%s\n' "$(now)" "$(current_branch)" "red-check" "$([[ $status == 0 ]] && echo valid || echo invalid)" >>"$state/runs.log"
((status == 2)) && echo "The runner's output is in $output."
exit "$status"
