#!/usr/bin/env bash
set -euo pipefail

# Commits the working tree of a task's branch, only when it is the tree the
# last green verify checked. Everything goes in, the journal included: one
# commit is one logical change, so code, review fixes and lessons are
# separate runs of verify and of this script. The message is the model's,
# written to the project's rules; the project's hooks judge it, and a commit
# whose tree a pre-commit hook changed is undone.
#
#   commit.sh <message-file>

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
in_project
require_config
on_task_branch

(($# == 1)) || {
  echo "Usage: commit.sh <message-file>" >&2
  exit 2
}
message="$1"
[[ -s "$message" ]] || die "the message file '$message' is missing or empty."

subject="$(grep -v -m 1 -e '^#' -e '^[[:space:]]*$' "$message" || true)"
[[ -n "$subject" ]] || die "the message has no subject line."

if [[ -z "$(git status --porcelain)" ]]; then
  die "nothing to commit."
fi
is_verified || die "the working tree is not the one the last green verify checked: run verify.sh first."

# The test-author's suite, once recorded, is changed by nobody else.
if [[ -x "$OVERLOAD_SCRIPTS/suite.sh" ]]; then
  bash "$OVERLOAD_SCRIPTS/suite.sh" check
fi

git add -A
# What is staged must be what verify checked, whatever stat data the real
# index held.
if [[ "$(commit_tree_hash "$(git write-tree)")" != "$(cut -d' ' -f1 "$(verified_file)")" ]]; then
  git reset -q
  die "the staged tree differs from the verified one: run verify.sh again, then commit."
fi
git commit --quiet -F "$message" ||
  die "git refused the commit, most likely through a hook of the project: its output is above. Fix what it says (verify again after changing a file), then commit again."
# A pre-commit hook that rewrites staged files (lint-staged, a formatter)
# changes the tree after the check: the commit must be the verified tree.
verified_tree="$(cut -d' ' -f1 "$(verified_file)")"
committed="$(commit_tree_hash HEAD)"
if [[ "$committed" != "$verified_tree" ]]; then
  changed="$(git diff --name-only --no-renames "$verified_tree" "$committed")"
  git reset -q --soft HEAD^
  die "a hook changed the commit's tree after verify checked it: the commit is undone, the hook's changes are in the working tree. Verify them, then commit again. The files it changed:
$changed"
fi
git log -1 --format='committed %h %s'
