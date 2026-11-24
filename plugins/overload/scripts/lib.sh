# shellcheck shell=bash
# Shared by the plugin's scripts: the project's config, the journal, the
# verified tree. Sourced, never run. Every script runs from the project's
# root, the directory Claude Code works in.

OVERLOAD_SCRIPTS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export OVERLOAD_SCRIPTS

CONFIG_FILE=".workflow/config"
JOURNAL_FILE=".workflow/journal.md"
# The test-author's throwaway reference model: the plugin's, not the project's.
# shellcheck disable=SC2034 # read by suite.sh
REFERENCE_DIR=".workflow/reference"
CONFIG_VERSION=1
# Every key of this version. `check` has no default: a config without it is
# refused, and a project with no checks writes `check =`, empty, on purpose.
CONFIG_KEYS="version check check_integrate run_tests run_integrate_tests main integrate rules backlog tests_glob integrate_tests_glob red_types"

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
  if [[ "$version" != "$CONFIG_VERSION" ]]; then
    echo "$CONFIG_FILE has version '$version', this plugin reads version $CONFIG_VERSION."
  else
    for k in ${keys[@]+"${keys[@]}"}; do
      [[ " $CONFIG_KEYS " == *" $k "* ]] && continue
      echo "'$k' is not a key of version $CONFIG_VERSION, whose keys are: ${CONFIG_KEYS// /, }."
    done
    ((has_check)) || echo "no 'check': the command that checks the tree before each commit, or 'check =' for a project with no checks."
  fi
}

require_config() {
  [[ -f "$CONFIG_FILE" ]] || die "no $CONFIG_FILE in this project: run /overload:setup first."
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

# with_files <command> <file>...: the command with its {files} replaced by
# the files, each quoted for bash.
with_files() {
  local command="$1" quoted="" file
  shift
  for file in "$@"; do
    quoted+="$(printf '%q' "$file") "
  done
  printf '%s\n' "${command//\{files\}/${quoted% }}"
}

current_branch() {
  git branch --show-current
}

on_task_branch() {
  local branch main
  branch="$(current_branch)"
  main="$(cfg main)"
  [[ -n "$branch" && "$branch" != "$main" ]] || die "on '${branch:-a detached HEAD}': this runs on a task's branch."
  [[ -f "$JOURNAL_FILE" ]] || die "'$branch' has no $JOURNAL_FILE: it is not a Workflow Overload task."
}

# Brings the local main up to its upstream, fast-forward only, without
# switching to it. Nothing to do without an upstream, or when main is ahead.
main_from_upstream() {
  local main="$1" remote old new
  remote="$(git config "branch.$main.remote" || true)"
  [[ -n "$remote" ]] || return 0
  git fetch --quiet "$remote" || die "cannot fetch '$main' from '$remote': settle that, then run this again."
  new="$(git rev-parse -q --verify "$main@{upstream}")" || return 0
  old="$(git rev-parse "refs/heads/$main")"
  [[ "$old" != "$new" ]] || return 0
  git merge-base --is-ancestor "$new" "$old" && return 0
  git merge-base --is-ancestor "$old" "$new" ||
    die "'$main' and its upstream have diverged: settle that by hand, then run this again."
  git update-ref "refs/heads/$main" "$new" "$old"
}

# The plugin's state for this clone: the verified tree and the runs' output.
# Inside .git, so that it never lands in a commit.
state_dir() {
  local dir
  dir="$(git rev-parse --git-path overload)"
  mkdir -p "$dir"
  printf '%s\n' "$dir"
}

# The tree of the working directory as a commit would record it, untracked
# files included and ignored files left out, without the journal: updating
# it never invalidates a verify. Built in an index of its own, so that the
# real index stays as it is.
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
  GIT_INDEX_FILE="$index" git rm -q --cached --ignore-unmatch -- "$JOURNAL_FILE" >/dev/null
  GIT_INDEX_FILE="$index" git write-tree
  rm -f "$index"
}

# The same hash for a commit's tree.
commit_tree_hash() {
  local index
  index="$(mktemp)"
  GIT_INDEX_FILE="$index" git read-tree "$1"
  GIT_INDEX_FILE="$index" git rm -q --cached --ignore-unmatch -- "$JOURNAL_FILE" >/dev/null
  GIT_INDEX_FILE="$index" git write-tree
  rm -f "$index"
}

verified_file() {
  printf '%s/verified\n' "$(state_dir)"
}

# The last green `verify.sh --integrate`, check_integrate included, as
# `<tree> <branch> <time> <main's commit>`: integrate.sh wants one on the
# branch since main last moved, not one on every tree, so that the slow tests
# run once per task and again after a sync, not after every fix.
integrated_file() {
  printf '%s/verified-integrate\n' "$(state_dir)"
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

# glob_pathspecs <key>: a key's comma-separated globs as git pathspecs, one
# per line.
glob_pathspecs() {
  local glob
  local -a globs=()
  IFS=',' read -ra globs <<<"$(cfg "$1")"
  for glob in ${globs[@]+"${globs[@]}"}; do
    glob="${glob#"${glob%%[![:space:]]*}"}"
    glob="${glob%"${glob##*[![:space:]]}"}"
    [[ -n "$glob" ]] && printf ':(glob)%s\n' "$glob"
  done
}

# Every test file as git pathspecs: those `check` runs (`tests_glob`) and
# those it leaves out (`integrate_tests_glob`), which the suite records and
# guards alike.
tests_pathspecs() {
  glob_pathspecs tests_glob
  glob_pathspecs integrate_tests_glob
}

# The config's test globs, for a message.
tests_globs() {
  local outside
  outside="$(cfg integrate_tests_glob)"
  printf 'tests_glob: %s%s\n' "$(cfg tests_glob)" "${outside:+; integrate_tests_glob: $outside}"
}

# outside_check <file>...: those of the files, present in the working tree,
# that `integrate_tests_glob` matches. They run through `run_integrate_tests`,
# the others through `run_tests`; a file both globs match is outside check,
# since a project sets that glob on purpose and the default `tests_glob` is
# broad.
outside_check() {
  local file
  local -a specs=()
  local -A matched=()
  mapfile -t specs < <(glob_pathspecs integrate_tests_glob)
  ((${#specs[@]})) || return 0
  while IFS= read -r file; do
    matched["$file"]=1
  done < <(git ls-files -c -o --exclude-standard -- "${specs[@]}")
  for file in "$@"; do
    [[ -n "${matched[$file]:-}" ]] && printf '%s\n' "$file"
  done
  return 0
}

# green_lists <branch>: the folder of a branch's green lists, the new tests
# a valid red found passing already, for the step review. A list is named
# after the HEAD it was made on: the next chunk, on another HEAD, finds none.
green_lists() {
  printf '%s/red-check-green/%s\n' "$(state_dir)" "$1"
}

# The green list of this branch and HEAD; the file exists after a valid red
# on them, empty when no new test passed.
green_list() {
  printf '%s/%s.txt\n' "$(green_lists "$(current_branch)")" "$(git rev-parse HEAD)"
}

# The config's `rules` entries, files and folders, one per line, trimmed.
rules_entries() {
  local entry
  local -a entries=()
  IFS=',' read -ra entries <<<"$(cfg rules)"
  for entry in ${entries[@]+"${entries[@]}"}; do
    entry="${entry#"${entry%%[![:space:]]*}"}"
    entry="${entry%"${entry##*[![:space:]]}"}"
    [[ -n "$entry" ]] && printf '%s\n' "$entry"
  done
  return 0
}

# docs_only <tree>: succeeds when the task is one of /overload:task that
# decides on main (a spec in the journal; a plan and no item; a change of
# a plan or spec main holds) and its changes from its base to <tree> are
# documents only: specs, plans, their inputs, the backlog, the files of the
# config's `rules` (a decision record added, marked superseded, a rule), in
# any change. Such a task closes without `check_integrate` and without the
# final review: its reviewer judged the spec or plan and its decision
# records, the human approved them, or the drop, at its checkpoint. The
# journal is never part of the change.
docs_only() {
  local tree="$1" base backlog entry file
  local -a rules=()
  [[ "$(journal_get command)" != build ]] || return 1
  [[ -n "$(journal_get spec)" || -n "$(journal_get change)" || (-n "$(journal_get plan)" && -z "$(journal_get item)") ]] || return 1
  base="$(journal_get base)"
  [[ -n "$base" ]] || return 1
  backlog="$(cfg backlog)"
  mapfile -t rules < <(rules_entries)
  while IFS= read -r file; do
    case "$file" in
      "$JOURNAL_FILE" | "$backlog" | .workflow/specs/* | .workflow/plans/* | .workflow/inputs/*) continue ;;
    esac
    for entry in ${rules[@]+"${rules[@]}"}; do
      entry="${entry%/}"
      [[ "$file" == "$entry" || "$file" == "$entry"/* ]] && continue 2
    done
    return 1
  done < <(git diff --name-only --no-renames "$base" "$tree")
  return 0
}

# is_acceptance: the task is a plan's acceptance, /overload:build <plan>: a
# build with a plan and no spec.
is_acceptance() {
  [[ "$(journal_get command)" == build && -z "$(journal_get spec)" && -n "$(journal_get plan)" ]]
}

# acceptance_without_fixes <tree>: succeeds on an acceptance whose changes
# from its base to <tree> are its plan alone, the steps' outcome: no code to
# review, though check_integrate still runs on the code the items built.
acceptance_without_fixes() {
  local base file plan
  is_acceptance || return 1
  base="$(journal_get base)" plan="$(journal_get plan)"
  [[ -n "$base" ]] || return 1
  while IFS= read -r file; do
    [[ "$file" == "$JOURNAL_FILE" || "$file" == "$plan" ]] || return 1
  done < <(git diff --name-only --no-renames "$base" "$1")
  return 0
}

# close_next <tree>: the step after a green `verify.sh --integrate` on the
# tree: close/write for a task of docs only that decides on main, whose
# lessons and backlog went to its checkpoint; close/lessons for an
# acceptance without fixes; close/review otherwise.
close_next() {
  if docs_only "$1"; then
    echo close/write
  elif acceptance_without_fixes "$1"; then
    echo close/lessons
  else
    echo close/review
  fi
}

# Phases set by the scripts: running a script is the decision, so its
# outcome moves the phase, only from the phases its header names, and only
# when what it checked is what the next phase needs. A red never moves it;
# any other phase is left alone.

# phase_to <phase>: sets the journal's phase, and says so.
phase_to() {
  bash "$OVERLOAD_SCRIPTS/journal.sh" set phase "$1"
  echo "phase: $1"
}

# phase_stays <why>: a phase the outcome could have moved, left as it is.
phase_stays() {
  echo "phase stays $(journal_get phase): $1"
}

# spec_chunks [<commit>]: the chunks of the journal's spec, a line each as
# spec.py prints them, from the working tree or from a commit (none when the
# commit lacks the spec). Fails with spec.py's message.
# shellcheck disable=SC2120 # the commit is optional
spec_chunks() {
  local spec
  spec="$(journal_get spec)"
  [[ -n "$spec" ]] || {
    echo "the journal names no spec" >&2
    return 1
  }
  if [[ -z "${1:-}" ]]; then
    python3 "$OVERLOAD_SCRIPTS/spec.py" chunks "$spec"
  elif git cat-file -e "$1:$spec" 2>/dev/null; then
    git show "$1:$spec" | python3 "$OVERLOAD_SCRIPTS/spec.py" chunks -
  fi
}

# next_chunk_phase <chunks>: the first open chunk's first step, or the close.
next_chunk_phase() {
  local n state first
  while IFS=$'\t' read -r n state _ first; do
    if [[ "$state" == open ]]; then
      echo "l/chunk-$n/$first"
      return
    fi
  done <<<"$1"
  echo close/check
}

suite_refs() {
  # for-each-ref matches a pattern up to a slash: the records of fix/x/y are
  # not those of fix/x/y-other.
  git for-each-ref --format='%(refname)' "refs/overload/suite/$1" | sort -V
}

# The plans: .workflow/plans/<name>.md, beside the specs. One is open at a
# time: approved on main, until its acceptance makes it done or a task drops
# it. An item of the open plan is worked by one task at a time, recorded
# under the state folder while its branch lives: the plan, on main, cannot
# tell an item whose branch is open from one nobody started. Its acceptance
# is recorded the same way, as the work `acceptance`.

# The plans and specs main's working tree tracks, a path per line.
tracked_plans() { git ls-files -- '.workflow/plans/*.md'; }
tracked_specs() { git ls-files -- '.workflow/specs/*.md'; }

# open_plans: the tracked plans with 'status: approved', a path per line.
open_plans() {
  local plan
  while IFS= read -r plan; do
    [[ -n "$plan" && "$(python3 "$OVERLOAD_SCRIPTS/spec.py" status "$plan")" == approved ]] && printf '%s\n' "$plan"
  done < <(tracked_plans)
  return 0
}

item_records_dir() {
  printf '%s/items\n' "$(state_dir)"
}

# record_item <plan> <n|acceptance> <command>: this branch works item <n>
# of <plan>, or its acceptance.
record_item() {
  local file
  file="$(item_records_dir)/$(current_branch)"
  mkdir -p "$(dirname "$file")"
  printf '%s\t%s\t%s\n' "$1" "$2" "$3" >"$file"
}

# item_records: `<branch> <plan> <n|acceptance> <command>` for each branch
# that works an item, or the acceptance, and still exists: a record whose
# branch is gone counts no more.
item_records() {
  local dir file branch
  dir="$(item_records_dir)"
  [[ -d "$dir" ]] || return 0
  while IFS= read -r file; do
    branch="${file#"$dir"/}"
    git show-ref --verify --quiet "refs/heads/$branch" || continue
    printf '%s\t%s\n' "$branch" "$(cat "$file")"
  done < <(find "$dir" -type f | sort)
}

# work_name <n|acceptance>: a record's work, for a message.
work_name() {
  if [[ "$1" == acceptance ]]; then echo "the acceptance"; else echo "item $1"; fi
}

# item_open_elsewhere <plan>: the first record of the plan on a branch other
# than this one, as `<branch> <n|acceptance> <command>`; fails when there is
# none.
item_open_elsewhere() {
  local branch plan n command current
  current="$(current_branch)"
  while IFS=$'\t' read -r branch plan n command; do
    if [[ "$plan" == "$1" && "$branch" != "$current" ]]; then
      printf '%s\t%s\t%s\n' "$branch" "$n" "$command"
      return 0
    fi
  done < <(item_records)
  return 1
}

# plan_in_head <plan>: dies unless HEAD holds the plan approved.
plan_in_head() {
  local status
  git cat-file -e "HEAD:$1" 2>/dev/null || die "$1 is not a file on $(cfg main): a task approves a plan, and its merge brings it there."
  status="$(git show "HEAD:$1" | python3 "$OVERLOAD_SCRIPTS/spec.py" status -)"
  [[ "$status" == approved ]] || die "$1 is not 'status: approved' but '${status:-none}': only the open plan has items to work, or changes."
}

# item_can_open <plan> <n>: prints `<n> <S|L> <title>` when a task can open
# the item of the plan, on main; dies with why it cannot.
item_can_open() {
  local plan="$1" n="$2" other line branch n_other
  local -a specs=()
  plan_in_head "$plan"
  if other="$(item_open_elsewhere "$plan")"; then
    IFS=$'\t' read -r branch n_other _ <<<"$other"
    die "$(work_name "$n_other") of $plan is open on branch $branch: one item at a time."
  fi
  mapfile -t specs < <(tracked_specs)
  line="$(python3 "$OVERLOAD_SCRIPTS/spec.py" opens "$plan" "$n" ${specs[@]+"${specs[@]}"} 2>&1)" ||
    die "${line#spec.py: }"
  printf '%s\n' "$line"
}

