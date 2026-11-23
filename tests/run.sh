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

# run_test <file> <name> <log>: runs the test in a subshell, its output in the
# log, and sets `status` to its exit status. Never call it in a condition (if,
# while, &&, ||, !): bash ignores set -e in everything a condition runs, so a
# failing step would no longer stop the test. The canary below checks it.
run_test() {
  set +e
  (
    set -euo pipefail
    # shellcheck source=helpers.sh
    source "$TESTS_DIR/helpers.sh"
    # shellcheck disable=SC1090
    source "$1"
    setup_repo
    "$2"
  ) >"$3" 2>&1
  status=$?
  set -e
}

# The canary: a test whose failing step no assertion checks must fail, or a
# test that passes here proves nothing.
canary="$(mktemp)"
printf 'test_canary() {\n  false\n  true\n}\n' >"$canary"
run_test "$canary" test_canary /dev/null
if ((status == 0)); then
  echo "run.sh: a test passed past a failing step; this harness ignores set -e, refusing to run." >&2
  exit 2
fi
rm -f "$canary"

for file in "$TESTS_DIR"/*.test.sh; do
  mapfile -t names < <(bash -c "source '$TESTS_DIR/helpers.sh'; source '$file'; declare -F" | awk '$3 ~ /^test_/ { print $3 }')
  for name in "${names[@]}"; do
    [[ -z "$pattern" || "$name" == *"$pattern"* ]] || continue
    log="$(mktemp)"
    run_test "$file" "$name" "$log"
    if ((status == 0)); then
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
