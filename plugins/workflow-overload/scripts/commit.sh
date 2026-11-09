#!/usr/bin/env bash
set -euo pipefail

# Commits the working tree of a task's branch, only when it is the tree the
# last green verify checked, with a subject in the config's `commit` format.
# Everything goes in, the journal included: one commit is one logical
# change, so code, review fixes and lessons are separate runs of verify and
# of this script.
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

# The config's format as an extended regex: the literal parts escaped,
# <type> one of `commit_types`, the other placeholders any text.
template="$(cfg commit)"
types="$(cfg commit_types)"
alternation="$(printf '%s' "$types" | tr -d '[:space:]' | tr ',' '|')"
# shellcheck disable=SC2016 # a sed bracket expression, not an expansion
regex="$(printf '%s' "$template" | sed -e 's/[][\.*^$()+?{}|/]/\\&/g')"
regex="${regex//<type>/($alternation)}"
regex="$(printf '%s' "$regex" | sed -e 's/<[a-z_-]*>/.+/g')"
if ! [[ "$subject" =~ ^$regex$ ]]; then
  die "the subject '$subject' does not follow the config's format '$template' (types: $types)."
fi
max="$(cfg subject_max)"
length="$(printf '%s' "$subject" | wc -m | tr -d ' ')"
((length <= max)) || die "the subject has $length characters, over $max."

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
git commit --quiet -F "$message"
git log -1 --format='committed %h %s'
