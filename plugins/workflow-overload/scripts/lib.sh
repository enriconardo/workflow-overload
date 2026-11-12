# shellcheck shell=bash
# Shared by the plugin's scripts: the project's config, the journal, the
# verified tree. Sourced, never run. Every script runs from the project's
# root, the directory Claude Code works in.

OVERLOAD_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export OVERLOAD_SCRIPTS

CONFIG_FILE=".workflow/config"
JOURNAL_FILE=".workflow/journal.md"
METRICS_FILE=".workflow/metrics.jsonl"
# The test-author's throwaway reference model: the plugin's, not the project's.
REFERENCE_DIR=".workflow/reference"
CONFIG_VERSION=2
# Every key of this version. `check` has no default: a config without it is
# refused, and a project with no checks writes `check =`, empty, on purpose.
CONFIG_KEYS="version check run_tests main integrate rules backlog tests_glob red_types"

die() {
  echo "overload: $*" >&2
  exit 1
}

# The project's root, or a refusal outside a git work tree.
in_project() {
  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || die "not inside a git repository."
  cd "$root" || die "cannot enter $root."
}

# Defaults of the keys a config may leave out.
config_default() {
  case "$1" in
    main) echo main ;;
    integrate) echo merge ;;
    backlog) echo .workflow/backlog.md ;;
    rules) echo CLAUDE.md ;;
    tests_glob) echo '**/__tests__/**, **/*.test.*, **/*.spec.*, **/test_*.py, **/*_test.py, **/*_test.go' ;;
    red_types) echo 'AssertionError, NotImplemented' ;;
    *) echo '' ;;
  esac
}

# The config file's lines as `key<TAB>value`. Lines are `key = value`; a `#`
# after whitespace starts a comment; nothing is evaluated.
config_entries() {
  local line k v
  [[ -f "$CONFIG_FILE" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%[[:space:]]#*}"
    [[ "$line" == \#* ]] && continue
    [[ "$line" == *=* ]] || continue
    k="${line%%=*}"
    v="${line#*=}"
    k="${k//[[:space:]]/}"
    v="${v#"${v%%[![:space:]]*}"}"
    v="${v%"${v##*[![:space:]]}"}"
    printf '%s\t%s\n' "$k" "$v"
  done <"$CONFIG_FILE"
}

# config_get <key>: the value from OVERLOAD_<KEY> when that variable is set,
# even to empty (a session where the project's container is out of reach
# sets OVERLOAD_CHECK), else from .workflow/config, else the default.
config_get() {
  local key="$1" var k v found=""
  var="OVERLOAD_$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]')"
  if [[ -n "${!var+x}" ]]; then
    printf '%s\n' "${!var}"
    return
  fi
  while IFS=$'\t' read -r k v; do
    if [[ "$k" == "$key" ]]; then
      found=1
      printf '%s\n' "$v"
    fi
  done < <(config_entries)
  [[ -n "$found" ]] || config_default "$key"
}

# What became of a key of version 1 that version 2 does not have.
v1_key() {
  case "$1" in
    verify) echo "is 'check' in version 2" ;;
    test_files) echo "is 'run_tests' in version 2" ;;
    exec) echo "is gone in version 2: its prefix goes at the start of 'check' and 'run_tests'" ;;
    branch | types | commit | commit_types | subject_max) echo "is gone in version 2: names and messages follow the project's rules, and its commit-msg hook" ;;
    specs) echo "is gone in version 2: L specs are always in .workflow/specs" ;;
    reference) echo "is gone in version 2: the reference model is always in $REFERENCE_DIR" ;;
    stub) echo "is gone in version 2: a stub only throws the language's not-implemented error, whose name red_types holds" ;;
    probe_env) echo "is gone in version 2: the prober makes its own environment" ;;
    *) return 1 ;;
  esac
}

# Why the config cannot be read, a line each, then where to fix it; nothing
# when it can. Read from the file alone: an environment variable changes a
# value, not the config.
config_problems() {
  local found
  found="$(config_problems_found)"
  [[ -n "$found" ]] || return 0
  printf '%s\n' "$found"
  echo "Fix it on main, or, with a task open, on its branch in a commit of its own (verify.sh, then commit.sh)."
}

config_problems_found() {
  local k v version="" has_check=0
  local -a keys=()
  while IFS=$'\t' read -r k v; do
    [[ "$k" == version ]] && version="$v"
    [[ "$k" == check ]] && has_check=1
    keys+=("$k")
  done < <(config_entries)
  if [[ "$version" == 1 ]]; then
    echo "$CONFIG_FILE is version 1, this plugin reads version $CONFIG_VERSION. To migrate it: set version = 2; rename verify to check, test_files to run_tests; put the exec prefix, if any, at the start of both commands; remove exec, branch, types, commit, commit_types, subject_max, specs, stub, reference and probe_env."
  elif [[ "$version" != "$CONFIG_VERSION" ]]; then
    echo "$CONFIG_FILE has version '$version', this plugin reads version $CONFIG_VERSION."
  else
    for k in ${keys[@]+"${keys[@]}"}; do
      [[ " $CONFIG_KEYS " == *" $k "* ]] && continue
      if v="$(v1_key "$k")"; then
        echo "'$k' $v."
      else
        echo "'$k' is not a key of version $CONFIG_VERSION, whose keys are: ${CONFIG_KEYS// /, }."
      fi
    done
    ((has_check)) || echo "no 'check': the command that checks the tree before each commit, or 'check =' for a project with no checks."
  fi
}

require_config() {
  [[ -f "$CONFIG_FILE" ]] || die "no $CONFIG_FILE in this project: run /overload setup first."
  local problems
  problems="$(config_problems)"
  [[ -z "$problems" ]] || die "$CONFIG_FILE is refused:
$problems"
}

# The last value of a key, for keys given once.
cfg() {
  config_get "$1" | tail -n 1
}

# Runs a project command in bash, with pipefail, so that `check | tail`
# cannot turn a red run green.
run_project() {
  bash -o pipefail -c "$1"
}

current_branch() {
  git branch --show-current
}

on_task_branch() {
  local branch main
  branch="$(current_branch)"
  main="$(cfg main)"
  [[ -n "$branch" && "$branch" != "$main" ]] || die "on '${branch:-a detached HEAD}': this runs on a task's branch."
  [[ -f "$JOURNAL_FILE" ]] || die "'$branch' has no $JOURNAL_FILE: it is not an /overload task."
}

# The plugin's state for this clone: verified trees and run logs. Inside .git,
# so that it never lands in a commit.
state_dir() {
  local dir
  dir="$(git rev-parse --git-path overload)"
  mkdir -p "$dir"
  printf '%s\n' "$dir"
}

# The tree of the working directory as a commit would record it, untracked
# files included and ignored files left out, without the journal and the
# metrics: updating those never invalidates a verify. Built in an index of
# its own, so that the real index stays as it is.
work_tree_hash() {
  local index
  index="$(mktemp)"
  # From HEAD's tree, not a copy of the index: a copied index carries stat
  # data that a same-size edit within the same second matches, and git then
  # takes the old content for the file's. Entries read from a tree have none,
  # so every file is hashed.
  if git rev-parse --verify --quiet HEAD >/dev/null; then
    GIT_INDEX_FILE="$index" git read-tree HEAD
  else
    rm -f "$index"
  fi
  GIT_INDEX_FILE="$index" git add -A >/dev/null 2>&1 || {
    rm -f "$index"
    die "git add failed while hashing the working tree."
  }
  GIT_INDEX_FILE="$index" git rm -q --cached --ignore-unmatch -- "$JOURNAL_FILE" "$METRICS_FILE" >/dev/null
  GIT_INDEX_FILE="$index" git write-tree
  rm -f "$index"
}

# The same hash for a commit's tree.
commit_tree_hash() {
  local index
  index="$(mktemp)"
  GIT_INDEX_FILE="$index" git read-tree "$1"
  GIT_INDEX_FILE="$index" git rm -q --cached --ignore-unmatch -- "$JOURNAL_FILE" "$METRICS_FILE" >/dev/null
  GIT_INDEX_FILE="$index" git write-tree
  rm -f "$index"
}

verified_file() {
  printf '%s/verified\n' "$(state_dir)"
}

# Succeeds when the working tree is the one the last green verify checked.
is_verified() {
  local file
  file="$(verified_file)"
  [[ -f "$file" ]] || return 1
  [[ "$(cut -d' ' -f1 "$file")" == "$(work_tree_hash)" ]]
}

now() {
  date -u +%Y-%m-%dT%H:%M:%SZ
}

# journal_get <key>: a `key: value` line of the journal's header.
journal_get() {
  [[ -f "$JOURNAL_FILE" ]] || return 0
  sed -n "s/^$1: *//p" "$JOURNAL_FILE" | head -n 1
}

# The config's `tests_glob` as git pathspecs, one per line.
tests_pathspecs() {
  local glob
  IFS=',' read -ra globs <<<"$(cfg tests_glob)"
  for glob in "${globs[@]}"; do
    glob="${glob#"${glob%%[![:space:]]*}"}"
    glob="${glob%"${glob##*[![:space:]]}"}"
    [[ -n "$glob" ]] && printf ':(glob)%s\n' "$glob"
  done
}

suite_refs() {
  # for-each-ref matches a pattern up to a slash: the records of fix/x/y are
  # not those of fix/x/y-other.
  git for-each-ref --format='%(refname)' "refs/overload/suite/$1" | sort -V
}
