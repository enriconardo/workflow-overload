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

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
in_project

usage() {
  echo "Usage: plan.sh check <plan> | item <plan> <n>" >&2
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
  *) usage ;;
esac
