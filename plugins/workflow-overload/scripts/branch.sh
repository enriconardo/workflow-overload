#!/usr/bin/env bash
set -euo pipefail

# Opens a task after the triage: checks the name against the config's
# `branch` and `types`, creates the branch from an up-to-date main, and
# writes the journal with the tier and the intent.
#
#   branch.sh <tier> <type> <scope> <description> <intent-file>
#
# <tier> is S or L; <intent-file> holds the intent the brainstorming wrote
# (problem, goal, constraints, decisions), copied into the journal.

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
in_project
require_config

if (($# != 5)); then
  echo "Usage: branch.sh <S|L> <type> <scope> <description> <intent-file>" >&2
  exit 2
fi
tier="$1" type="$2" scope="$3" description="$4" intent="$5"

[[ "$tier" == S || "$tier" == L ]] || die "the tier is S or L, not '$tier'."
[[ -s "$intent" ]] || die "the intent file '$intent' is missing or empty."

types="$(cfg types)"
known=0
IFS=',' read -ra list <<<"$types"
for t in "${list[@]}"; do
  t="${t//[[:space:]]/}"
  [[ "$t" == "$type" ]] && known=1
done
((known)) || die "'$type' is not among the config's types: $types."

kebab='^[a-z0-9]+(-[a-z0-9]+)*$'
[[ "$scope" =~ $kebab ]] || die "the scope '$scope' is not kebab-case."
# A ticket id may open the description: EN-209-snapshot-diff.
[[ "$description" =~ ^([A-Z]+-[0-9]+-)?[a-z0-9]+(-[a-z0-9]+)*$ ]] || die "the description '$description' is not kebab-case."

template="$(cfg branch)"
branch="${template//<type>/$type}"
branch="${branch//<scope>/$scope}"
branch="${branch//<description>/$description}"
[[ "$branch" != *'<'* ]] || die "the config's branch '$template' has a placeholder this script does not fill: <type>, <scope> and <description> only."
git check-ref-format --branch "$branch" >/dev/null 2>&1 || die "'$branch' is not a valid branch name."

# The merge subject `Merge branch '<branch>'` must fit the project's subject
# limit, when it has one.
max="$(cfg subject_max)"
[[ -z "$max" || "$max" =~ ^[0-9]+$ ]] || die "the config's subject_max '$max' is not a number."
if [[ -n "$max" ]] && ((${#branch} + 15 > max)); then
  die "'$branch' has ${#branch} characters: its merge subject would be over $max. Shorten the description."
fi

main="$(cfg main)"
current="$(current_branch)"
[[ "$current" == "$main" ]] || die "on '${current:-a detached HEAD}': a task starts from $main."
# A clean main, but for the first config that /overload init wrote and has
# not committed yet: its first task is the one that commits it.
dirty="$(git status --porcelain --untracked-files=all)"
if ! git cat-file -e "HEAD:$CONFIG_FILE" 2>/dev/null; then
  dirty="$(printf '%s\n' "$dirty" | grep -v -x -e "?? $CONFIG_FILE" -e "?? .workflow/backlog.md" || true)"
fi
[[ -z "$dirty" ]] || die "the working tree has uncommitted changes: a task starts from a clean $main."
if git show-ref --verify --quiet "refs/heads/$branch"; then
  die "'$branch' exists already."
fi

# A clone without an upstream is up to date by definition.
if git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' >/dev/null 2>&1; then
  git pull --ff-only --quiet
fi

git switch --quiet -c "$branch"

mkdir -p "$(dirname "$JOURNAL_FILE")"
{
  echo "# Task journal"
  echo
  echo "branch: $branch"
  echo "tier: $tier"
  echo "phase: $([[ "$tier" == S ]] && echo s/implement || echo l/spec)"
  echo "base: $(git rev-parse --short HEAD)"
  echo "started: $(now)"
  echo "review_rounds: 0"
  echo "verify_red_streak: 0"
  echo "escalations: 0"
  echo
  echo "## Intent"
  echo
  # Its headings go below the journal's sections, which the scripts read.
  sed -E 's/^(#+ )/##\1/' "$intent"
  echo
  echo "## Open findings"
  echo
  echo "## Lesson candidates"
  echo
  echo "## Backlog candidates"
  echo
  echo "## Log"
  echo
  echo "- $(now) opened on $(git rev-parse --short HEAD) of $main"
} >"$JOURNAL_FILE"

echo "On '$branch', tier $tier; the journal is $JOURNAL_FILE."
