#!/usr/bin/env bash
set -euo pipefail

# Commits the working tree of a task's branch, only when it is the tree the
# last green verify checked. Everything goes in, the journal included: one
# commit is one logical change, so code, review fixes and lessons are
# separate runs of verify and of this script. The message is the model's,
# written to the project's rules; the project's hooks judge it, and a commit
# whose tree a pre-commit hook changed is undone. With a sync under way
# (sync.sh), the commit is the merge's.
#
#   commit.sh <message-file>
#
# The commit moves the phase, in the journal it commits: from s/implement to
# close/check when it changes more than the config; from close/check to
# close/review when its tree is the one verify.sh --integrate checked, or to
# close/write on a task of docs only that decides on main (lib.sh's
# docs_only); from l/checkpoint to close/check when it holds the spec
# approved with a chunk to build, which ends a spec task; from p/checkpoint
# to close/check when it holds the plan approved, in format, with no item
# ticked, which ends a plan task, or ticked as main had them, on a revision;
# from d/checkpoint to close/check when it holds the dropped spec or plan
# with its reason; from any step of l/chunk-<n> to the next
# open chunk's first step, or close/check, when it ticks chunk <n> and no
# other.

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

# A sync's merge is committed even when it changes no file: main must be in
# the branch's history.
if [[ -z "$(git status --porcelain)" && ! -f "$(git rev-parse --git-path MERGE_HEAD)" ]]; then
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
verified_tree="$(cut -d' ' -f1 "$(verified_file)")"
if [[ "$(commit_tree_hash "$(git write-tree)")" != "$verified_tree" ]]; then
  git reset -q
  die "the staged tree differs from the verified one: run verify.sh again, then commit."
fi

# The phase after the commit, from what it holds, decided on the staged tree
# so that the commit holds its journal with the new phase.
phase="$(journal_get phase)"
next="" stays=""
case "$phase" in
  s/implement)
    if [[ -n "$(git diff --cached --name-only --no-renames HEAD -- . ":(exclude)$CONFIG_FILE" ":(exclude)$JOURNAL_FILE")" ]]; then
      next=close/check
    else
      stays="the commit changes only the config."
    fi
    ;;
  close/check)
    read -r checked checked_on _ 2>/dev/null <"$(integrated_file)" || checked="" checked_on=""
    if [[ "$checked" == "$verified_tree" && "$checked_on" == "$(current_branch)" ]]; then
      next=close/review
      ! docs_only "$verified_tree" || next=close/write
    else
      stays="verify.sh --integrate did not check this tree."
    fi
    ;;
  l/checkpoint)
    spec="$(journal_get spec)"
    if [[ -n "$spec" && -f "$spec" && "$(python3 "$OVERLOAD_SCRIPTS/spec.py" status "$spec")" == approved ]]; then
      if ! chunks="$(spec_chunks 2>&1)"; then
        stays="$chunks"
      elif [[ "$(next_chunk_phase "$chunks")" == close/check ]]; then
        stays="the spec has no chunk left to build."
      else
        next=close/check
      fi
    else
      stays="the commit holds no spec with 'status: approved'."
    fi
    ;;
  p/checkpoint)
    plan="$(journal_get plan)"
    if [[ -z "$plan" || ! -f "$plan" || "$(python3 "$OVERLOAD_SCRIPTS/spec.py" status "$plan")" != approved ]]; then
      stays="the commit holds no plan with 'status: approved'."
    elif ! items="$(python3 "$OVERLOAD_SCRIPTS/spec.py" items "$plan" 2>&1)"; then
      stays="$items"
    elif [[ -z "$(journal_get change)" ]] && ticked="$(awk -F'\t' '$2 == "done" { print $1; exit }' <<<"$items")" && [[ -n "$ticked" ]]; then
      stays="item $ticked is ticked: a plan reaches main with no item ticked."
    else
      next=close/check
    fi
    ;;
  d/checkpoint)
    change="$(journal_get change)"
    if [[ -z "$change" || ! -f "$change" ]]; then
      stays="the journal names no spec or plan to drop that exists."
    elif ! reason="$(python3 "$OVERLOAD_SCRIPTS/spec.py" dropped "$change" 2>&1)"; then
      stays="${reason#spec.py: "$change": }."
    else
      next=close/check
    fi
    ;;
  l/chunk-*/*)
    n="${phase#l/chunk-}" n="${n%%/*}"
    if ! before="$(spec_chunks HEAD 2>&1)"; then
      stays="$before"
    elif ! after="$(spec_chunks 2>&1)"; then
      stays="$after"
    else
      ticked="$(awk -F'\t' 'NR == FNR { if ($2 == "done") done[$1] = 1; next } $2 == "done" && !done[$1] { print $1 }' \
        <(printf '%s\n' "$before") <(printf '%s\n' "$after"))"
      if [[ "$ticked" == "$n" ]]; then
        next="$(next_chunk_phase "$after")"
      else
        stays="the commit does not tick chunk $n alone."
      fi
    fi
    ;;
esac
if [[ -n "$next" ]]; then
  bash "$OVERLOAD_SCRIPTS/journal.sh" set phase "$next"
  git add -- "$JOURNAL_FILE"
fi
# A commit refused or undone leaves the phase as it was.
phase_back() {
  [[ -z "$next" ]] || bash "$OVERLOAD_SCRIPTS/journal.sh" set phase "$phase"
}

if ! git commit --quiet -F "$message"; then
  phase_back
  die "git refused the commit, most likely through a hook of the project: its output is above. Fix what it says (verify again after changing a file), then commit again."
fi
# A pre-commit hook that rewrites staged files (lint-staged, a formatter)
# changes the tree after the check: the commit must be the verified tree.
committed="$(commit_tree_hash HEAD)"
if [[ "$committed" != "$verified_tree" ]]; then
  changed="$(git diff --name-only --no-renames "$verified_tree" "$committed")"
  # A sync's merge undone stays a merge under way.
  other="$(git rev-parse -q --verify HEAD^2 || true)"
  git reset -q --soft HEAD^
  [[ -z "$other" ]] || printf '%s\n' "$other" >"$(git rev-parse --git-path MERGE_HEAD)"
  phase_back
  die "a hook changed the commit's tree after verify checked it: the commit is undone, the hook's changes are in the working tree. Verify them, then commit again. The files it changed:
$changed"
fi
git log -1 --format='committed %h %s'
if [[ -n "$next" ]]; then
  echo "phase: $next"
elif [[ -n "$stays" ]]; then
  echo "phase stays $phase: $stays"
fi
