#!/usr/bin/env bash
set -euo pipefail

# Runs every tests/*.test.sh. Each test is a function named test_*, run in a
# subshell inside a fresh temporary git repository, so that one test cannot
# leak into the next. `tests/run.sh [pattern]` runs the tests whose name
# matches the pattern.

TESTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export SCRIPTS="$TESTS_DIR/../plugins/overload/scripts"
pattern="${1:-}"
passed=0
failed=0
failures=()

for file in "$TESTS_DIR"/*.test.sh; do
  mapfile -t names < <(bash -c "source '$TESTS_DIR/helpers.sh'; source '$file'; declare -F" | awk '$3 ~ /^test_/ { print $3 }')
  for name in "${names[@]}"; do
    [[ -z "$pattern" || "$name" == *"$pattern"* ]] || continue
    log="$(mktemp)"
    if (
      set -euo pipefail
      # shellcheck source=helpers.sh
      source "$TESTS_DIR/helpers.sh"
      # shellcheck disable=SC1090
      source "$file"
      setup_repo
      "$name"
    ) >"$log" 2>&1; then
      passed=$((passed + 1))
      echo "ok   $(basename "$file") $name"
    else
      failed=$((failed + 1))
      failures+=("$(basename "$file") $name")
      echo "FAIL $(basename "$file") $name"
      sed 's/^/     | /' "$log"
    fi
    rm -f "$log"
  done
done

echo
echo "$passed passed, $failed failed"
((failed == 0))
