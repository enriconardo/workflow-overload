# shellcheck shell=bash
# Shared by the plugin's scripts: the project's config, the journal, the
# verified tree. Sourced, never run. Every script runs from the project's
# root, the directory Claude Code works in.

OVERLOAD_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export OVERLOAD_SCRIPTS

CONFIG_FILE=".workflow/config"
JOURNAL_FILE=".workflow/journal.md"
METRICS_FILE=".workflow/metrics.jsonl"
CONFIG_VERSION=1

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
    branch) echo '<type>/<scope>/<description>' ;;
    types) echo 'feature, fix, hotfix, refactor, test, docs, chore' ;;
    commit) echo '<type>(<scope>): <summary>' ;;
    commit_types) echo 'feat, fix, refactor, perf, test, docs, build, ci, chore' ;;
    subject_max) echo 72 ;;
    integrate) echo merge ;;
    backlog) echo .workflow/backlog.md ;;
    rules) echo CLAUDE.md ;;
    specs) echo .workflow/specs ;;
    tests_glob) echo '**/__tests__/**, **/*.test.*, **/*.spec.*, **/test_*.py, **/*_test.py, **/*_test.go' ;;
    red_types) echo 'AssertionError, NotImplemented' ;;
    reference) echo .workflow/reference ;;
    *) echo '' ;;
  esac
}

# config_get <key>: the value from OVERLOAD_<KEY> when that variable is set,
# even to empty (a cloud session without Docker empties `exec`), else from
# .workflow/config, else the default. Lines are `key = value`; a `#` after
# whitespace starts a comment; nothing is evaluated.
config_get() {
  local key="$1" var line k v found=""
  var="OVERLOAD_$(printf '%s' "$key" | tr '[:lower:]' '[:upper:]')"
  if [[ -n "${!var+x}" ]]; then
    printf '%s\n' "${!var}"
    return
  fi
  if [[ -f "$CONFIG_FILE" ]]; then
    while IFS= read -r line || [[ -n "$line" ]]; do
      line="${line%%[[:space:]]#*}"
      [[ "$line" == \#* ]] && continue
      [[ "$line" == *=* ]] || continue
      k="${line%%=*}"
      v="${line#*=}"
      k="${k//[[:space:]]/}"
      v="${v#"${v%%[![:space:]]*}"}"
      v="${v%"${v##*[![:space:]]}"}"
      if [[ "$k" == "$key" ]]; then
        found=1
        printf '%s\n' "$v"
      fi
    done <"$CONFIG_FILE"
  fi
  [[ -n "$found" ]] || config_default "$key"
}

require_config() {
  [[ -f "$CONFIG_FILE" ]] || die "no $CONFIG_FILE in this project: run /overload init first."
  local version
  version="$(config_get version | tail -n 1)"
  [[ "$version" == "$CONFIG_VERSION" ]] || die "$CONFIG_FILE has version '${version}', this plugin reads version $CONFIG_VERSION."
}

# The last value of a key, for keys given once.
cfg() {
  config_get "$1" | tail -n 1
}

# Runs a project command through the config's `exec` prefix, in bash, with
# pipefail, so that `verify | tail` cannot turn a red run green.
run_project() {
  local prefix
  prefix="$(cfg exec)"
  bash -o pipefail -c "${prefix:+$prefix }$1"
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
