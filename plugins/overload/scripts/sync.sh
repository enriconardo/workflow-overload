#!/usr/bin/env bash
set -euo pipefail

# Takes a moved main into the task's branch, so that a red caused by the
# meeting of the two shows on the branch and is fixed there, in the normal
# loop: brings main up to its upstream, then merges it without committing.
# The merge is committed like any other change, after a green verify, with
# its fixes; the journal's base becomes main's commit, so that <base>..HEAD
# still holds the branch's own changes only. integrate.sh refuses a branch
# that does not hold main.
#
#   sync.sh          takes main in; a conflict is left to resolve
#   sync.sh --abort  undoes a sync not yet committed, the base included

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
in_project
require_config
on_task_branch

branch="$(current_branch)"
main="$(cfg main)"
merging="$(git rev-parse --git-path MERGE_HEAD)"
saved_base="$(state_dir)/sync-base"

case "${1:-}" in
  "") ;;
  --abort)
    [[ -f "$merging" ]] || die "no sync under way on '$branch'."
    git merge --abort
    if [[ -f "$saved_base" ]]; then
      bash "$OVERLOAD_SCRIPTS/journal.sh" set base "$(cat "$saved_base")"
      rm -f "$saved_base"
    fi
    bash "$OVERLOAD_SCRIPTS/journal.sh" log "sync with $main undone"
    echo "sync undone: '$branch' is as it was before it."
    exit 0
    ;;
  *) die "usage: sync.sh [--abort]" ;;
esac

[[ ! -f "$merging" ]] || die "a merge is under way: resolve it, verify and commit it, or undo it with sync.sh --abort."
dirty="$(git status --porcelain -- . ":(exclude)$JOURNAL_FILE")"
[[ -z "$dirty" ]] || die "the working tree has uncommitted changes: verify and commit them first.
$dirty"
git show-ref --verify --quiet "refs/heads/$main" || die "no local '$main' to take in."

main_from_upstream "$main"
target="$(git rev-parse --short "refs/heads/$main")"
if git merge-base --is-ancestor "$main" HEAD; then
  echo "'$branch' already holds '$main' ($target): nothing to take in."
  exit 0
fi

journal_get base >"$saved_base"
bash "$OVERLOAD_SCRIPTS/journal.sh" set base "$target"
bash "$OVERLOAD_SCRIPTS/journal.sh" log "sync: took in $main at $target; base was $(cat "$saved_base")"

if ! git merge --no-ff --no-commit --quiet "$main" >/dev/null 2>&1; then
  conflicts="$(git diff --name-only --diff-filter=U)"
  [[ -n "$conflicts" ]] || {
    git merge --abort 2>/dev/null || true
    bash "$OVERLOAD_SCRIPTS/journal.sh" set base "$(cat "$saved_base")"
    rm -f "$saved_base"
    die "git could not merge '$main' into '$branch'; nothing changed."
  }
  die "taking in '$main' ($target) conflicts on these files, left with their markers:
$conflicts
Resolve them, verify and commit the merge with commit.sh; or undo it with sync.sh --abort."
fi
echo "took in '$main' at $target, not committed: verify, then commit the merge with commit.sh."
