#!/usr/bin/env bash
set -euo pipefail

# Opens a task: checks the name, creates the branch from an up-to-date main,
# and writes the journal with the tier, the command that runs the task and
# the intent.
#
#   branch.sh <tier> <name> <intent-file> [--item <plan> <n> | --change <doc>] [--map <file>] [--inputs <slug> <file>...]
#   branch.sh --build <name> <spec|plan>
#
# The first form opens a task of /overload:task after the triage; the second
# a task of /overload:build. With a plan, the open plan once every item is
# ticked, it opens the plan's acceptance: tier A, phase a/run, the journal
# names the plan, and the branch is recorded as working the plan's
# acceptance, so that no revision or drop of the plan opens meanwhile. With
# a spec, approved on main with a chunk left to build, its journal names
# the spec, which holds the intent, and its phase is that chunk's first
# step. Unless the spec expired: the files it rests on
# (its frontmatter's depends_on, the config's rules, the config) changed on
# main since the commit that brought it there, its approval. Then the phase
# is l/expiry, and the build reviews the spec against those changes first.
# The journal records the approval as `approved`, and logs what main changed.
#
# <tier> is S, L, P for a plan, or D for a drop: one plan is open at a
# time, so a plan task waits until main holds none approved. --change names
# a decision main holds that the task changes, which the journal records as
# `change`: with P, the open plan, which the task revises (the journal names
# it as `plan` too); with D, the open plan or a spec approved and not built,
# which the task drops. A drop waits while an item of its plan, or its
# acceptance, is open on a branch: that task stops or ends first; a revision
# waits for the acceptance alone. --item opens S or L on an item of the
# open plan, which the journal names as `plan` and `item`: the plan
# approved on main, the item not ticked, its spec not approved yet, its
# dependencies ticked, no other item started. A build of an item's spec
# names them too, and the plan joins the files whose change expires the
# spec. Either records under the state folder that its branch works the
# item, until integrate.sh merges it: one item at a time.
#
# <name> is the branch's whole name, which the model writes following the
# project's rules: no part of it is read, so only git and the project's
# commit-msg hook judge it. <intent-file> holds the intent the
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
  echo "Usage: branch.sh <S|L|P|D> <name> <intent-file> [--item <plan> <n> | --change <doc>] [--map <file>] [--inputs <slug> <file>...] | branch.sh --build <name> <spec|plan>" >&2
  exit 2
}
(($# >= 3)) || usage
command=task spec="" approved="" note="" log=""
acceptance=""
if [[ "$1" == --build ]]; then
  (($# == 3)) || usage
  command=build tier=L branch="$2" spec="${3#./}"
  if [[ "$spec" == .workflow/plans/*.md ]]; then
    tier=A acceptance="$spec" spec=""
  fi
  set -- "$tier" "$branch" ""
else
  tier="$1"
fi
branch="$2" intent="$3"
shift 3
map="" slug="" inputs=() plan="" item="" change="" changed_plan=""
if [[ "${1:-}" == --item ]]; then
  [[ $# -ge 3 && ("$tier" == S || "$tier" == L) ]] || usage
  plan="$2" item="$3"
  shift 3
elif [[ "${1:-}" == --change ]]; then
  [[ $# -ge 2 && ("$tier" == P || "$tier" == D) ]] || usage
  change="$2"
  shift 2
fi
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

[[ "$tier" == S || "$tier" == L || "$tier" == P || "$tier" == D || -n "$acceptance" ]] || die "the tier is S, L, P (a plan) or D (a drop), not '$tier'."
[[ "$tier" != D || -n "$change" ]] || die "tier D drops a plan or a spec: name it with --change <doc>."
[[ "$command" == build || -s "$intent" ]] || die "the intent file '$intent' is missing or empty."
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

# A build starts from the spec as main holds it: approved, with a chunk
# left to build.
case "$tier" in
  S) phase=s/implement ;;
  L) phase=l/spec ;;
  P) phase=p/plan ;;
  D) phase=d/drop ;;
  A) phase=a/run ;;
esac
if [[ "$tier" == P && -z "$change" ]]; then
  open="$(open_plans | head -n 1)"
  [[ -z "$open" ]] || die "a plan is open already, $open: one plan at a time. Its next item is in /overload:task's status."
fi
# A decision main holds: the open plan, revised or dropped, or a spec
# approved and not built, dropped.
if [[ -n "$change" ]]; then
  change="${change#./}"
  case "$change" in
    .workflow/plans/*.md)
      plan_in_head "$change"
      changed_plan="$change"
      [[ "$tier" == D ]] || plan="$change"
      ;;
    .workflow/specs/*.md)
      [[ "$tier" == D ]] || die "a spec approved on main changes only by its drop (tier D): a correction goes through its build."
      git cat-file -e "HEAD:$change" 2>/dev/null || die "$change is not a file on $main."
      status="$(git show "HEAD:$change" | python3 "$OVERLOAD_SCRIPTS/spec.py" status -)"
      [[ "$status" == approved ]] || die "$change is not 'status: approved' but '${status:-none}': only a spec approved and not built is dropped."
      linked="$(git show "HEAD:$change" | python3 "$OVERLOAD_SCRIPTS/spec.py" link - 2>&1)" || die "$change: ${linked#spec.py: -: }"
      changed_plan="${linked%%$'\t'*}"
      ;;
    *) die "'$change' is neither a plan (.workflow/plans/<name>.md) nor a spec (.workflow/specs/<name>.md) that main holds." ;;
  esac
  if [[ -n "$changed_plan" ]] && other="$(item_open_elsewhere "$changed_plan")"; then
    IFS=$'\t' read -r other_branch other_item _ <<<"$other"
    if [[ "$tier" == D ]]; then
      die "$(work_name "$other_item") of $changed_plan is open on branch $other_branch: stop that task, or end it, before the drop."
    elif [[ "$other_item" == acceptance ]]; then
      die "the acceptance of $changed_plan is open on branch $other_branch: it ends first, and a revision then adds the items its failed steps call for."
    fi
  fi
fi
[[ -z "$item" ]] || title="$(item_can_open "$plan" "$item")"
# An acceptance: the open plan, every item ticked, nothing else of it open.
if [[ -n "$acceptance" ]]; then
  plan="$acceptance"
  plan_in_head "$plan"
  items="$(git show "HEAD:$plan" | python3 "$OVERLOAD_SCRIPTS/spec.py" items - 2>&1)" || die "$plan: ${items#spec.py: -: }"
  open="$(awk -F'\t' '$2 != "done" { print $1; exit }' <<<"$items")"
  [[ -z "$open" ]] || die "item $open of $plan is not ticked: the acceptance runs once every item is."
  if other="$(item_open_elsewhere "$plan")"; then
    IFS=$'\t' read -r other_branch other_item _ <<<"$other"
    die "$(work_name "$other_item") of $plan is open on branch $other_branch: one at a time."
  fi
elif [[ "$command" == build ]]; then
  git cat-file -e "HEAD:$spec" 2>/dev/null || die "'$spec' is not a file on $main: /overload:build builds a spec that a task approved and integrated."
  status="$(git show "HEAD:$spec" | python3 "$OVERLOAD_SCRIPTS/spec.py" status -)"
  [[ "$status" == approved ]] || die "$spec is not 'status: approved' but '${status:-none}': /overload:task approves a spec."
  chunks="$(git show "HEAD:$spec" | python3 "$OVERLOAD_SCRIPTS/spec.py" chunks - 2>&1)" || die "$chunks"
  phase="$(next_chunk_phase "$chunks")"
  [[ "$phase" != close/check ]] || die "$spec has no chunk left to build."
  # The approval: the last commit of main's own line that changed the spec,
  # the merge of the task that approved it.
  approved="$(git log --first-parent -1 --format=%h HEAD -- "$spec")"
  head="$(git rev-parse --short HEAD)"
  linked="$(git show "HEAD:$spec" | python3 "$OVERLOAD_SCRIPTS/spec.py" link - 2>&1)" || die "$spec: ${linked#spec.py: -: }"
  if [[ -n "$linked" ]]; then
    IFS=$'\t' read -r plan item <<<"$linked"
    plan_in_head "$plan"
    if other="$(item_open_elsewhere "$plan")"; then
      IFS=$'\t' read -r other_branch other_item _ <<<"$other"
      die "$(work_name "$other_item") of $plan is open on branch $other_branch: one item at a time."
    fi
  fi
  mapfile -t watched < <(git show "HEAD:$spec" | python3 "$OVERLOAD_SCRIPTS/spec.py" depends -)
  ((${#watched[@]})) || note="the spec names no depends_on: only the rules${plan:+, the plan} and the config were checked."
  mapfile -t -O "${#watched[@]}" watched < <(rules_entries)
  watched+=("$CONFIG_FILE")
  [[ -z "$plan" ]] || watched+=("$plan")
  mapfile -t changed < <(git diff --name-only --no-renames "$approved" HEAD -- "${watched[@]}")
  if ((${#changed[@]})); then
    phase=l/expiry
    shown="$(printf '%s, ' "${changed[@]:0:10}")"
    ((${#changed[@]} <= 10)) || shown+="and $((${#changed[@]} - 10)) more, "
    log="expiry: main changed the spec's files since its approval: ${shown%, }; see git diff $approved $head -- $(printf '%q ' "${watched[@]}")"
    log="${log% }"
  else
    moved="$(git rev-list --first-parent --count "$approved..HEAD")"
    if ((moved)); then
      log="main moved since the spec's approval: $moved commit$( ((moved == 1)) || echo s) (git log --first-parent --oneline $approved..$head), none on its files"
    fi
  fi
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
  echo "command: $command"
  echo "phase: $phase"
  echo "base: $(git rev-parse --short HEAD)"
  echo "started: $(now)"
  echo "verify_red_streak: 0"
  [[ -z "$spec" ]] || echo "spec: $spec"
  [[ -z "$spec" ]] || echo "approved: $approved"
  [[ -z "$plan" ]] || echo "plan: $plan"
  [[ -z "$item" ]] || echo "item: $item"
  [[ -z "$change" ]] || echo "change: $change"
  echo
  echo "## Intent"
  echo
  if [[ -n "$spec" ]]; then
    echo "Build the approved spec $spec: its *Why*, *What* and *Decisions* hold the intent."
  elif [[ -n "$acceptance" ]]; then
    echo "Run the acceptance of the plan $plan: every step of its *Acceptance*, from the first, on the code its items built."
  else
    # Its headings go below the journal's sections, which the scripts read.
    sed -E 's/^(#+ )/##\1/' "$intent"
  fi
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
  [[ -z "$log" ]] || echo "- $(now) $log"
} >"$JOURNAL_FILE"

[[ -z "$map" ]] || bash "$OVERLOAD_SCRIPTS/journal.sh" keep map "$map" >/dev/null
[[ -z "$item" ]] || record_item "$plan" "$item" "$command"
[[ -z "$acceptance" ]] || record_item "$plan" acceptance build

echo "On '$branch', tier $tier; the journal is $JOURNAL_FILE."
if [[ -n "$item" ]]; then
  if [[ -n "${title:-}" ]]; then
    IFS=$'\t' read -r _ estimated name <<<"$title"
    echo "It works item $item of $plan, $name, estimated $estimated."
  else
    echo "It builds item $item of $plan."
  fi
fi
[[ -z "$change" ]] || echo "It changes $change."
[[ -z "$acceptance" ]] || echo "It runs the acceptance of $plan."
[[ -z "$note" ]] || echo "$note"
[[ -z "$log" ]] || echo "${log#expiry: }; phase $phase."
