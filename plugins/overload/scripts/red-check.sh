#!/usr/bin/env bash
set -euo pipefail

# Checks that the recorded suite fails for the right reason before any code
# is written: every recorded test runs, and fails on an assertion or on a
# stub's NotImplemented, not on an import or a load error (junit.py). Runs
# the config's `run_tests`, its `{files}` replaced by the recorded test
# files; the command prints JUnit XML. The files of `integrate_tests_glob`,
# which `check` leaves out, run through `run_integrate_tests` instead, and
# both runs are judged as one.
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
# A file whose command is empty in the config is skipped, and said so; with
# nothing left to run, the whole check is skipped, and logged.

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
  echo "red check: the suite only deletes test files, nothing to run."
  exit 0
fi

# Each file runs through the command of its glob: `run_tests`, or
# `run_integrate_tests` for those `check` leaves out.
declare -A is_outside=()
while IFS= read -r file; do
  is_outside["$file"]=1
done < <(outside_check "${present[@]}")
inside=() outside=()
for file in "${present[@]}"; do
  if [[ -n "${is_outside[$file]:-}" ]]; then outside+=("$file"); else inside+=("$file"); fi
done
keys=() files=()
declare -A command_of=()
for key in run_tests run_integrate_tests; do
  if [[ "$key" == run_tests ]]; then group=(${inside[@]+"${inside[@]}"}); else group=(${outside[@]+"${outside[@]}"}); fi
  ((${#group[@]})) || continue
  command="$(cfg "$key")"
  if [[ -z "$command" ]]; then
    if [[ "$key" == run_tests && ${#outside[@]} -eq 0 ]]; then
      echo "red check skipped: the config has no 'run_tests', the command that runs given test files and prints JUnit XML."
      exit 0
    fi
    echo "red check skipped for ${group[*]}: the config has no '$key', the command that runs them and prints JUnit XML."
    continue
  fi
  [[ "$command" == *'{files}'* ]] || die "the config's $key has no {files} placeholder."
  command_of["$key"]="$command"
  keys+=("$key")
  files+=("${group[@]}")
done
if ((${#keys[@]} == 0)); then
  echo "red check skipped: no recorded test file has a command to run it."
  exit 0
fi

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

# run_files <key> <file>...: the key's command with {files} replaced by the
# given files, quoted.
run_files() {
  local key="$1"
  shift
  set +e
  run_project "$(with_files "${command_of[$key]}" "$@")"
  set -e
}

# save_run <file> <key> <file>...: what the command printed, through a pipe:
# a report written to /dev/stdout (pytest --junitxml) opens a file anew,
# truncating it and writing over the runner's other lines, but a pipe keeps
# both in order.
save_run() {
  local into="$1"
  shift
  run_files "$@" 2>&1 | cat >"$into"
}

# the files of a key among the given ones
of_key() {
  local key="$1" file
  shift
  for file in "$@"; do
    if [[ -n "${is_outside[$file]:-}" ]]; then
      [[ "$key" == run_integrate_tests ]] && printf '%s\n' "$file"
    else
      [[ "$key" == run_tests ]] && printf '%s\n' "$file"
    fi
  done
  return 0
}

# run_all <output> <integrate-output> <file>...: each key's files through
# its command, run_tests's into <output>, run_integrate_tests's into the
# other; sets junit_runs to junit.py's arguments for those runs.
run_all() {
  local inside_into="$1" outside_into="$2" key into file first=1
  local -a group=() also=()
  shift 2
  junit_runs=()
  for key in "${keys[@]}"; do
    mapfile -t group < <(of_key "$key" "$@")
    ((${#group[@]})) || continue
    into="$inside_into"
    [[ "$key" == run_tests ]] || into="$outside_into"
    save_run "$into" "$key" "${group[@]}"
    if ((first)); then
      junit_runs=(--key "$key" "$into")
      first=0
    else
      # the second run, with its files, before the first run's output
      also=(--also "$key=$into")
      for file in "${group[@]}"; do also+=(--also-file "$file"); done
      junit_runs=("${also[@]}" "${junit_runs[@]}")
    fi
  done
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
  run_all "$state/red-check-head.txt" "$state/red-check-integrate-head.txt" "${old[@]}"
  restore
  trap restore_code EXIT
  python3 "$OVERLOAD_SCRIPTS/junit.py" --list "${junit_runs[@]}" "${old[@]}" >"$existing" || true
fi

run_all "$output" "$state/red-check-integrate-output.txt" "${files[@]}"
restore_code
trap - EXIT

status=0
rm -f "$state/red-check-green.txt"
python3 "$OVERLOAD_SCRIPTS/junit.py" --types "$(cfg red_types)" --existing "$existing" --green "$state/red-check-green.txt" "${junit_runs[@]}" "${files[@]}" || status=$?
if ((status == 0 && !without_code)); then
  git update-ref "$base_ref" "$(git commit-tree "$(source_tree)" -p HEAD -m "stubs state of $branch")"
fi
((status == 2)) && echo "The runners' output is in $state (red-check-output.txt, red-check-integrate-output.txt)."
exit "$status"
