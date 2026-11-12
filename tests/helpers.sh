# shellcheck shell=bash
# Helpers of the tests: a throwaway project with a config whose verify reads
# a file, so that a test decides whether verify is green or red.

setup_repo() {
  WORK="$(mktemp -d)"
  export HOME="$WORK/home"
  mkdir -p "$HOME"
  export CLAUDE_CONFIG_DIR="$HOME/.claude"
  git config --global user.email test@example.com
  git config --global user.name Test
  git config --global init.defaultBranch main
  # Keep the variables of a cloud session out of the tests.
  unset OVERLOAD_EXEC OVERLOAD_VERIFY
  REPO="$WORK/repo"
  mkdir -p "$REPO" && cd "$REPO" || exit 1
  git init -q
  mkdir -p .workflow
  cat >.workflow/config <<'EOF'
version = 1
exec    =                      # nothing: the commands run here
verify  = bash check.sh        # green unless the file red exists
main    = main
EOF
  cat >check.sh <<'EOF'
echo "checking"
if [[ -f red ]]; then echo "Failed: red exists"; exit 1; fi
echo "all good"
EOF
  echo "# demo" >README.md
  git add -A
  git commit -q -m "chore(repo): start"
}

intent() {
  printf 'Problem: the README is short.\nGoal: say what the project does.\n' >"$WORK/intent.md"
  printf '%s\n' "$WORK/intent.md"
}

open_task() {
  bash "$SCRIPTS/branch.sh" S "${1:-docs/readme/describe-project}" "$(intent)" >/dev/null
}

message() {
  printf '%s\n\n%s\n' "$1" "${2:-Why it changes.}" >"$WORK/message.txt"
  printf '%s\n' "$WORK/message.txt"
}

fail() {
  echo "assertion failed: $*" >&2
  exit 1
}

# expect_fail <text> <command...>: the command fails and prints the text.
expect_fail() {
  local text="$1" out
  shift
  if out="$("$@" 2>&1)"; then
    fail "expected a failure of '$*', it succeeded: $out"
  fi
  [[ "$out" == *"$text"* ]] || fail "expected '$text' in the output of '$*', got: $out"
}

expect_eq() {
  [[ "$1" == "$2" ]] || fail "expected '$2', got '$1'${3:+ ($3)}"
}

# set_config <key> <value>: replaces the key's line of the config.
set_config() {
  grep -v "^$1[[:space:]]*=" .workflow/config >"$WORK/config" || true
  printf '%s = %s\n' "$1" "$2" >>"$WORK/config"
  mv "$WORK/config" .workflow/config
}

# A runner that prints JUnit XML as vitest does, from the files' own lines:
# `case <name> <assert|notimpl|pass|skip|typeerror>`, or `load` for a file
# that fails to load.
fake_runner() {
  cat >"$REPO/runner.py" <<'PY'
import sys
from xml.sax.saxutils import quoteattr as q
print("some log line the runner prints")
print('<?xml version="1.0" encoding="UTF-8" ?>\n<testsuites>')
for path in sys.argv[1:]:
    lines = open(path).read().split("\n")
    print('<testsuite name=%s>' % q(path))
    if "load" in lines:
        print('<testcase classname=%s name=%s><failure message="Cannot find module" type="Error"/></testcase>' % (q(path), q(path)))
    for line in lines:
        if line.startswith("case "):
            _, name, kind = line.split(" ")
            body = {"assert": '<failure message="expected 1 to be 2" type="AssertionError"/>',
                    "notimpl": '<failure message="" type="NotImplemented"/>',
                    "typeerror": '<failure message="x is not a function" type="TypeError"/>',
                    "skip": "<skipped/>", "pass": ""}[kind]
            print('<testcase classname=%s name=%s>%s</testcase>' % (q(path), q(name), body))
    print("</testsuite>")
print("</testsuites>")
PY
  set_config test_files 'python3 runner.py {files}'
  git add -A && git commit -qm "chore(repo): fake runner"
}

open_l_task() {
  bash "$SCRIPTS/branch.sh" L "${1:-feature/greet/default-name}" "$(intent)" >/dev/null
}

# refusing_hook <name> <max>: a hook in core.hooksPath that refuses a message
# whose subject is over <max> characters.
refusing_hook() {
  mkdir -p "$WORK/hooks"
  # shellcheck disable=SC2016 # the hook's own code, expanded when it runs
  printf '#!/usr/bin/env bash\n(( $(head -n 1 "$1" | wc -m) <= %d )) || { echo "subject over %d" >&2; exit 1; }\n' \
    "$(($2 + 1))" "$2" >"$WORK/hooks/$1"
  chmod +x "$WORK/hooks/$1"
  git config core.hooksPath "$WORK/hooks"
}
