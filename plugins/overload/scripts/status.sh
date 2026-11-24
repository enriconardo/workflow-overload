#!/usr/bin/env bash
set -uo pipefail

# What the skills read before they decide what to do: the config, the
# branch, the journal's header and whether the tree is verified; on main,
# the specs to build and the open plan with its next item and the command
# that works it, or its acceptance once every item is ticked: open on a
# branch, failed at some steps, or to run. Never fails, so that a skill
# always loads.

# shellcheck source=lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

# plan_lines <plan>: the plan's counts or problems, and on main its next
# item with the command that works it.
plan_lines() {
  local plan="$1" counts branch of n command next state tier spec title failed
  local -a args=()
  if ! counts="$(python3 "$OVERLOAD_SCRIPTS/spec.py" check "$plan" 2>&1)"; then
    echo "$plan, refused:"
    printf '%s\n' "$counts" | sed "s|^spec.py: $plan: |  - |"
    return 0
  fi
  echo "$plan, $counts"
  [[ "$(current_branch)" == "$(cfg main)" ]] || return 0
  while IFS=$'\t' read -r branch of n command; do
    [[ "$of" == "$plan" && "$n" != acceptance ]] && args+=(--started "$n")
  done < <(item_records)
  mapfile -t -O "${#args[@]}" args < <(tracked_specs)
  next="$(python3 "$OVERLOAD_SCRIPTS/spec.py" next "$plan" ${args[@]+"${args[@]}"} 2>&1)" || {
    echo "  - next: none, $next"
    return 0
  }
  if [[ "$next" == acceptance ]]; then
    while IFS=$'\t' read -r branch of n command; do
      if [[ "$of" == "$plan" && "$n" == acceptance ]]; then
        echo "  - every item ticked, its acceptance open on branch $branch, where /overload:build resumes it"
        return 0
      fi
    done < <(item_records)
    failed="$(python3 "$OVERLOAD_SCRIPTS/spec.py" steps "$plan" | awk -F'\t' '$2 == "failed" { printf "%s%s", sep, $1; sep = ", " }')"
    if [[ -n "$failed" ]]; then
      echo "  - every item ticked, its acceptance failed at step $failed → /overload:task $plan <the change> adds the items that fix it; then /overload:build $plan runs it again"
    else
      echo "  - every item ticked → its acceptance: /overload:build $plan"
    fi
    return 0
  fi
  IFS=$'\t' read -r n state tier spec title <<<"$next"
  printf '  - next: item %s (%s estimated), %s' "$n" "$tier" "$title"
  if [[ "$state" == open ]]; then
    echo " → /overload:task $plan $n"
    return 0
  fi
  while IFS=$'\t' read -r branch of n command; do
    if [[ "$of" == "$plan" && "$n" != acceptance ]]; then
      echo ": open on branch $branch, where /overload:$command resumes it"
      return 0
    fi
  done < <(item_records)
  echo ": its spec $spec is approved → /overload:build $spec"
}

root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "- repository: none (not inside a git work tree)"
  exit 0
}
cd "$root" || exit 0

echo "- scripts: $OVERLOAD_SCRIPTS"
echo "- branch: $(current_branch || echo '(detached)')"
git rev-parse -q --verify HEAD >/dev/null || echo "- repository: no commit yet"
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "- config: none ($CONFIG_FILE is missing)"
else
  problems="$(config_problems)"
  if [[ -n "$problems" ]]; then
    echo "- config: refused"
    printf '%s\n' "$problems" | sed 's/^/  - /'
  else
    echo "- config:"
    for key in $CONFIG_KEYS; do
      printf '  - %s = %s\n' "$key" "$(cfg "$key")"
    done
    [[ -n "$(cfg check)" ]] || echo "  - check is empty: every commit passes unchecked, until a task brings the project's checks"
    for key in $CONFIG_KEYS; do
      var="OVERLOAD_$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]')"
      [[ -n "${!var+x}" ]] && echo "  - ($key comes from \$$var)"
    done
  fi
fi
if [[ -f "$JOURNAL_FILE" ]]; then
  echo "- journal: $JOURNAL_FILE"
  sed -n '/^## /q; /^[a-z_]*: /s/^/  - /p' "$JOURNAL_FILE"
  spec="$(journal_get spec)"
  if [[ -n "$spec" && -f "$spec" ]]; then
    echo "- spec: $spec, status $(python3 "$OVERLOAD_SCRIPTS/spec.py" status "$spec")"
    python3 "$OVERLOAD_SCRIPTS/spec.py" chunks "$spec" 2>&1 | while IFS=$'\t' read -r n state type first; do
      if [[ "$state" == open ]]; then
        echo "  - chunk $n: open, $type, first step $first"
      elif [[ "$state" == "done" ]]; then
        echo "  - chunk $n: done"
      else
        echo "  - $n"
      fi
    done
  fi
  plan="$(journal_get plan)"
  if [[ -n "$plan" && -z "$(journal_get item)" && -f "$plan" ]]; then
    echo "- plan: $(plan_lines "$plan")"
  fi
  if is_verified 2>/dev/null; then
    echo "- working tree: verified"
  else
    echo "- working tree: not verified since its last change"
  fi
else
  echo "- journal: none on this branch"
  # On main, what /overload:build takes: the approved specs with a chunk
  # left to build; a done or dropped one is not listed.
  if [[ "$(current_branch)" == "$(cfg main)" ]]; then
    mapfile -t specs < <(git ls-files -- '.workflow/specs/*.md')
    ready="$( ((${#specs[@]})) && python3 "$OVERLOAD_SCRIPTS/spec.py" ready "${specs[@]}")"
    if [[ -z "$ready" ]]; then
      echo "- specs to build: none"
    else
      echo "- specs to build:"
      printf '%s\n' "$ready" | sed 's/\t/: /; s/^/  - /'
    fi
    mapfile -t plans < <(open_plans)
    ((${#plans[@]})) || echo "- open plan: none"
    for plan in ${plans[@]+"${plans[@]}"}; do
      echo "- open plan: $(plan_lines "$plan")"
    done
  fi
fi
dirty="$(git status --porcelain | head -n 10)"
if [[ -n "$dirty" ]]; then
  echo "- uncommitted changes:"
  printf '%s\n' "$dirty" | sed 's/^/  /'
fi
exit 0
