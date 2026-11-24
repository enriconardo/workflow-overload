#!/usr/bin/env bash
set -euo pipefail

# Reads a plan for the main agent, which runs only the plugin's scripts.
#
#   plan.sh check <plan>     the plan's counts, or each way it is out of
#                            format: its requirements, items and acceptance
#                            steps, their IDs, coverage and dependencies
#   plan.sh item <plan> <n>  whether a task can open the item now: the plan
#                            approved on main, the item not ticked, its spec
#                            not approved yet, its dependencies ticked, and
#                            no other item started, on a branch or by a spec
#   plan.sh merge <plan> <n> the commit of main's own line that ticked the
#                            item, its task's merge, as `<sha> <subject>`:
#                            how an acceptance step names a version

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
in_project

usage() {
  echo "Usage: plan.sh check <plan> | item <plan> <n> | merge <plan> <n>" >&2
  exit 2
}

case "${1:-}" in
  check)
    (($# == 2)) || usage
    python3 "$OVERLOAD_SCRIPTS/spec.py" check "$2"
    ;;
  item)
    (($# == 3)) || usage
    require_config
    line="$(item_can_open "$2" "$3")"
    IFS=$'\t' read -r n tier title <<<"$line"
    echo "item $n ($tier estimated), $title: a task can open it"
    ;;
  merge)
    (($# == 3)) || usage
    require_config
    plan="$2" n="$3"
    main="$(cfg main)"
    # ticked <commit>: whether the plan, as the commit holds it, ticks item n.
    ticked() {
      git show "$1:$plan" 2>/dev/null | python3 "$OVERLOAD_SCRIPTS/spec.py" items - 2>/dev/null |
        awk -F'\t' -v n="$n" '$1 == n && $2 == "done" { found = 1 } END { exit !found }'
    }
    while IFS= read -r commit; do
      if ticked "$commit" && ! ticked "$commit^1"; then
        git log -1 --format='%h %s' "$commit"
        exit 0
      fi
    done < <(git log --first-parent --format=%H "refs/heads/$main" -- "$plan")
    die "item $n of $plan is not ticked on $main."
    ;;
  *) usage ;;
esac
