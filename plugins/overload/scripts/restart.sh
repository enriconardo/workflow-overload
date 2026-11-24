#!/usr/bin/env bash
set -euo pipefail

# Reopens a task at a larger tier, on the human's go. The journal stays,
# with the facts found so far, which the main agent logs first.
#
#   restart.sh <reason>
#   restart.sh --plan <reason>
#
# The first form reopens as L an S task that proved to be L: the attempt's
# code goes, and the task starts again from main, so that its spec comes
# from the problem, not from a sketched solution.
#
# --plan turns the task of a spec not approved yet, too large for one spec,
# into a plan task on the same branch: tier P, phase p/plan, the spec's
# draft kept under the state folder (logged as `spec`) and taken out of the
# tree, for the plan to start from. A spec of no plan becomes a new plan,
# refused while main holds a plan open: one plan at a time, and the spec
# stays a spec. An item's spec becomes a revision of its plan, which splits
# the item: never a plan in the plan. The journal then names the plan as
# `change`, and no longer the item, which the branch stops working.
#
# Without --plan:
# Aborts a sync under way; puts the uncommitted work in a stash; recreates
# the branch, same name, from main brought up to its upstream; puts back the
# journal as tier L, phase l/spec, main as its base, no red streak, no open
# findings (they speak of code that is gone), its candidates and its log
# kept, the reason logged; puts back the inputs, and the first config and
# backlog when main lacks them; drops the verified trees and the branch's
# records, keeping the explorer's map and the plan's item it works. It
# prints what it discarded: the commits, the attempt's tip, which `git
# reflog <branch>` keeps, and the stash. The journal names neither, so that
# the spec does not start from the attempt.

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
in_project
require_config
on_task_branch

to_plan=0
if [[ "${1:-}" == --plan ]]; then
  to_plan=1
  shift
fi
(($#)) && [[ -n "$*" ]] || {
  echo "Usage: restart.sh [--plan] <reason>" >&2
  exit 2
}
reason="$*"
tier="$(journal_get tier)"
branch="$(current_branch)"
main="$(cfg main)"
journal() { bash "$OVERLOAD_SCRIPTS/journal.sh" "$@"; }

if ((to_plan)); then
  phase="$(journal_get phase)"
  [[ "$tier" == L && "$(journal_get command)" == task ]] ||
    die "restart.sh --plan turns into a plan the task of a spec not approved yet (tier L), not tier $tier of /overload:$(journal_get command)."
  [[ "$phase" == l/* ]] || die "restart.sh --plan runs before the spec is approved, not in phase $phase."
  plan="$(journal_get plan)"
  item="$(journal_get item)"
  main_from_upstream "$main"
  if [[ -n "$item" ]]; then
    status="$(git show "refs/heads/$main:$plan" 2>/dev/null | python3 "$OVERLOAD_SCRIPTS/spec.py" status -)"
    [[ "$status" == approved ]] || die "$plan is not approved on $main but '${status:-none}': only the open plan is revised."
  else
    while IFS= read -r open; do
      [[ "$open" == *.md && "$(git show "refs/heads/$main:$open" | python3 "$OVERLOAD_SCRIPTS/spec.py" status -)" == approved ]] &&
        die "a plan is open on main, $open: one plan at a time, the spec stays a spec."
    done < <(git ls-tree -r --name-only "refs/heads/$main" -- .workflow/plans/)
  fi
  spec="$(journal_get spec)"
  kept=""
  if [[ -n "$spec" && -f "$spec" ]]; then
    journal keep spec "$spec" >/dev/null
    kept="$(state_dir)/kept/$branch/spec.md"
    git rm -q --cached --ignore-unmatch -- "$spec"
    rm -f -- "$spec"
  fi
  # The header loses the spec and the item: the task now writes a plan.
  awk '/^## / { body = 1 } body || !/^(spec|item): / { print }' "$JOURNAL_FILE" >"$JOURNAL_FILE.new" &&
    mv "$JOURNAL_FILE.new" "$JOURNAL_FILE"
  journal set tier P
  journal set phase p/plan
  [[ -z "$item" ]] || journal set change "$plan"
  journal log "tier P: $reason"
  rm -f "$(item_records_dir)/$branch"
  if [[ -n "$item" ]]; then
    echo "On '$branch', tier P, phase p/plan: a revision of $plan that splits item $item; the branch no longer works the item."
  else
    echo "On '$branch', tier P, phase p/plan: a new plan."
  fi
  [[ -z "$kept" ]] || echo "The spec's draft is kept as $kept, out of the tree: the plan starts from it."
  exit 0
fi

[[ "$tier" == S ]] || die "restart.sh reopens an S task as L: this task is tier $tier already."
saved="$(mktemp -d)"
trap 'rm -rf "$saved"' EXIT

aborted=""
if git rev-parse -q --verify MERGE_HEAD >/dev/null; then
  bash "$OVERLOAD_SCRIPTS/sync.sh" --abort >/dev/null
  aborted=1
fi
base="$(journal_get base)"

# What goes back on the new branch, uncommitted as when the task opened.
cp -- "$JOURNAL_FILE" "$saved/journal.md"
keep=()
while IFS= read -r file; do
  keep+=("$file")
done < <(sed -n '/^## Inputs$/,/^## /s/^- //p' "$JOURNAL_FILE")
main_from_upstream "$main"
for file in "$CONFIG_FILE" "$(cfg backlog)"; do
  git cat-file -e "refs/heads/$main:$file" 2>/dev/null || keep+=("$file")
done
for file in ${keep[@]+"${keep[@]}"}; do
  [[ -f "$file" ]] || continue
  mkdir -p "$saved/files/$(dirname -- "$file")"
  cp -- "$file" "$saved/files/$file"
done

tip="$(git rev-parse --short HEAD)"
commits="$(git log --oneline "$base..HEAD")"
stash=""
if [[ -n "$(git status --porcelain -- . ":(exclude)$JOURNAL_FILE")" ]]; then
  git stash push --quiet --include-untracked -m "overload: the S attempt of $branch" -- . ":(exclude)$JOURNAL_FILE"
  stash="$(git stash list -n 1 --format=%gd)"
fi

git switch --quiet --force -C "$branch" "$main"

mkdir -p "$(dirname "$JOURNAL_FILE")"
awk '
  /^## / { skip = ($0 == "## Open findings"); print; if (skip) print ""; next }
  !skip { print }' "$saved/journal.md" >"$JOURNAL_FILE"
if [[ -d "$saved/files" ]]; then
  cp -R -- "$saved/files/." .
fi
journal set tier L
journal set phase l/spec
journal set base "$(git rev-parse --short HEAD)"
journal set verify_red_streak 0
journal log "tier L: $reason"
journal log "restarted from $(git rev-parse --short HEAD) of $main, without the S attempt's code"

rm -f "$(verified_file)" "$(integrated_file)"
bash "$OVERLOAD_SCRIPTS/suite.sh" clear

echo "On '$branch' again, from $main at $(git rev-parse --short HEAD): tier L, phase l/spec; the journal is kept, without its open findings."
[[ -z "$aborted" ]] || echo "The sync under way was aborted."
if [[ -n "$commits" ]]; then
  count="$(printf '%s\n' "$commits" | wc -l | tr -d ' ')"
  echo "Discarded $count commit$( ((count == 1)) || echo s) up to $tip, which git reflog $branch keeps:"
  printf '%s\n' "$commits" | head -n 10 | sed 's/^/  /'
  ((count <= 10)) || echo "  and $((count - 10)) more"
fi
[[ -z "$stash" ]] || echo "The uncommitted work is in $stash."
