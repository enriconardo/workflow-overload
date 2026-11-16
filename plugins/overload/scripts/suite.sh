#!/usr/bin/env bash
set -euo pipefail

# The test-author's suite, recorded as it hands it over, so that nobody else
# changes it unseen: commit.sh refuses a tree where a recorded test file
# differs from its last record. A record is a commit outside refs/heads
# (refs/overload/suite/<branch>/<n>), so that a red suite never lands on the
# branch, built through a temporary index, so that the working tree, the
# index and the branch stay as they are.
#
#   suite.sh record   the test-author, last: the test files changed against
#                     HEAD (the config's tests_glob) become record <n>
#   suite.sh files    the recorded test files, one per line
#   suite.sh check    fails when a recorded file differs from its record,
#                     or, while a record sits on HEAD, when a test file
#                     outside it changed
#   suite.sh diff     how each recorded file differs, for the reviewers
#   suite.sh clear    removes the branch's records and the stubs' state

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
in_project
require_config

branch="$(current_branch)"
[[ -n "$branch" && "$branch" != "$(cfg main)" ]] || die "on '${branch:-a detached HEAD}': a suite belongs to a task's branch."

mapfile -t specs < <(tests_pathspecs)

# Every listing of files, git diff and git status alike, takes --no-renames:
# a renamed test file is its old path deleted and its new one added, and a
# listing that pairs them would leave the old path out of the suite.

# Each recorded file with the record that holds its last version. Records
# made on the same HEAD belong to one chunk, and each is a full snapshot of
# the test files then: the newest of them speaks for every file the chunk's
# records touched, a file put back as HEAD has it included.
latest() {
  local ref file parent
  declare -A last=() newest=()
  while IFS= read -r ref; do
    parent="$(git rev-parse "$ref^")"
    newest["$parent"]="$ref"
    while IFS= read -r file; do
      [[ -n "$file" ]] && last["$file"]="$ref"
    done < <(git diff --name-only --no-renames "$ref^" "$ref")
  done < <(suite_refs "$branch")
  for file in "${!last[@]}"; do
    printf '%s\t%s\n' "$file" "${newest[$(git rev-parse "${last[$file]}^")]}"
  done | sort
}

record() {
  local tree last next ref commit
  local -a changed=()
  if [[ -e "$REFERENCE_DIR" ]]; then
    die "the reference model $REFERENCE_DIR is still in place: delete it before recording."
  fi
  # The changed test files, listed first: git add refuses a pathspec that
  # matches nothing, and a project rarely uses every glob of the default.
  mapfile -t changed < <(git status --porcelain --untracked-files=all --no-renames -- "${specs[@]}" | cut -c4-)
  ((${#changed[@]})) || die "no test file changed against HEAD (tests_glob: $(cfg tests_glob)): nothing to record."
  # Global, for the trap that runs after the function returns.
  index="$(mktemp)"
  trap 'rm -f "$index"' EXIT
  GIT_INDEX_FILE="$index" git read-tree HEAD
  GIT_INDEX_FILE="$index" git add -A -- "${changed[@]}"
  tree="$(GIT_INDEX_FILE="$index" git write-tree)"
  [[ "$tree" != "$(git rev-parse 'HEAD^{tree}')" ]] || die "no test file changed against HEAD (tests_glob: $(cfg tests_glob)): nothing to record."
  # The highest number plus one: a record removed by hand never comes back
  # as an existing number, and update-ref with an empty old value refuses one.
  last="$(suite_refs "$branch" | tail -n 1)"
  next=1
  [[ -n "$last" ]] && next=$((${last##*/} + 1))
  ref="refs/overload/suite/$branch/$next"
  commit="$(git commit-tree "$tree" -p HEAD -m "test-author suite $next on $branch")"
  git update-ref "$ref" "$commit" ""
  echo "Recorded suite $next as $ref:"
  git diff --name-status --no-renames HEAD "$commit"
}

check() {
  local file ref changed=()
  while IFS=$'\t' read -r file ref; do
    if git cat-file -e "$ref:$file" 2>/dev/null; then
      if [[ ! -f "$file" ]] || [[ "$(git hash-object -- "$file")" != "$(git rev-parse "$ref:$file")" ]]; then
        changed+=("$file")
      fi
    elif [[ -e "$file" ]]; then
      changed+=("$file")
    fi
  done < <(latest)
  if ((${#changed[@]})); then
    printf 'overload: these recorded test files differ from the suite the test-author handed over:\n' >&2
    printf '  %s\n' "${changed[@]}" >&2
    echo "Only the test-author changes them, and records the suite again." >&2
    exit 1
  fi
  # A record made on this HEAD means a test-first chunk is under way: its
  # tests come from the test-author only, so no other test file changes.
  local last extra=()
  last="$(suite_refs "$branch" | tail -n 1)"
  [[ -n "$last" && "$(git rev-parse "$last^")" == "$(git rev-parse HEAD)" ]] || return 0
  local -A recorded=()
  while IFS= read -r file; do
    [[ -n "$file" ]] && recorded["$file"]=1
  done < <(git diff --name-only --no-renames HEAD "$last")
  while IFS= read -r file; do
    [[ -n "$file" && -z "${recorded[$file]:-}" ]] && extra+=("$file")
  done < <(git status --porcelain --untracked-files=all --no-renames -- "${specs[@]}" | cut -c4-)
  if ((${#extra[@]})); then
    printf 'overload: these test files changed but are not in the suite the test-author recorded for this chunk:\n' >&2
    printf '  %s\n' "${extra[@]}" >&2
    echo "On a test-first chunk the tests come from the test-author: report the missing case, or undo the change." >&2
    exit 1
  fi
}

case "${1:-}" in
  record) record ;;
  files) latest | cut -f1 ;;
  check) check ;;
  diff)
    # Compared by content: an untracked file is invisible to git diff <ref>.
    while IFS=$'\t' read -r file ref; do
      recorded="$(mktemp)"
      git show "$ref:$file" >"$recorded" 2>/dev/null || : >"$recorded"
      if [[ -f "$file" ]] && cmp -s "$recorded" "$file"; then
        echo "== $file: as recorded (${ref##*/})"
      else
        echo "== $file: changed since record ${ref##*/}"
        git --no-pager diff --no-index -- "$recorded" "$([[ -f "$file" ]] && echo "$file" || echo /dev/null)" || true
      fi
      rm -f "$recorded"
    done < <(latest)
    ;;
  clear)
    suite_refs "$branch" | while IFS= read -r ref; do git update-ref -d "$ref"; done
    git update-ref -d "refs/overload/base/$branch" 2>/dev/null || true
    ;;
  *)
    echo "Usage: suite.sh record | files | check | diff | clear" >&2
    exit 2
    ;;
esac
