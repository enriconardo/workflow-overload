#!/usr/bin/env bash
set -euo pipefail

# Checks that the recorded suite fails for the right reason before any code
# is written: every recorded test runs, and fails on an assertion or on a
# stub's NotImplemented, not on an import or a load error (junit.py). Runs
# the config's `run_tests`, its `{files}` replaced by the recorded test
# files; the command prints JUnit XML.
#
# A recorded file that exists in HEAD holds tests from before the chunk,
# which may pass. Their names come from a first run of those files as HEAD
# has them, put in place for that run only.
#
#   red-check.sh                 the suite against the working tree
#   red-check.sh --without-code  the suite against the source as it was when
#                                the suite last had a valid red: HEAD plus
#                                the stubs, or HEAD alone when there was
#                                none. For a suite recorded again after the
#                                code was written (a test reported wrong).
#                                The working tree is put back afterwards.
#
# A valid red leaves the stubs' state in refs/overload/base/<branch>, which
# integrate.sh removes with the suite's records.
#
# With an empty `run_tests` in the config, the check is skipped and logged.

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
in_project
require_config
on_task_branch

without_code=0
case "${1:-}" in
  "") ;;
  --without-code) without_code=1 ;;
  *) die "usage: red-check.sh [--without-code]" ;;
esac

command="$(cfg run_tests)"
if [[ -z "$command" ]]; then
  printf '%s\t%s\t%s\t%s\n' "$(now)" "$(current_branch)" "red-check" skipped >>"$(state_dir)/runs.log"
  echo "red check skipped: the config has no 'run_tests', the command that runs given test files and prints JUnit XML."
  exit 0
fi
[[ "$command" == *'{files}'* ]] || die "the config's run_tests has no {files} placeholder."

mapfile -t files < <(bash "$OVERLOAD_SCRIPTS/suite.sh" files)
((${#files[@]})) || die "no suite recorded on this branch: the test-author records it with suite.sh record."
bash "$OVERLOAD_SCRIPTS/suite.sh" check

# A test file the suite deletes has no test to run, and a runner given its
# path reports nothing for it, or fails.
present=()
for file in "${files[@]}"; do
  if [[ -f "$file" ]]; then
    present+=("$file")
  else
    echo "$file: deleted by the suite, not run"
  fi
done
if ((${#present[@]} == 0)); then
  printf '%s\t%s\t%s\t%s\n' "$(now)" "$(current_branch)" "red-check" valid >>"$(state_dir)/runs.log"
  echo "red check: the suite only deletes test files, nothing to run."
  exit 0
fi
files=("${present[@]}")

branch="$(current_branch)"
base_ref="refs/overload/base/$branch"

# The tree of HEAD with every file of the working tree that is not a test:
# the source as it stands, stubs and code alike.
source_tree() {
  local index tree spec
  local -a excludes=()
  while IFS= read -r spec; do
    [[ -n "$spec" ]] && excludes+=(":(exclude,glob)${spec#:(glob)}")
  done < <(tests_pathspecs)
  index="$(mktemp)"
  GIT_INDEX_FILE="$index" git read-tree HEAD
  GIT_INDEX_FILE="$index" git add -A -- . ":(exclude).workflow" "${excludes[@]}"
  tree="$(GIT_INDEX_FILE="$index" git write-tree)"
  rm -f "$index"
  printf '%s\n' "$tree"
}

# --without-code: the source files go back to the base tree for the run, and
# come back whatever happens. A file the working tree has and the base lacks
# waits in a copy; one the base has and the working tree lacks is made and
# removed again.
kept="" kept_files=() made_files=()
restore_code() {
  local file
  for file in ${kept_files[@]+"${kept_files[@]}"}; do
    mkdir -p -- "$(dirname -- "$file")"
    cp -p -- "$kept/$file" "$file"
  done
  for file in ${made_files[@]+"${made_files[@]}"}; do
    rm -f -- "$file"
  done
  kept_files=() made_files=()
  [[ -z "$kept" ]] || rm -rf -- "$kept"
  kept=""
}
trap restore_code EXIT

if ((without_code)); then
  base_tree="$(git rev-parse 'HEAD^{tree}')"
  if git rev-parse -q --verify "$base_ref" >/dev/null && [[ "$(git rev-parse "$base_ref^")" == "$(git rev-parse HEAD)" ]]; then
    base_tree="$(git rev-parse "$base_ref^{tree}")"
  fi
  kept="$(mktemp -d)"
  while IFS=$'\t' read -r change file; do
    [[ -n "$file" ]] || continue
    if [[ "$change" != D ]]; then
      mkdir -p -- "$kept/$(dirname -- "$file")"
      cp -p -- "$file" "$kept/$file"
      kept_files+=("$file")
    else
      made_files+=("$file")
    fi
    if git cat-file -e "$base_tree:$file" 2>/dev/null; then
      mkdir -p -- "$(dirname -- "$file")"
      git cat-file blob "$base_tree:$file" >"$file"
    else
      rm -f -- "$file"
    fi
  done < <(git diff --name-status --no-renames "$base_tree" "$(source_tree)")
  echo "red check without the code: the source files are as they were at the last valid red."
fi

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

# Saves what the command printed, through a pipe: a report written to
# /dev/stdout (pytest --junitxml) opens a file anew, truncating it and
# writing over the runner's other lines, but a pipe keeps both in order.
save_run() {
  local into="$1"
  shift
  run_files "$@" 2>&1 | cat >"$into"
}

state="$(state_dir)"
output="$state/red-check-output.txt"
existing="$state/red-check-existing.txt"
: >"$existing"

old=()
for file in "${files[@]}"; do
  git cat-file -e "HEAD:$file" 2>/dev/null && old+=("$file")
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
  trap 'restore; restore_code' EXIT
  for file in "${old[@]}"; do
    mkdir -p -- "$backup/$(dirname -- "$file")"
    cp -- "$file" "$backup/$file"
    git show "HEAD:$file" >"$file"
  done
  save_run "$state/red-check-head.txt" "${old[@]}"
  restore
  trap restore_code EXIT
  python3 "$OVERLOAD_SCRIPTS/junit.py" --list "$state/red-check-head.txt" "${old[@]}" >"$existing" || true
fi

save_run "$output" "${files[@]}"
restore_code
trap - EXIT

status=0
rm -f "$state/red-check-green.txt"
python3 "$OVERLOAD_SCRIPTS/junit.py" --types "$(cfg red_types)" --existing "$existing" --green "$state/red-check-green.txt" "$output" "${files[@]}" || status=$?
printf '%s\t%s\t%s\t%s\n' "$(now)" "$branch" "red-check" "$([[ $status == 0 ]] && echo valid || echo invalid)" >>"$state/runs.log"
if ((status == 0 && !without_code)); then
  git update-ref "$base_ref" "$(git commit-tree "$(source_tree)" -p HEAD -m "stubs state of $branch")"
fi
((status == 2)) && echo "The runner's output is in $output."
exit "$status"
