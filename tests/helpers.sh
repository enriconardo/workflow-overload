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
  bash "$SCRIPTS/branch.sh" S docs "${1:-readme}" "${2:-describe-project}" "$(intent)" >/dev/null
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
