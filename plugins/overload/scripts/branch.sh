#!/usr/bin/env bash
set -euo pipefail

# Opens a task after the triage: checks the name, creates the branch from an
# up-to-date main, and writes the journal with the tier and the intent.
#
#   branch.sh <tier> <name> <intent-file>
#
# <tier> is S or L; <name> is the branch's whole name, which the model writes
# following the project's rules: no part of it is read, so only git and the
# project's commit-msg hook judge it. <intent-file> holds the intent the
# brainstorming wrote (problem, goal, constraints, decisions), copied into
# the journal.

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
in_project
require_config

if (($# != 3)); then
  echo "Usage: branch.sh <S|L> <name> <intent-file>" >&2
  exit 2
fi
tier="$1" branch="$2" intent="$3"

[[ "$tier" == S || "$tier" == L ]] || die "the tier is S or L, not '$tier'."
[[ -s "$intent" ]] || die "the intent file '$intent' is missing or empty."
git check-ref-format --branch "$branch" >/dev/null 2>&1 || die "'$branch' is not a valid branch name."

main="$(cfg main)"
[[ "$branch" != "$main" ]] || die "'$branch' is the main branch: a task opens a branch of its own."
current="$(current_branch)"
[[ "$current" == "$main" ]] || die "on '${current:-a detached HEAD}': a task starts from $main."
# A clean main, but for the first config that /overload setup wrote and has
# not committed yet: its first task is the one that commits it.
dirty="$(git status --porcelain --untracked-files=all)"
if ! git cat-file -e "HEAD:$CONFIG_FILE" 2>/dev/null; then
  dirty="$(printf '%s\n' "$dirty" | grep -v -x -e "?? $CONFIG_FILE" -e "?? .workflow/backlog.md" || true)"
fi
[[ -z "$dirty" ]] || die "the working tree has uncommitted changes: a task starts from a clean $main."
if git show-ref --verify --quiet "refs/heads/$branch"; then
  die "'$branch' exists already."
fi

# The merge's subject goes through the project's commit-msg hook now, so
# that a name it would refuse at the merge is refused before the task.
# `git hook run` follows core.hooksPath; it came with git 2.36.
version="$(git version)"
if [[ "$version" =~ ([0-9]+)\.([0-9]+) ]] && ((BASH_REMATCH[1] > 2 || (BASH_REMATCH[1] == 2 && BASH_REMATCH[2] >= 36))); then
  subject="$(mktemp)"
  printf "Merge branch '%s'\n" "$branch" >"$subject"
  if ! refusal="$(git hook run --ignore-missing commit-msg -- "$subject" 2>&1)"; then
    rm -f "$subject"
    die "the project's commit-msg hook refuses the merge's subject \"Merge branch '$branch'\": choose another name.
$refusal"
  fi
  rm -f "$subject"
else
  echo "branch.sh: git ${version#git version } has no 'git hook run', which came with git 2.36: the merge's subject was not checked against the project's commit-msg hook."
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
