#!/usr/bin/env bash
set -euo pipefail

# Integrates a task's branch after the human's go at the last checkpoint:
# refuses a tree that is not the verified one; a branch that does not hold
# main, brought up to its upstream first (sync.sh takes it in); and, when the
# config has a `check_integrate`, a branch where `verify.sh --integrate` has
# not run green since main last moved. Then merges with --no-ff into main
# without the journal, whose result is the branch's verified tree, and
# deletes the branch and its records. A branch with a spec holds it as its
# command leaves it: approved with a chunk to build after /overload:task,
# done after /overload:build. A plan task brings its plan approved, in
# format, no item ticked, and no other plan open on main. A task on an item
# of the plan changes no other item, which only a revision does, and leaves
# its item ticked, but for the task of an L item's spec, whose build ticks
# it. A change of a decision main holds (the journal's `change`) changes
# that plan or spec as its tier allows: a revision (P) changes no item
# ticked, ticks none, and changes none a branch works; a drop (D) leaves
# the document dropped with its reason and its plan's items as they are.
# Either drops, with its reason, the approved spec of each item it removes
# or drops, and changes no other spec or plan. A refusal leaves main as it
# was.
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

dirty="$(git status --porcelain -- . ":(exclude)$JOURNAL_FILE")"
[[ -z "$dirty" ]] || die "the working tree has uncommitted changes: verify and commit them first.
$dirty"

verified="$(verified_file)"
[[ -f "$verified" && "$(cut -d' ' -f1 "$verified")" == "$(commit_tree_hash HEAD)" ]] ||
  die "HEAD is not the tree the last green verify checked: run verify.sh first."

git show-ref --verify --quiet "refs/heads/$main" || die "no local '$main' to integrate into."
main_from_upstream "$main"
git merge-base --is-ancestor "$main" HEAD ||
  die "'$main' moved since '$branch' last took it in: run sync.sh, verify and commit the merge, then integrate again."

# The slow but local tests, when the project has them, ran green on this
# branch since main last moved: once per task, again after a sync.
integrated="$(integrated_file)"
if [[ -n "$(cfg check_integrate)" ]]; then
  read -r _ ran_on _ ran_with 2>/dev/null <"$integrated" || ran_on="" ran_with=""
  [[ "$ran_on" == "$branch" && "$ran_with" == "$(git rev-parse -q --verify "refs/heads/$main" || echo none)" ]] ||
    die "check_integrate has not run green on '$branch' since '$main' last moved: run verify.sh --integrate, then integrate again."
fi

# The spec is in the state its command leaves it: a task's approved, with a
# chunk left to build; a build's done, every chunk ticked.
spec="$(journal_get spec)"
if [[ -n "$spec" ]]; then
  [[ -f "$spec" ]] || die "the journal's spec '$spec' does not exist."
  status="$(python3 "$OVERLOAD_SCRIPTS/spec.py" status "$spec")"
  chunks="$(python3 "$OVERLOAD_SCRIPTS/spec.py" chunks "$spec" 2>&1)" || die "$chunks"
  if [[ "$(journal_get command)" == build ]]; then
    if grep -q $'\topen\t' <<<"$chunks"; then
      die "$spec has chunks not ticked:
$(grep '^- \[ \]' "$spec")"
    fi
    [[ "$status" == "done" ]] || die "$spec is not 'status: done': set it, verify and commit, then integrate."
  else
    [[ "$status" == approved ]] || die "$spec is not 'status: approved': the human approves it at the checkpoint, then it is committed."
    grep -q $'\topen\t' <<<"$chunks" || die "$spec has no chunk left to build: /overload:build would have nothing to do."
  fi
fi

# The plan as its task leaves it, and an item's task within its item.
plan="$(journal_get plan)"
item="$(journal_get item)"
if [[ -n "$plan" ]]; then
  [[ -f "$plan" ]] || die "the journal's plan '$plan' does not exist."
  items="$(python3 "$OVERLOAD_SCRIPTS/spec.py" items "$plan" 2>&1)" || die "$plan is out of format:
$items"
  plan_status="$(python3 "$OVERLOAD_SCRIPTS/spec.py" status "$plan")"
  [[ "$plan_status" == approved ]] || die "$plan is not 'status: approved' but '${plan_status:-none}': the human approves it at the checkpoint, then it is committed."
  if [[ -n "$(journal_get change)" ]]; then
    : # a revision, checked below
  elif [[ -z "$item" ]]; then
    ticked="$(awk -F'\t' '$2 == "done" { print $1; exit }' <<<"$items")"
    [[ -z "$ticked" ]] || die "item $ticked of $plan is ticked: a plan reaches main with no item ticked."
    other="$(open_plans | grep -vxF -- "$plan" | head -n 1 || true)"
    [[ -z "$other" ]] || die "a plan is open on main already, $other: one plan at a time."
  else
    was="$(mktemp)"
    if ! git show "refs/heads/$main:$plan" >"$was" 2>/dev/null; then
      rm -f "$was"
      die "$main has no $plan: the item's plan is gone."
    fi
    if ! changes="$(python3 "$OVERLOAD_SCRIPTS/spec.py" revision "$was" "$plan" 2>&1)"; then
      rm -f "$was"
      die "the task changes $plan as no revision may: $changes"
    fi
    rm -f "$was"
    others="$(awk -F'\t' -v n="$item" '$1 != n { printf "%s%s", sep, $1; sep = ", " }' <<<"$changes")"
    [[ -z "$others" ]] || die "the task changes item $others of $plan: a revision of the plan goes through /overload:task $plan."
    state="$(awk -F'\t' -v n="$item" '$1 == n { print $2 }' <<<"$items")"
    if [[ -n "$spec" && "$(journal_get command)" != build ]]; then
      linked="$(python3 "$OVERLOAD_SCRIPTS/spec.py" link "$spec" 2>&1)" || die "$linked"
      IFS=$'\t' read -r linked_plan linked_item <<<"$linked"
      [[ "$linked_plan" == "$plan" && "$linked_item" == "$item" ]] ||
        die "$spec names item ${linked_item:-none} of ${linked_plan:-no plan}, not the task's: plan: $plan and item: $item."
      [[ "$state" != "done" ]] || die "item $item of $plan is ticked: the build of its spec ticks it."
    else
      [[ "$state" == "done" ]] || die "item $item of $plan is not ticked: the task's last commit ticks it."
    fi
  fi
fi

# A change of a decision main holds: the open plan revised or dropped, a
# spec approved and not built dropped.
change="$(journal_get change)"
if [[ -n "$change" ]]; then
  tier="$(journal_get tier)"
  [[ -f "$change" ]] || die "the journal's change '$change' does not exist."
  was="$(mktemp)"
  trap 'rm -f "$was"' EXIT
  git show "refs/heads/$main:$change" >"$was" 2>/dev/null || die "$main has no $change: only a decision main holds changes."
  was_status="$(python3 "$OVERLOAD_SCRIPTS/spec.py" status "$was")"
  [[ "$was_status" == approved ]] || die "$change is '${was_status:-none}' on $main: only an approved plan or spec changes."
  changed_plan="" dropped_items=""
  if [[ "$tier" == D ]]; then
    reason="$(python3 "$OVERLOAD_SCRIPTS/spec.py" dropped "$change" 2>&1)" ||
      die "$change is not dropped with its reason: ${reason#spec.py: "$change": }."
  fi
  case "$change" in
    .workflow/plans/*)
      changed_plan="$change"
      changes="$(python3 "$OVERLOAD_SCRIPTS/spec.py" revision "$was" "$change" 2>&1)" ||
        die "the task changes $change as no revision may: $changes"
      if [[ "$tier" == D ]]; then
        [[ -z "$changes" ]] || die "dropping $change changes its item $(cut -f1 <<<"$changes" | paste -sd, - | sed 's/,/, /g'): a drop leaves the items as they are."
        if other="$(item_open_elsewhere "$change")"; then
          IFS=$'\t' read -r other_branch other_item _ <<<"$other"
          die "item $other_item of $change is open on branch $other_branch: stop that task, or end it, before the drop."
        fi
        dropped_items="all"
      else
        items="$(python3 "$OVERLOAD_SCRIPTS/spec.py" items "$change")"
        while IFS=$'\t' read -r n kind; do
          [[ -n "$n" ]] || continue
          while IFS=$'\t' read -r other_branch of other_item _; do
            [[ "$of" == "$change" && "$other_item" == "$n" && "$other_branch" != "$branch" ]] &&
              die "item $n of $change is open on branch $other_branch: a revision changes no item a task works."
          done < <(item_records)
          if [[ "$kind" == changed && "$(awk -F'\t' -v n="$n" '$1 == n { print $2 }' <<<"$items")" == "done" ]]; then
            die "the revision ticks item $n: the task that ends an item ticks it."
          fi
          dropped_items+=" $n "
        done <<<"$changes"
      fi
      ;;
    .workflow/specs/*)
      linked="$(python3 "$OVERLOAD_SCRIPTS/spec.py" link "$was" 2>/dev/null || true)"
      if [[ -n "$linked" ]]; then
        IFS=$'\t' read -r linked_plan linked_item <<<"$linked"
        while IFS=$'\t' read -r other_branch of other_item _; do
          [[ "$of" == "$linked_plan" && "$other_item" == "$linked_item" && "$other_branch" != "$branch" ]] &&
            die "item $other_item of $linked_plan is open on branch $other_branch: stop that task, or end it, before the drop."
        done < <(item_records)
      fi
      ;;
  esac
  # The specs main holds approved for the items the change removes or drops:
  # each is dropped, with its reason, in this task.
  allowed=" "
  [[ "$change" != .workflow/specs/* ]] || allowed+="$change "
  if [[ -n "$changed_plan" ]]; then
    while IFS= read -r spec_path; do
      [[ -n "$spec_path" ]] || continue
      text="$(git show "refs/heads/$main:$spec_path")"
      [[ "$(python3 "$OVERLOAD_SCRIPTS/spec.py" status - <<<"$text")" == approved ]] || continue
      linked="$(python3 "$OVERLOAD_SCRIPTS/spec.py" link - <<<"$text" 2>/dev/null)" || continue
      IFS=$'\t' read -r linked_plan linked_item <<<"$linked"
      [[ "$linked_plan" == "$changed_plan" ]] || continue
      [[ "$dropped_items" == all || "$dropped_items" == *" $linked_item "* ]] || continue
      allowed+="$spec_path "
      [[ "$(python3 "$OVERLOAD_SCRIPTS/spec.py" status "$spec_path" 2>/dev/null)" == dropped ]] && continue
      if [[ "$tier" == D ]]; then
        die "dropping $change drops the approved spec of its item $linked_item, $spec_path: drop it in this task."
      elif ! grep -qx "$linked_item"$'\tremoved' <<<"$changes"; then
        continue
      fi
      die "item $linked_item of $change goes, and main holds its spec $spec_path approved: drop it in this task."
    done < <(git ls-tree -r --name-only "refs/heads/$main" -- .workflow/specs/)
  fi
  while IFS= read -r file; do
    case "$file" in
      .workflow/plans/*)
        [[ "$file" == "$changed_plan" ]] || die "the task changes $file: a change of $change changes no other plan."
        ;;
      .workflow/specs/*)
        [[ "$allowed" == *" $file "* ]] ||
          die "the task changes $file, which is not the spec of an item it changes or removes: a change of $change drops those specs alone."
        reason="$(python3 "$OVERLOAD_SCRIPTS/spec.py" dropped "$file" 2>&1)" ||
          die "the task changes $file, which it may only drop, with its reason: ${reason#spec.py: "$file": }."
        ;;
    esac
  done < <(git diff --name-only --no-renames "refs/heads/$main" HEAD -- .workflow/plans/ .workflow/specs/)
fi

# The journal is tracked on the branch: a local edit to it would block the
# switch, and the merge drops the file anyway.
git checkout --quiet -- "$JOURNAL_FILE" 2>/dev/null || true
git switch --quiet "$main"

back_to_branch() {
  git merge --abort 2>/dev/null || true
  git switch --quiet "$branch"
}

if ! git merge --no-ff --no-commit --quiet "$branch" >/dev/null 2>&1; then
  conflicts="$(git diff --name-only --diff-filter=U)"
  back_to_branch
  die "merging '$branch' into '$main' conflicts; '$main' is unchanged. Ask the human. Conflicting files:
$conflicts"
fi

git rm -q -f --ignore-unmatch -- "$JOURNAL_FILE"

# The subject branch.sh ran the project's commit-msg hook on: git's own
# adds " into <main>" when main is not the default branch.
if ! git commit --quiet -m "Merge branch '$branch'"; then
  back_to_branch
  die "the commit of the merge was refused (a commit-msg hook?); '$main' is unchanged."
fi
# The branch is the merge's second parent, so all of it is in main; -d would
# measure against the branch's upstream instead, and refuse one pushed and
# then committed on.
git branch -q -D "$branch"
for ref in $(git for-each-ref --format='%(refname)' "refs/overload/suite/$branch" "refs/overload/base/$branch"); do
  git update-ref -d "$ref"
done
rm -f "$verified" "$integrated"
rm -rf "$(state_dir)/kept/$branch" "$(green_lists "$branch")"
rm -f "$(item_records_dir)/$branch"
git log -1 --format="integrated '$branch' into '$main' as %h %s"
