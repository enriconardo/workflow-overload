#!/usr/bin/env bash
set -euo pipefail

# Integrates a task's branch after the human's go at the last checkpoint:
# refuses a tree that is not the verified one, merges with --no-ff into main
# without the journal and with the task's line of measures, repeats verify on
# the merge's result when main moved, and deletes the branch and its records.
# A conflict or a red verify aborts the merge and leaves main as it was.
#
#   integrate.sh

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
in_project
require_config
on_task_branch

branch="$(current_branch)"
main="$(cfg main)"
mode="$(cfg integrate)"
[[ "$mode" == merge ]] || die "integrate = '$mode' is not supported yet: this version merges locally (integrate = merge)."

dirty="$(git status --porcelain -- . ":(exclude)$JOURNAL_FILE" ":(exclude)$METRICS_FILE")"
[[ -z "$dirty" ]] || die "the working tree has uncommitted changes: verify and commit them first.
$dirty"

verified="$(verified_file)"
[[ -f "$verified" && "$(cut -d' ' -f1 "$verified")" == "$(commit_tree_hash HEAD)" ]] ||
  die "HEAD is not the tree the last green verify checked: run verify.sh first."

git show-ref --verify --quiet "refs/heads/$main" || die "no local '$main' to integrate into."

# An L task's spec is done: every chunk ticked, its status set.
spec="$(journal_get spec)"
if [[ -n "$spec" ]]; then
  [[ -f "$spec" ]] || die "the journal's spec '$spec' does not exist."
  if grep -q '^- \[ \]' "$spec"; then
    die "$spec has chunks not ticked:
$(grep '^- \[ \]' "$spec")"
  fi
  grep -qx 'status: done' "$spec" || die "$spec is not 'status: done': set it, verify and commit, then integrate."
fi

# The journal leaves with the branch; the measures read it first.
journal_copy="$(mktemp)"
cp "$JOURNAL_FILE" "$journal_copy"
measures="$(mktemp)"
trap 'rm -f "$journal_copy" "$measures"' EXIT
python3 "$OVERLOAD_SCRIPTS/metrics.py" record --branch "$branch" --main "$main" \
  --journal "$journal_copy" --runs "$(state_dir)/runs.log" >"$measures" ||
  die "the measures of '$branch' could not be computed; nothing was merged."

# The journal is tracked on the branch: a local edit to it would block the
# switch, and the merge drops the file anyway.
git checkout --quiet -- "$JOURNAL_FILE" 2>/dev/null || true
git switch --quiet "$main"
if git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' >/dev/null 2>&1; then
  git pull --ff-only --quiet || {
    git switch --quiet "$branch"
    die "'$main' cannot fast-forward to its upstream: settle that by hand, then run this again."
  }
fi

back_to_branch() {
  git merge --abort 2>/dev/null || true
  git switch --quiet "$branch"
}

moved=0
git merge-base --is-ancestor "$main" "$branch" || moved=1

if ! git merge --no-ff --no-commit --quiet "$branch" >/dev/null 2>&1; then
  conflicts="$(git diff --name-only --diff-filter=U)"
  back_to_branch
  die "merging '$branch' into '$main' conflicts; '$main' is unchanged. Ask the human. Conflicting files:
$conflicts"
fi

git rm -q -f --ignore-unmatch -- "$JOURNAL_FILE"
mkdir -p "$(dirname "$METRICS_FILE")"
cat "$measures" >>"$METRICS_FILE"
git add -- "$METRICS_FILE"

if ((moved)); then
  echo "'$main' moved since the branch started: verifying the merge's result."
  if ! bash "$OVERLOAD_SCRIPTS/verify.sh"; then
    back_to_branch
    die "verify is red on the merge's result; '$main' is unchanged. Ask the human."
  fi
fi

git commit --quiet --no-edit
git branch -q -d "$branch"
for ref in $(git for-each-ref --format='%(refname)' "refs/overload/suite/$branch"); do
  git update-ref -d "$ref"
done
rm -f "$verified"
git log -1 --format="integrated '$branch' into '$main' as %h %s"
