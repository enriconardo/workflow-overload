#!/usr/bin/env bash
set -euo pipefail

# Opens a task after the triage: checks the name, creates the branch from an
# up-to-date main, and writes the journal with the tier and the intent.
#
#   branch.sh <tier> <name> <intent-file> [--map <file>] [--inputs <slug> <file>...]
#
# <tier> is S or L; <name> is the branch's whole name, which the model writes
# following the project's rules: no part of it is read, so only git and the
# project's commit-msg hook judge it. <intent-file> holds the intent the
# brainstorming wrote (problem, goal, constraints, decisions), copied into
# the journal. The inputs the human gave (a brief, a mockup, a sample) are
# copied into .workflow/inputs/<slug>/, which the journal's *Inputs* lists:
# the first commit takes them to the branch, and the merge to main, where a
# later session finds them. <slug> is the name of the spec that will use
# them, or the task's. The explorer's map, when it ran, is kept for the
# sessions to come, as `journal.sh keep map` does.

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
in_project
require_config

usage() {
  echo "Usage: branch.sh <S|L> <name> <intent-file> [--map <file>] [--inputs <slug> <file>...]" >&2
  exit 2
}
(($# >= 3)) || usage
tier="$1" branch="$2" intent="$3"
shift 3
map="" slug="" inputs=()
if [[ "${1:-}" == --map ]]; then
  (($# >= 2)) || usage
  map="$2"
  shift 2
fi
if (($#)); then
  [[ "$1" == --inputs && $# -ge 3 ]] || usage
  slug="$2"
  inputs=("${@:3}")
fi
INPUTS_DIR=".workflow/inputs"

[[ "$tier" == S || "$tier" == L ]] || die "the tier is S or L, not '$tier'."
[[ -s "$intent" ]] || die "the intent file '$intent' is missing or empty."
[[ -z "$map" || -f "$map" ]] || die "the map '$map' is not a file."
if [[ -n "$slug" ]]; then
  [[ "$slug" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || die "'$slug' is not a folder name for the inputs: letters, digits, '.', '_' and '-'."
  declare -A seen=()
  for file in "${inputs[@]}"; do
    [[ -f "$file" ]] || die "the input '$file' is not a file."
    name="$(basename -- "$file")"
    [[ -z "${seen[$name]:-}" ]] || die "two inputs named '$name': rename one."
    seen["$name"]=1
  done
  [[ ! -e "$INPUTS_DIR/$slug" ]] || die "$INPUTS_DIR/$slug exists already: choose another name."
fi
git check-ref-format --branch "$branch" >/dev/null 2>&1 || die "'$branch' is not a valid branch name."

main="$(cfg main)"
[[ "$branch" != "$main" ]] || die "'$branch' is the main branch: a task opens a branch of its own."
current="$(current_branch)"
[[ "$current" == "$main" ]] || die "on '${current:-a detached HEAD}': a task starts from $main."
git rev-parse -q --verify HEAD >/dev/null || die "'$main' has no commit yet: /overload:setup makes the first one."
# A clean main, but for the first config that /overload:setup wrote and has
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

copied=()
for file in ${inputs[@]+"${inputs[@]}"}; do
  mkdir -p "$INPUTS_DIR/$slug"
  cp -- "$file" "$INPUTS_DIR/$slug/"
  copied+=("$INPUTS_DIR/$slug/$(basename -- "$file")")
done

mkdir -p "$(dirname "$JOURNAL_FILE")"
{
  echo "# Task journal"
  echo
  echo "branch: $branch"
  echo "tier: $tier"
  echo "phase: $([[ "$tier" == S ]] && echo s/implement || echo l/spec)"
  echo "base: $(git rev-parse --short HEAD)"
  echo "started: $(now)"
  echo "verify_red_streak: 0"
  echo
  echo "## Intent"
  echo
  # Its headings go below the journal's sections, which the scripts read.
  sed -E 's/^(#+ )/##\1/' "$intent"
  echo
  if ((${#copied[@]})); then
    echo "## Inputs"
    echo
    printf -- '- %s\n' "${copied[@]}"
    echo
  fi
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

[[ -z "$map" ]] || bash "$OVERLOAD_SCRIPTS/journal.sh" keep map "$map" >/dev/null

echo "On '$branch', tier $tier; the journal is $JOURNAL_FILE."
