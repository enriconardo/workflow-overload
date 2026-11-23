# shellcheck shell=bash
# The S path's scripts: config, branch, journal, verify, commit, integrate,
# and the hooks. Run by tests/run.sh, each test in a fresh repository.

source_lib() {
  # shellcheck source=../plugins/overload/scripts/lib.sh
  source "$SCRIPTS/lib.sh"
}

test_config_reads_values_comments_and_defaults() {
  source_lib
  expect_eq "$(cfg check)" "bash check.sh"
  expect_eq "$(cfg run_tests)" "" "default"
  expect_eq "$(cfg integrate)" "merge" "default"
  expect_eq "$(cfg red_types)" "AssertionError, NotImplemented" "default"
}

test_config_env_overrides_even_when_empty() {
  source_lib
  echo 'run_tests = ./dev.sh exec pytest {files}' >>.workflow/config
  expect_eq "$(cfg run_tests)" "./dev.sh exec pytest {files}"
  expect_eq "$(OVERLOAD_RUN_TESTS='' cfg run_tests)" ""
  expect_eq "$(OVERLOAD_CHECK='make check' cfg check)" "make check"
}

test_config_refuses_another_version() {
  set_config version 2
  expect_fail "has version '2', this plugin reads version 1" bash "$SCRIPTS/verify.sh"
  expect_fail "on main, or" bash "$SCRIPTS/verify.sh"
  [[ "$(bash "$SCRIPTS/status.sh")" == *"config: refused"*"version '2'"*"on main, or"* ]] || fail "status: $(bash "$SCRIPTS/status.sh")"
}

test_config_refuses_a_key_it_does_not_know() {
  echo 'tests_glb = **/*.test.ts' >>.workflow/config
  expect_fail "'tests_glb' is not a key of version 1" bash "$SCRIPTS/verify.sh"
  [[ "$(bash "$SCRIPTS/status.sh")" == *"config: refused"*"tests_glb"* ]] || fail "status: $(bash "$SCRIPTS/status.sh")"
}

test_config_missing_points_to_setup() {
  rm .workflow/config
  expect_fail "run /overload:setup first" bash "$SCRIPTS/verify.sh"
}

test_config_refuses_a_config_without_check() {
  grep -v '^check' .workflow/config >"$WORK/config" && mv "$WORK/config" .workflow/config
  expect_fail "no 'check'" bash "$SCRIPTS/verify.sh"
  echo 'check =' >>.workflow/config
  bash "$SCRIPTS/verify.sh" | grep -q "nothing checked" || fail "an empty check refused"
}

test_branch_opens_task_with_journal() {
  open_task
  expect_eq "$(git branch --show-current)" "docs/readme/describe-project"
  expect_eq "$(bash "$SCRIPTS/journal.sh" get tier)" "S"
  expect_eq "$(bash "$SCRIPTS/journal.sh" get phase)" "s/implement"
  expect_eq "$(bash "$SCRIPTS/journal.sh" get command)" "task"
  # base is a short sha, which may be all digits
  expect_eq "$(sed -n '/^## /q; /^base:/d; /^[a-z_]*: [0-9]*$/p' .workflow/journal.md)" "verify_red_streak: 0" "the only counter"
  grep -q "Goal: say what the project does." .workflow/journal.md || fail "intent missing from the journal"
}

test_branch_refuses_bad_names_and_states() {
  expect_fail "not a valid branch name" bash "$SCRIPTS/branch.sh" S "docs/bad name" "$(intent)"
  expect_fail "is the main branch" bash "$SCRIPTS/branch.sh" S main "$(intent)"
  expect_fail "tier is S or L" bash "$SCRIPTS/branch.sh" M docs/readme "$(intent)"
  expect_fail "Usage" bash "$SCRIPTS/branch.sh" S docs readme "$(intent)"
  echo change >>README.md
  expect_fail "uncommitted changes" bash "$SCRIPTS/branch.sh" S docs/readme "$(intent)"
  git checkout -q README.md
  git branch docs/readme
  expect_fail "exists already" bash "$SCRIPTS/branch.sh" S docs/readme "$(intent)"
  git switch -q -c other
  expect_fail "a task starts from main" bash "$SCRIPTS/branch.sh" S docs/other "$(intent)"
}

test_branch_takes_the_name_whole() {
  bash "$SCRIPTS/branch.sh" S "EN-209_Snapshot.diff" "$(intent)" >/dev/null
  expect_eq "$(git branch --show-current)" "EN-209_Snapshot.diff"
  expect_eq "$(bash "$SCRIPTS/journal.sh" get branch)" "EN-209_Snapshot.diff"
}

test_branch_refuses_a_name_the_commit_msg_hook_refuses_at_the_merge() {
  refusing_hook commit-msg 72
  expect_fail "subject over 72" bash "$SCRIPTS/branch.sh" S \
    "docs/a-very-long-description-that-goes-on-and-on-and-on-forever" "$(intent)"
  expect_fail "Merge branch 'docs/a-very-long" bash "$SCRIPTS/branch.sh" S \
    "docs/a-very-long-description-that-goes-on-and-on-and-on-forever" "$(intent)"
  expect_eq "$(git branch --show-current)" "main" "no branch for a refused name"
  bash "$SCRIPTS/branch.sh" S docs/short "$(intent)" >/dev/null
  expect_eq "$(git branch --show-current)" "docs/short"
}

test_branch_says_when_git_is_too_old_to_run_the_hook() {
  refusing_hook commit-msg 10
  mkdir -p "$WORK/bin"
  # shellcheck disable=SC2016 # the wrapper's own code, expanded when it runs
  printf '#!/usr/bin/env bash\n[[ "$1" != version && "$1" != --version ]] || { echo "git version 2.35.1"; exit 0; }\nexec %q "$@"\n' \
    "$(command -v git)" >"$WORK/bin/git"
  chmod +x "$WORK/bin/git"
  out="$(PATH="$WORK/bin:$PATH" bash "$SCRIPTS/branch.sh" S docs/readme/describe-project "$(intent)")"
  [[ "$out" == *"git 2.35"*"not checked"* ]] || fail "$out"
  expect_eq "$(git branch --show-current)" "docs/readme/describe-project"
}

test_without_hooks_no_name_or_subject_is_too_long() {
  bash "$SCRIPTS/branch.sh" S \
    "docs/a-very-long-description-that-goes-on-and-on-and-on-forever" "$(intent)" >/dev/null
  echo "More." >>README.md
  bash "$SCRIPTS/verify.sh" >/dev/null
  bash "$SCRIPTS/commit.sh" "$(message "docs(readme): $(printf 'x%.0s' {1..90})")" >/dev/null
}

test_branch_copies_the_inputs_into_their_folder() {
  mkdir -p "$WORK/in" "$WORK/other"
  printf 'The brief.\n' >"$WORK/in/brief.md"
  printf '\x89PNG\x00\x01' >"$WORK/in/mock up.png"
  bash "$SCRIPTS/branch.sh" L feature/greet/default-name "$(intent)" \
    --inputs 2026-11-17-greet "$WORK/in/brief.md" "$WORK/in/mock up.png" >/dev/null
  cmp -s "$WORK/in/brief.md" .workflow/inputs/2026-11-17-greet/brief.md || fail "brief not copied"
  cmp -s "$WORK/in/mock up.png" ".workflow/inputs/2026-11-17-greet/mock up.png" || fail "mockup not copied"
  expect_eq "$(sed -n '/^## Inputs/,/^## Open/p' .workflow/journal.md | grep '^- ')" \
    "$(printf -- '- .workflow/inputs/2026-11-17-greet/brief.md\n- .workflow/inputs/2026-11-17-greet/mock up.png')"
  bash "$SCRIPTS/verify.sh" >/dev/null
  bash "$SCRIPTS/commit.sh" "$(message 'docs(greet): spec')" >/dev/null
  git cat-file -e "HEAD:.workflow/inputs/2026-11-17-greet/brief.md" || fail "inputs not committed"
}

test_branch_refuses_inputs_it_cannot_take() {
  mkdir -p "$WORK/in" "$WORK/other"
  echo a >"$WORK/in/brief.md"
  echo b >"$WORK/other/brief.md"
  expect_fail "Usage" bash "$SCRIPTS/branch.sh" S docs/x "$(intent)" --inputs only-a-slug
  expect_fail "Usage" bash "$SCRIPTS/branch.sh" S docs/x "$(intent)" --input slug "$WORK/in/brief.md"
  expect_fail "not a file" bash "$SCRIPTS/branch.sh" S docs/x "$(intent)" --inputs slug "$WORK/in/missing.md"
  expect_fail "not a file" bash "$SCRIPTS/branch.sh" S docs/x "$(intent)" --inputs slug "$WORK/in"
  expect_fail "two inputs named 'brief.md'" bash "$SCRIPTS/branch.sh" S docs/x "$(intent)" --inputs slug "$WORK/in/brief.md" "$WORK/other/brief.md"
  expect_fail "not a folder name" bash "$SCRIPTS/branch.sh" S docs/x "$(intent)" --inputs ../up "$WORK/in/brief.md"
  mkdir -p .workflow/inputs/taken && echo x >.workflow/inputs/taken/old.md
  git add -A && git commit -qm "chore(repo): an older input"
  expect_fail "exists already" bash "$SCRIPTS/branch.sh" S docs/x "$(intent)" --inputs taken "$WORK/in/brief.md"
  expect_eq "$(git branch --show-current)" "main" "no branch for refused inputs"
}

test_journal_set_inc_log() {
  open_task
  bash "$SCRIPTS/journal.sh" set phase s/review
  expect_eq "$(bash "$SCRIPTS/journal.sh" get phase)" "s/review"
  expect_eq "$(bash "$SCRIPTS/journal.sh" inc verify_red_streak)" "1"
  bash "$SCRIPTS/journal.sh" set lessons 2
  expect_eq "$(bash "$SCRIPTS/journal.sh" get lessons)" "2"
  bash "$SCRIPTS/journal.sh" log "review found nothing"
  tail -n 1 .workflow/journal.md | grep -q "review found nothing" || fail "log line missing"
  # a new key lands in the header, before the first section
  expect_eq "$(sed -n '/^## /q; /^lessons:/p' .workflow/journal.md)" "lessons: 2"
}

test_journal_keeps_a_file_where_a_later_session_finds_it() {
  open_task
  printf 'map of the code\n' >"$WORK/map.md"
  out="$(bash "$SCRIPTS/journal.sh" keep map "$WORK/map.md")"
  kept="$(git rev-parse --git-path overload)/kept/docs/readme/describe-project/map.md"
  [[ "$out" == *"$kept"* ]] || fail "$out"
  rm "$WORK/map.md"
  expect_eq "$(cat "$kept")" "map of the code" "the copy outlives the file"
  grep -q "^- .* map: $kept$" .workflow/journal.md || fail "not logged: $(cat .workflow/journal.md)"
  expect_fail "not a name" bash "$SCRIPTS/journal.sh" keep "../x" "$kept"
  expect_fail "not a file" bash "$SCRIPTS/journal.sh" keep map "$WORK/none.md"
  verified_commit "More."
  # another task, opened while this one waits, keeps a file of the same name
  git switch -q main
  open_task docs/readme/other
  printf 'map of the other\n' >"$WORK/map.md"
  bash "$SCRIPTS/journal.sh" keep map "$WORK/map.md" >/dev/null
  expect_eq "$(cat "$kept")" "map of the code" "the first task's map"
  # another file, so that the first task's sync takes main in without a conflict
  echo "Other." >OTHER.md
  bash "$SCRIPTS/verify.sh" >/dev/null
  bash "$SCRIPTS/commit.sh" "$(message "docs(other): Other.")" >/dev/null
  bash "$SCRIPTS/integrate.sh" >/dev/null
  [[ -f "$kept" ]] || fail "the merge of the other task removed the first task's files"
  [[ ! -e "$(git rev-parse --git-path overload)/kept/docs/readme/other" ]] || fail "kept after the merge"
  git switch -q docs/readme/describe-project
  bash "$SCRIPTS/sync.sh" >/dev/null
  bash "$SCRIPTS/verify.sh" >/dev/null
  bash "$SCRIPTS/commit.sh" "$(message "Merge branch 'main' into docs/readme/describe-project")" >/dev/null
  bash "$SCRIPTS/integrate.sh" >/dev/null
  [[ ! -e "$kept" ]] || fail "kept after the merge"
}

test_branch_keeps_the_explorer_s_map() {
  printf 'map of the code\n' >"$WORK/map.md"
  printf 'The brief.\n' >"$WORK/brief.md"
  expect_fail "not a file" bash "$SCRIPTS/branch.sh" L feature/greet/x "$(intent)" --map "$WORK/none.md"
  expect_fail "Usage" bash "$SCRIPTS/branch.sh" L feature/greet/x "$(intent)" --map
  expect_eq "$(git branch --show-current)" "main" "no branch for a refused map"
  bash "$SCRIPTS/branch.sh" L feature/greet/x "$(intent)" --map "$WORK/map.md" --inputs greet "$WORK/brief.md" >/dev/null
  kept="$(git rev-parse --git-path overload)/kept/feature/greet/x/map.md"
  expect_eq "$(cat "$kept")" "map of the code"
  grep -q "^- .* map: $kept$" .workflow/journal.md || fail "not logged: $(cat .workflow/journal.md)"
  [[ -f .workflow/inputs/greet/brief.md ]] || fail "inputs lost"
}

test_branch_keeps_the_intent_inside_its_section() {
  printf '## Problem\nThe README is short.\n# Goal\nSay more.\n' >"$WORK/headed.md"
  bash "$SCRIPTS/branch.sh" S docs/readme/describe-project "$WORK/headed.md" >/dev/null
  expect_eq "$(grep -c '^## ' .workflow/journal.md)" "5" "only the journal's own sections"
  grep -qx '#### Problem' .workflow/journal.md || fail "heading not demoted"
}

test_verify_green_records_the_tree_and_red_does_not() {
  open_task
  echo "More." >>README.md
  bash "$SCRIPTS/verify.sh" | grep -q "verify: green" || fail "verify not green"
  source_lib
  is_verified || fail "tree not recorded as verified"
  touch red
  expect_fail "verify: red" bash "$SCRIPTS/verify.sh"
  is_verified && fail "a red run left the tree verified"
  expect_eq "$(bash "$SCRIPTS/journal.sh" get verify_red_streak)" "1"
  [[ ! -e "$(git rev-parse --git-path overload)/runs.log" ]] || fail "run log written"
}

test_verify_without_a_command_records_the_tree_unchecked() {
  set_config check ''
  git add -A && git commit -qm "chore(repo): no check"
  open_task
  echo "More." >>README.md
  out="$(bash "$SCRIPTS/verify.sh")"
  [[ "$out" == *"no 'check' command"*"nothing checked"* ]] || fail "$out"
  source_lib
  is_verified || fail "tree not recorded"
  [[ ! -e "$(git rev-parse --git-path overload)/runs.log" ]] || fail "run log written"
  bash "$SCRIPTS/commit.sh" "$(message 'docs(readme): say more')" >/dev/null
}

test_verify_red_is_red_through_a_pipe_in_the_command() {
  set_config check 'bash check.sh | cat' 
  git commit -qam "chore(repo): pipe"
  open_task
  touch red
  expect_fail "verify: red" bash "$SCRIPTS/verify.sh"
}

test_verify_is_red_when_the_check_changes_a_file_git_does_not_ignore() {
  echo "*.log" >.gitignore
  set_config check 'bash check.sh; date >run.log; [[ ! -f fix ]] || echo fixed >>README.md'
  git add -A && git commit -qm "chore(repo): a check that writes"
  open_task
  echo "More." >>README.md
  bash "$SCRIPTS/verify.sh" | grep -q "verify: green" || fail "an ignored file made it red"
  touch fix
  if out="$(bash "$SCRIPTS/verify.sh" 2>&1)"; then fail "green: $out"; fi
  [[ "$out" == *"verify: red"*"changed files git does not ignore"*"README.md"* ]] || fail "$out"
  [[ "$out" != *"  fix"* ]] || fail "a file the check did not change is listed: $out"
  source_lib
  is_verified && fail "a check that changed the tree left it verified"
  expect_eq "$(bash "$SCRIPTS/journal.sh" get verify_red_streak)" "1"
}

test_verify_third_red_asks_the_human() {
  open_task
  touch red
  bash "$SCRIPTS/verify.sh" >/dev/null 2>&1 || true
  bash "$SCRIPTS/verify.sh" >/dev/null 2>&1 || true
  expect_fail "Stop and ask the human" bash "$SCRIPTS/verify.sh"
}

test_verify_sees_a_same_size_edit_made_in_the_same_second() {
  open_task
  echo "aaaa" >notes.txt
  git add notes.txt
  echo "bbbb" >notes.txt
  bash "$SCRIPTS/verify.sh" >/dev/null
  bash "$SCRIPTS/commit.sh" "$(message 'docs(readme): add notes')" >/dev/null
  expect_eq "$(git show HEAD:notes.txt)" "bbbb" "the committed content"
  expect_eq "$(git status --porcelain)" "" "a clean tree after the commit"
}

test_journal_edits_do_not_invalidate_verify() {
  open_task
  echo "More." >>README.md
  bash "$SCRIPTS/verify.sh" >/dev/null
  bash "$SCRIPTS/journal.sh" log "verified"
  source_lib
  is_verified || fail "a journal edit invalidated the verify"
  echo "Again." >>README.md
  is_verified && fail "a change to README kept the verify"
  true
}

test_commit_needs_a_verified_tree_and_a_subject() {
  open_task
  echo "More." >>README.md
  expect_fail "not the one the last green verify checked" bash "$SCRIPTS/commit.sh" "$(message 'docs(readme): say what it does')"
  bash "$SCRIPTS/verify.sh" >/dev/null
  printf '# a comment\n\n' >"$WORK/no-subject.txt"
  expect_fail "no subject line" bash "$SCRIPTS/commit.sh" "$WORK/no-subject.txt"
  # the subject's form is the project's rules', and its hooks': none here
  [[ "$(bash "$SCRIPTS/commit.sh" "$(message 'Update README')")" == "committed "* ]] || fail "no commit"
  git show --name-only --format= HEAD | grep -qx .workflow/journal.md || fail "journal not committed"
  echo "Again." >>README.md
  expect_fail "not the one the last green verify checked" bash "$SCRIPTS/commit.sh" "$(message 'docs(readme): again')"
}

test_commit_undoes_a_commit_whose_tree_a_pre_commit_hook_changed() {
  # as lint-staged does: the hook rewrites a staged file and stages it again
  mkdir -p "$WORK/hooks"
  printf '#!/usr/bin/env bash\ngrep -qx formatted README.md || { echo formatted >>README.md; git add README.md; }\n' >"$WORK/hooks/pre-commit"
  chmod +x "$WORK/hooks/pre-commit"
  git config core.hooksPath "$WORK/hooks"
  open_task
  echo "More." >>README.md
  bash "$SCRIPTS/verify.sh" >/dev/null
  before="$(git rev-parse HEAD)"
  if out="$(bash "$SCRIPTS/commit.sh" "$(message 'docs(readme): say more')" 2>&1)"; then
    fail "committed a tree verify did not check: $out"
  fi
  [[ "$out" == *"changed the commit's tree"*"README.md"* ]] || fail "$out"
  expect_eq "$(git rev-parse HEAD)" "$before" "the commit undone"
  expect_eq "$(bash "$SCRIPTS/journal.sh" get phase)" s/implement "the phase of an undone commit"
  grep -qx formatted README.md || fail "the hook's change lost"
  bash "$SCRIPTS/verify.sh" >/dev/null
  bash "$SCRIPTS/commit.sh" "$(message 'docs(readme): say more')" >/dev/null
  expect_eq "$(git show HEAD:README.md | tail -n 1)" "formatted"
}

test_commit_reports_a_refusal_of_the_commit_msg_hook() {
  open_task
  refusing_hook commit-msg 20
  echo "More." >>README.md
  bash "$SCRIPTS/verify.sh" >/dev/null
  before="$(git rev-parse HEAD)"
  expect_fail "subject over 20" bash "$SCRIPTS/commit.sh" "$(message 'docs(readme): a subject over twenty')"
  expect_fail "git refused the commit" bash "$SCRIPTS/commit.sh" "$(message 'docs(readme): a subject over twenty')"
  expect_eq "$(git rev-parse HEAD)" "$before" "nothing committed"
  expect_eq "$(bash "$SCRIPTS/journal.sh" get phase)" s/implement "the phase of a refused commit"
  bash "$SCRIPTS/commit.sh" "$(message 'docs(x): short')" >/dev/null
}

test_commit_refuses_main_and_branches_without_journal() {
  echo "More." >>README.md
  expect_fail "runs on a task's branch" bash "$SCRIPTS/commit.sh" "$(message 'docs(readme): x')"
}

verified_commit() {
  echo "$1" >>README.md
  bash "$SCRIPTS/verify.sh" >/dev/null
  bash "$SCRIPTS/commit.sh" "$(message "docs(readme): $1")" >/dev/null
}

test_integrate_merges_without_journal() {
  open_task
  verified_commit "more"
  bash "$SCRIPTS/journal.sh" log "checkpoint: go"
  out="$(bash "$SCRIPTS/integrate.sh")"
  [[ "$out" == *"integrated 'docs/readme/describe-project'"* ]] || fail "not integrated: $out"
  expect_eq "$(git branch --show-current)" "main"
  git show-ref --verify --quiet refs/heads/docs/readme/describe-project && fail "branch not deleted"
  expect_eq "$(git log -1 --format=%s)" "Merge branch 'docs/readme/describe-project'"
  expect_eq "$(git rev-list --count HEAD^1..HEAD^2)" "1"
  [[ -f .workflow/journal.md ]] && fail "journal on main"
  [[ ! -e .workflow/metrics.jsonl ]] || fail "measures written"
  [[ -z "$(git status --porcelain)" ]] || fail "dirty after integrate"
}

test_integrate_deletes_a_branch_whose_upstream_is_behind() {
  # Pushed once, then committed on: git branch -d measures against the
  # upstream and refuses, though the branch is all in main.
  git init -q --bare "$WORK/remote.git"
  git remote add origin "$WORK/remote.git"
  open_task
  git push -q -u origin docs/readme/describe-project
  verified_commit "more"
  out="$(bash "$SCRIPTS/integrate.sh")"
  [[ "$out" == *"integrated 'docs/readme/describe-project'"* ]] || fail "not integrated: $out"
  if git show-ref --verify --quiet refs/heads/docs/readme/describe-project; then fail "branch not deleted"; fi
}

test_integrate_keeps_the_merge_subject_short_on_a_long_main() {
  # A main of 25 characters: git's own subject would add " into <main>".
  git switch -q -c chore/repo/overload-trial-a
  set_config main chore/repo/overload-trial-a
  git add -A && git commit -qm "chore(repo): trial base"
  mkdir -p .githooks
  # shellcheck disable=SC2016 # the hook's own code, expanded when it runs
  printf '#!/usr/bin/env bash\n(( $(head -n1 "$1" | wc -m) <= 73 )) || { echo "subject too long" >&2; exit 1; }\n' >.githooks/commit-msg
  chmod +x .githooks/commit-msg
  git config core.hooksPath .githooks
  git add -A && git commit -qm "chore(repo): hook"
  bash "$SCRIPTS/branch.sh" S docs/readme/describe-the-project-in-detail "$(intent)" >/dev/null
  verified_commit "more"
  out="$(bash "$SCRIPTS/integrate.sh")"
  [[ "$out" == *"integrated"* ]] || fail "not integrated: $out"
  expect_eq "$(git log -1 --format=%s)" "Merge branch 'docs/readme/describe-the-project-in-detail'"
}

test_integrate_refused_commit_leaves_main_intact() {
  open_task
  verified_commit "more"
  main_before="$(git rev-parse main)"
  mkdir -p "$WORK/hooks"
  printf '#!/usr/bin/env bash\necho "refused by a hook" >&2; exit 1\n' >"$WORK/hooks/commit-msg"
  chmod +x "$WORK/hooks/commit-msg"
  git config core.hooksPath "$WORK/hooks"
  expect_fail "the commit of the merge was refused" bash "$SCRIPTS/integrate.sh"
  expect_eq "$(git rev-parse main)" "$main_before" "main unchanged"
  expect_eq "$(git branch --show-current)" "docs/readme/describe-project"
  [[ -f .workflow/journal.md ]] || fail "journal lost"
  [[ -z "$(git status --porcelain)" ]] || fail "dirty: $(git status --porcelain)"
}

slow_check() {
  cat >slow.sh <<'EOF'
echo "slow tests"
if [[ -f slow-red ]]; then echo "Failed: slow-red exists"; exit 1; fi
EOF
  set_config check_integrate 'bash slow.sh'
  git add -A && git commit -qm "chore(repo): slow tests"
}

test_verify_integrate_runs_check_integrate_after_check() {
  slow_check
  open_task
  echo "More." >>README.md
  out="$(bash "$SCRIPTS/verify.sh")"
  [[ "$out" == *"verify: green"* && "$out" != *"check_integrate"* ]] || fail "a plain verify: $out"
  out="$(bash "$SCRIPTS/verify.sh" --integrate)"
  [[ "$out" == *"verify: green"*"check_integrate"* ]] || fail "$out"
  touch slow-red
  if out="$(bash "$SCRIPTS/verify.sh" --integrate 2>&1)"; then fail "green: $out"; fi
  [[ "$out" == *"slow-red exists"*"verify: red"*"check_integrate"* ]] || fail "$out"
  source_lib
  is_verified && fail "a red check_integrate left the tree verified"
  expect_eq "$(bash "$SCRIPTS/journal.sh" get verify_red_streak)" "1"
  touch red
  if out="$(bash "$SCRIPTS/verify.sh" --integrate 2>&1)"; then fail "green: $out"; fi
  [[ "$out" != *"slow tests"* ]] || fail "check_integrate ran after a red check: $out"
}

test_verify_integrate_without_check_integrate_runs_check_only() {
  open_task
  echo "More." >>README.md
  out="$(bash "$SCRIPTS/verify.sh" --integrate)"
  [[ "$out" == *"verify: green"*"no 'check_integrate'"* ]] || fail "$out"
  expect_fail "usage" bash "$SCRIPTS/verify.sh" --integrated
}

test_integrate_needs_check_integrate_green_since_main_last_moved() {
  slow_check
  open_task
  verified_commit "more"
  expect_fail "verify.sh --integrate" bash "$SCRIPTS/integrate.sh"
  bash "$SCRIPTS/verify.sh" --integrate >/dev/null
  # a fix after the run needs check, not the slow tests again
  verified_commit "again"
  move_main
  bash "$SCRIPTS/sync.sh" >/dev/null
  bash "$SCRIPTS/verify.sh" >/dev/null
  bash "$SCRIPTS/commit.sh" "$(message "Merge branch 'main'")" >/dev/null
  expect_fail "since 'main' last moved" bash "$SCRIPTS/integrate.sh"
  bash "$SCRIPTS/verify.sh" --integrate >/dev/null
  out="$(bash "$SCRIPTS/integrate.sh")"
  [[ "$out" == *"integrated"* ]] || fail "not integrated: $out"
}

test_integrate_refuses_an_unverified_head() {
  open_task
  verified_commit "more"
  echo "x" >>README.md
  expect_fail "uncommitted changes" bash "$SCRIPTS/integrate.sh"
  git checkout -q README.md
  rm -f "$(git rev-parse --git-path overload)/verified"
  expect_fail "not the tree the last green verify checked" bash "$SCRIPTS/integrate.sh"
}

move_main() {
  git switch -q main
  echo "${2:-other}" >"${1:-other.txt}"
  git add -A && git commit -qm "chore(repo): move main"
  git switch -q docs/readme/describe-project
}

test_integrate_refuses_a_main_that_moved_and_leaves_it_intact() {
  open_task
  verified_commit "more"
  move_main
  before="$(git rev-parse main)"
  bash "$SCRIPTS/journal.sh" log "an edit to keep"
  expect_fail "sync.sh" bash "$SCRIPTS/integrate.sh"
  expect_eq "$(git rev-parse main)" "$before"
  expect_eq "$(git branch --show-current)" "docs/readme/describe-project"
  grep -q "an edit to keep" .workflow/journal.md || fail "the journal's edit lost"
}

test_sync_takes_in_a_moved_main_and_commit_records_the_merge() {
  open_task
  verified_commit "more"
  move_main
  head="$(git rev-parse HEAD)"
  out="$(bash "$SCRIPTS/sync.sh")"
  [[ "$out" == *"not committed"* ]] || fail "$out"
  expect_eq "$(git rev-parse HEAD)" "$head" "nothing committed"
  [[ -f other.txt ]] || fail "main not taken in"
  expect_eq "$(bash "$SCRIPTS/journal.sh" get base)" "$(git rev-parse --short main)" "the base is main's commit"
  bash "$SCRIPTS/verify.sh" >/dev/null
  bash "$SCRIPTS/commit.sh" "$(message "Merge branch 'main' into docs/readme/describe-project")" >/dev/null
  expect_eq "$(git rev-list --parents -n 1 HEAD | wc -w)" "3" "a merge commit"
  expect_eq "$(git diff --name-only "$(bash "$SCRIPTS/journal.sh" get base)" HEAD -- . ':(exclude).workflow')" "README.md" "the range from the base holds the branch's changes only"
  out="$(bash "$SCRIPTS/integrate.sh")"
  [[ "$out" == *"integrated"* ]] || fail "not integrated: $out"
  [[ -f other.txt ]] || fail "main's change lost"
}

test_sync_with_main_already_in_does_nothing() {
  open_task
  verified_commit "more"
  out="$(bash "$SCRIPTS/sync.sh")"
  [[ "$out" == *"nothing to take in"* ]] || fail "$out"
  [[ ! -f "$(git rev-parse --git-path MERGE_HEAD)" ]] || fail "a merge started"
}

test_sync_commits_a_merge_that_changes_nothing() {
  open_task
  echo "same" >other.txt
  verified_commit "more"
  move_main other.txt same
  bash "$SCRIPTS/sync.sh" >/dev/null
  bash "$SCRIPTS/verify.sh" >/dev/null
  bash "$SCRIPTS/commit.sh" "$(message "Merge branch 'main'")" >/dev/null
  git merge-base --is-ancestor main HEAD || fail "main not in the branch"
}

test_sync_conflict_waits_for_a_resolution_or_an_abort() {
  open_task
  verified_commit "branch line"
  base="$(bash "$SCRIPTS/journal.sh" get base)"
  git switch -q main
  echo "main line" >>README.md && git commit -qam "chore(repo): conflict"
  git switch -q docs/readme/describe-project
  head="$(git rev-parse HEAD)"
  out="$(bash "$SCRIPTS/sync.sh" 2>&1)" && fail "no conflict: $out"
  [[ "$out" == *"conflicts"*"README.md"*"sync.sh --abort"* ]] || fail "$out"
  [[ -f "$(git rev-parse --git-path MERGE_HEAD)" ]] || fail "the merge was not left to resolve"
  expect_fail "a merge is under way" bash "$SCRIPTS/sync.sh"
  bash "$SCRIPTS/sync.sh" --abort >/dev/null
  [[ ! -f "$(git rev-parse --git-path MERGE_HEAD)" ]] || fail "the merge is still there"
  expect_eq "$(git rev-parse HEAD)" "$head"
  expect_eq "$(bash "$SCRIPTS/journal.sh" get base)" "$base" "the base put back"
  expect_eq "$(git status --porcelain -- README.md)" "" "README.md as it was"
  expect_fail "no sync under way" bash "$SCRIPTS/sync.sh" --abort
}

test_sync_and_integrate_bring_main_up_to_its_upstream() {
  git init -q --bare "$WORK/remote.git"
  git remote add origin "$WORK/remote.git"
  git push -q -u origin main
  open_task
  verified_commit "more"
  git clone -q "$WORK/remote.git" "$WORK/other"
  (cd "$WORK/other" && echo "upstream" >upstream.txt && git add -A && git commit -qm "chore(repo): upstream" && git push -q)
  expect_fail "sync.sh" bash "$SCRIPTS/integrate.sh"
  expect_eq "$(git rev-parse main)" "$(git rev-parse origin/main)" "main fast-forwarded"
  bash "$SCRIPTS/sync.sh" >/dev/null
  [[ -f upstream.txt ]] || fail "the upstream's change not taken in"
}

guard() {
  printf '{"tool_input":{"command":%s}}' "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1")" |
    CLAUDE_PROJECT_DIR="$REPO" bash "$SCRIPTS/guard.sh"
}

test_guard_denies_commit_and_merge_only_inside_a_task() {
  expect_eq "$(guard 'git commit -m x')" "" "no journal: silent"
  open_task
  guard 'git commit -m x' | grep -q '"deny"' || fail "commit not denied"
  guard 'cd x && git merge --no-ff y' | grep -q '"deny"' || fail "merge not denied"
  expect_eq "$(guard 'git merge-base --is-ancestor a b')" "" "merge-base allowed"
  expect_eq "$(guard "bash $SCRIPTS/commit.sh msg")" "" "commit.sh allowed"
}

session_start() {
  printf '{"source":"%s"}' "$1" | CLAUDE_PROJECT_DIR="$REPO" bash "$SCRIPTS/session-start.sh"
}

test_session_start_speaks_only_inside_a_task() {
  expect_eq "$(session_start startup)" ""
  open_task
  [[ "$(session_start startup)" == *"continues only when the user types /overload:task"* ]] || fail "startup"
  [[ "$(session_start clear)" == *"phase s/implement"* ]] || fail "clear"
  [[ "$(session_start compact)" == *"reread .workflow/journal.md"* ]] || fail "compact"
  expect_eq "$(session_start resume)" "" "a resumed session holds the task"
}

test_session_start_names_the_command_a_build_waits_for() {
  open_build_task
  [[ "$(session_start startup)" == *"continues only when the user types /overload:build"* ]] || fail "$(session_start startup)"
}

test_status_reports_config_journal_and_verify() {
  out="$(OVERLOAD_RUN_TESTS="pytest {files}" bash "$SCRIPTS/status.sh")"
  [[ "$out" == *"journal: none"* ]] || fail "$out"
  [[ "$out" == *"run_tests = pytest {files}"*"run_tests comes from \$OVERLOAD_RUN_TESTS"* ]] || fail "the override not reported: $out"
  open_task
  echo "More." >>README.md
  bash "$SCRIPTS/verify.sh" >/dev/null
  out="$(bash "$SCRIPTS/status.sh")"
  [[ "$out" == *"tier: S"* && "$out" == *"working tree: verified"* ]] || fail "$out"
  rm .workflow/config
  [[ "$(bash "$SCRIPTS/status.sh")" == *"config: none"* ]] || fail "no config not reported"
}

test_status_lists_the_spec_s_chunks_with_their_first_step() {
  open_l_task
  mkdir -p .workflow/specs
  printf -- '---\nstatus: approved\n---\n\n## Chunks\n- [x] 1. A (test-first): a\n- [ ] 2. B (test-first): b; signatures: f(x)\n- [ ] 3. C (tests only): c\n' >.workflow/specs/s.md
  bash "$SCRIPTS/journal.sh" set spec .workflow/specs/s.md
  out="$(bash "$SCRIPTS/status.sh")"
  [[ "$out" == *"- spec: .workflow/specs/s.md, status approved"*"  - chunk 1: done"*"  - chunk 2: open, test-first, first step stub"*"  - chunk 3: open, tests-only, first step test"* ]] || fail "$out"
  printf -- '## Chunks\n- [ ] 1. A: a\n' >.workflow/specs/s.md
  out="$(bash "$SCRIPTS/status.sh")"
  [[ "$out" == *"chunk 1 has no type"* ]] || fail "$out"
}

empty_repo() {
  mkdir -p "$WORK/empty" && cd "$WORK/empty" && git init -q
  mkdir -p .workflow
  printf 'version = 1\ncheck =\nrun_tests =\n' >.workflow/config
}

test_status_reports_a_repository_without_commit_and_an_empty_check() {
  out="$(bash "$SCRIPTS/status.sh")"
  [[ "$out" != *"no commit yet"* && "$out" != *"unchecked"* ]] || fail "$out"
  empty_repo
  out="$(bash "$SCRIPTS/status.sh")"
  [[ "$out" == *"repository: no commit yet"* ]] || fail "$out"
  [[ "$out" == *"check is empty: every commit passes unchecked"* ]] || fail "$out"
}

test_verify_runs_before_the_first_commit() {
  empty_repo
  out="$(bash "$SCRIPTS/verify.sh")"
  [[ "$out" == *"nothing checked"* ]] || fail "$out"
  printf 'version = 1\ncheck = test -f .workflow/config\n' >.workflow/config
  out="$(bash "$SCRIPTS/verify.sh")"
  [[ "$out" == *"verify: green"* ]] || fail "$out"
}

test_branch_refuses_a_main_without_commit() {
  empty_repo
  expect_fail "no commit yet" bash "$SCRIPTS/branch.sh" S docs/readme "$(intent)"
}

test_branch_carries_the_first_config_of_init() {
  git rm -q --cached .workflow/config
  git commit -qm "chore(repo): no config yet"
  echo "# Backlog" >.workflow/backlog.md
  open_task
  expect_eq "$(git branch --show-current)" "docs/readme/describe-project"
  echo "More." >>README.md
  expect_fail "uncommitted changes" bash -c "git switch -q main && bash '$SCRIPTS/branch.sh' S docs/other/thing '$(intent)'"
}

test_every_skill_runs_only_when_the_user_types_it() {
  local skill
  local -a open=()
  for skill in "$SCRIPTS"/../skills/*/SKILL.md; do
    sed -n '2,/^---$/p' "$skill" | grep -qx 'disable-model-invocation: true' || open+=("$skill")
  done
  ((${#open[@]} == 0)) || fail "the model could load: ${open[*]}"
}

test_rules_prints_the_shared_rules_from_any_folder() {
  local out
  out="$(cd / && bash "$SCRIPTS/rules.sh")"
  expect_eq "$out" "$(cat "$SCRIPTS/../shared/rules.md")"
  [[ "$out" == "## Rules of every task"* ]] || fail "$out"
}

test_every_phase_a_skill_or_a_phase_names_exists() {
  local plugin="$SCRIPTS/.." file dir name
  local -a missing=()
  # `phases/<name>.md` is the running skill's folder, `shared/<name>.md` the
  # plugin's; a shared file runs under any skill, so its `phases/` names
  # must exist in one of them.
  for file in "$plugin"/skills/*/SKILL.md "$plugin"/skills/*/phases/*.md "$plugin"/shared/*.md; do
    dir="${file%/*}"
    [[ "$dir" == */phases ]] && dir="${dir%/phases}"
    while read -r name; do
      if [[ "$name" == shared/* ]]; then
        [[ -f "$plugin/$name" ]] || missing+=("${file#"$plugin"/}: $name")
      elif [[ "$dir" == */shared ]]; then
        compgen -G "$plugin/skills/*/$name" >/dev/null || missing+=("${file#"$plugin"/}: $name")
      else
        [[ -f "$dir/$name" ]] || missing+=("${file#"$plugin"/}: $name")
      fi
    done < <(grep -oE '(phases|shared)/[a-z-]+\.md' "$file" | sort -u)
  done
  ((${#missing[@]} == 0)) || fail "named, but no such file: ${missing[*]}"
}

test_the_phases_and_agents_name_only_the_config_s_keys() {
  source_lib
  local plugin="$SCRIPTS/.." readme="$SCRIPTS/../../../README.md" key explorer_keys
  local -a named=() unknown=() missing=()
  # The setup explorer's key list: the `- \`key\`` lines of its section.
  # shellcheck disable=SC2016 # backticks to match, not to expand
  explorer_keys="$(sed -n '/^## The keys/,/^## /p' "$plugin/agents/setup-explorer.md" | grep -oE '^- `[a-z_]+`' | sed 's/^- `//; s/`$//')"
  # "the config's `a`, `b` and `c`", the explorer's key list, and the
  # `key = value` lines of the README's
  # shellcheck disable=SC2016 # backticks to match, not to expand
  mapfile -t named < <({
    grep -ohE "config's (\`[a-z_]+\`(, | and |, and )?)+" "$plugin"/skills/*/SKILL.md \
      "$plugin"/skills/*/phases/*.md "$plugin"/shared/*.md "$plugin"/agents/*.md | grep -oE '`[a-z_]+`' | tr -d '`'
    printf '%s\n' "$explorer_keys"
    grep -ohE '^[a-z_]+ +=' "$readme" | tr -d ' ='
  } | sort -u)
  ((${#named[@]} >= 5)) || fail "too few keys found, the patterns are stale: ${named[*]}"
  for key in "${named[@]}"; do
    [[ " $CONFIG_KEYS " == *" $key "* ]] || unknown+=("$key")
  done
  ((${#unknown[@]} == 0)) || fail "named, but not keys of lib.sh: ${unknown[*]}"
  for key in $CONFIG_KEYS; do
    grep -qx "$key" <<<"$explorer_keys" || missing+=("setup-explorer.md: $key")
    grep -qE "^$key +=" "$readme" || missing+=("README.md: $key")
  done
  ((${#missing[@]} == 0)) || fail "keys missing from a key list: ${missing[*]}"
}

test_commit_moves_an_s_task_to_the_close_unless_it_holds_only_the_config() {
  open_task
  set_config check_integrate ''
  bash "$SCRIPTS/verify.sh" >/dev/null
  out="$(bash "$SCRIPTS/commit.sh" "$(message 'chore(repo): config')")"
  [[ "$out" == *"phase stays s/implement: the commit changes only the config"* ]] || fail "$out"
  out="$(verified_commit_out "More.")"
  [[ "$out" == *"phase: close/check"* ]] || fail "$out"
  expect_eq "$(bash "$SCRIPTS/journal.sh" get phase)" close/check
}

verified_commit_out() {
  echo "$1" >>README.md
  bash "$SCRIPTS/verify.sh" >/dev/null
  bash "$SCRIPTS/commit.sh" "$(message "docs(readme): $1")"
}

test_verify_integrate_moves_the_close_to_review_on_a_committed_tree() {
  slow_check
  open_task
  verified_commit "More."
  expect_eq "$(bash "$SCRIPTS/journal.sh" get phase)" close/check
  echo "Fix." >>README.md
  out="$(bash "$SCRIPTS/verify.sh" --integrate)"
  [[ "$out" == *"verify: green"* && "$out" != *"phase"* ]] || fail "an uncommitted tree moved: $out"
  out="$(bash "$SCRIPTS/commit.sh" "$(message 'docs(readme): fix')")"
  [[ "$out" == *"phase: close/review"* ]] || fail "$out"
  bash "$SCRIPTS/journal.sh" set phase close/check
  out="$(verified_commit_out "Plain.")"
  [[ "$out" == *"phase stays close/check: verify.sh --integrate did not check this tree"* ]] || fail "$out"
  touch slow-red
  if bash "$SCRIPTS/verify.sh" --integrate >/dev/null 2>&1; then fail "green"; fi
  expect_eq "$(bash "$SCRIPTS/journal.sh" get phase)" close/check "a red moved"
  rm slow-red
  out="$(bash "$SCRIPTS/verify.sh" --integrate)"
  [[ "$out" == *"phase: close/review"* ]] || fail "$out"
}

test_verify_integrate_leaves_a_merge_under_way_in_the_check() {
  open_task
  echo "same" >other.txt
  verified_commit "more"
  move_main other.txt same
  bash "$SCRIPTS/sync.sh" >/dev/null
  out="$(bash "$SCRIPTS/verify.sh" --integrate)"
  [[ "$out" == *"verify: green"* && "$out" != *"phase"* ]] || fail "a merge under way moved: $out"
  out="$(bash "$SCRIPTS/commit.sh" "$(message "Merge branch 'main'")")"
  [[ "$out" == *"phase: close/review"* ]] || fail "$out"
}

test_branch_opens_a_build_from_an_approved_spec_on_main() {
  approved_spec_on_main "- [x] 1. Greet (test-first): a.ts" "- [ ] 2. Wire (no test-first): b.ts"
  out="$(bash "$SCRIPTS/branch.sh" --build feature/greet/build .workflow/specs/s.md)"
  [[ "$out" == *"On 'feature/greet/build'"* ]] || fail "$out"
  expect_eq "$(git branch --show-current)" feature/greet/build
  expect_eq "$(bash "$SCRIPTS/journal.sh" get command)" build
  expect_eq "$(bash "$SCRIPTS/journal.sh" get tier)" L
  expect_eq "$(bash "$SCRIPTS/journal.sh" get spec)" .workflow/specs/s.md
  expect_eq "$(bash "$SCRIPTS/journal.sh" get phase)" l/chunk-2/implement
  expect_eq "$(bash "$SCRIPTS/journal.sh" get base)" "$(git rev-parse --short main)"
  expect_eq "$(bash "$SCRIPTS/journal.sh" get approved)" "$(git rev-parse --short main)"
  [[ "$out" != *"main moved"* && "$out" != *"expiry"* ]] || fail "$out"
  grep -q "^Build the approved spec .workflow/specs/s.md" .workflow/journal.md || fail "no intent: $(cat .workflow/journal.md)"
}

# spec_merged <depends_on>: an approved spec whose frontmatter names
# <depends_on> (none when empty), merged into main as its task leaves it.
spec_merged() {
  echo "a" >a.ts
  git add -A && git commit -qm "feat(greet): a"
  git switch -q -c docs/greet/spec
  mkdir -p .workflow/specs
  {
    printf -- '---\nstatus: approved\n'
    [[ -z "$1" ]] || printf 'depends_on: %s\n' "$1"
    printf -- '---\n\n# Greet\n\n## Chunks\n- [ ] 1. Greet (test-first): a.ts\n'
  } >.workflow/specs/s.md
  git add -A && git commit -qm "docs(greet): spec"
  git switch -q main
  git merge -q --no-ff -m "Merge branch 'docs/greet/spec'" docs/greet/spec
  git branch -q -D docs/greet/spec
}

# main_changes <file>...: a commit on main that changes each file.
main_changes() {
  local file
  for file in "$@"; do echo "changed" >>"$file"; done
  git add -A && git commit -qm "chore(repo): main moves"
}

build_spec() {
  bash "$SCRIPTS/branch.sh" --build feature/greet/build .workflow/specs/s.md
}

test_branch_goes_on_with_a_build_whose_files_main_left_alone() {
  spec_merged a.ts
  approval="$(git rev-parse --short HEAD)"
  main_changes other.txt
  out="$(build_spec)"
  expect_eq "$(bash "$SCRIPTS/journal.sh" get approved)" "$approval"
  expect_eq "$(bash "$SCRIPTS/journal.sh" get phase)" l/chunk-1/test
  [[ "$out" == *"main moved since the spec's approval: 1 commit (git log --first-parent --oneline $approval..$(git rev-parse --short main)), none on its files"* ]] || fail "$out"
  [[ "$out" != *"expiry"* ]] || fail "$out"
  grep -q "main moved since the spec's approval" .workflow/journal.md || fail "not logged: $(cat .workflow/journal.md)"
}

test_branch_sends_a_build_whose_files_main_changed_to_its_expiry() {
  spec_merged a.ts
  approval="$(git rev-parse --short HEAD)"
  set_config check_integrate 'bash slow.sh'
  main_changes a.ts CLAUDE.md other.txt
  head="$(git rev-parse --short HEAD)"
  out="$(build_spec)"
  expect_eq "$(bash "$SCRIPTS/journal.sh" get phase)" l/expiry
  [[ "$out" == *"main changed the spec's files since its approval: .workflow/config, CLAUDE.md, a.ts"* ]] || fail "$out"
  [[ "$out" == *"git diff $approval $head -- a.ts CLAUDE.md .workflow/config"* ]] || fail "$out"
  [[ "$out" != *"other.txt"* ]] || fail "$out"
  grep -q "expiry: main changed the spec's files" .workflow/journal.md || fail "not logged: $(cat .workflow/journal.md)"
}

test_branch_checks_the_rules_and_the_config_of_a_spec_without_depends_on() {
  spec_merged ""
  main_changes a.ts
  out="$(build_spec)"
  expect_eq "$(bash "$SCRIPTS/journal.sh" get phase)" l/chunk-1/test
  [[ "$out" == *"the spec names no depends_on: only the rules and the config were checked"* ]] || fail "$out"
  rm .workflow/journal.md
  git switch -q main
  git branch -q -D feature/greet/build
  main_changes CLAUDE.md
  out="$(build_spec)"
  expect_eq "$(bash "$SCRIPTS/journal.sh" get phase)" l/expiry
}

test_branch_refuses_a_build_of_a_spec_not_ready() {
  expect_fail "Usage" bash "$SCRIPTS/branch.sh" --build feature/greet/build
  expect_fail "not a file on main" bash "$SCRIPTS/branch.sh" --build feature/greet/build .workflow/specs/s.md
  approved_spec_on_main "- [x] 1. Greet (test-first): a.ts"
  expect_fail "no chunk left to build" bash "$SCRIPTS/branch.sh" --build feature/greet/build .workflow/specs/s.md
  sed -i.bak 's/^- \[x\] 1/- [ ] 1/; s/^status: approved/status: draft/' .workflow/specs/s.md && rm .workflow/specs/s.md.bak
  git commit -qam "docs(greet): draft again"
  expect_fail "is not 'status: approved'" bash "$SCRIPTS/branch.sh" --build feature/greet/build .workflow/specs/s.md
  sed -i.bak 's/^status: draft/status: approved/; s/ (test-first)//' .workflow/specs/s.md && rm .workflow/specs/s.md.bak
  git commit -qam "docs(greet): no type"
  expect_fail "chunk 1 has no type" bash "$SCRIPTS/branch.sh" --build feature/greet/build .workflow/specs/s.md
  expect_eq "$(git branch --show-current)" main
}

# A spec task of docs only: the spec, its inputs, a decision record it adds
# to a folder of `rules`, the backlog.
docs_spec_task() {
  slow_check
  mkdir -p docs/adr
  echo "# 0000 template" >docs/adr/0000-template.md
  set_config rules 'CLAUDE.md, docs/adr/'
  git add -A && git commit -qm "chore(repo): decision records"
  open_l_task
  write_spec draft "- [ ] 1. Greet (test-first): a.ts"
  echo "# 0001 greet" >docs/adr/0001-greet.md
  echo "- an item" >>.workflow/backlog.md
  bash "$SCRIPTS/journal.sh" set phase l/checkpoint
  sed -i.bak 's/^status: draft/status: approved/' .workflow/specs/s.md && rm .workflow/specs/s.md.bak
  bash "$SCRIPTS/verify.sh" >/dev/null
}

test_commit_closes_a_spec_task_once_its_spec_is_approved() {
  docs_spec_task
  out="$(bash "$SCRIPTS/commit.sh" "$(message 'docs(greet): spec')")"
  [[ "$out" == *"phase: close/check"* ]] || fail "$out"
}

test_verify_integrate_closes_a_spec_task_of_docs_only_without_check_integrate() {
  docs_spec_task
  bash "$SCRIPTS/commit.sh" "$(message 'docs(greet): spec')" >/dev/null
  # ignored, so that it is no change of the task
  echo slow-red >>.git/info/exclude
  touch slow-red
  out="$(bash "$SCRIPTS/verify.sh" --integrate)"
  [[ "$out" == *"verify: green"*"docs only"*"phase: close/write"* && "$out" != *"slow tests"* ]] || fail "$out"
  bash "$SCRIPTS/journal.sh" set phase close/integrate
  out="$(bash "$SCRIPTS/integrate.sh")"
  [[ "$out" == *"integrated"* ]] || fail "$out"
}

test_a_spec_task_that_changes_more_than_docs_has_the_whole_close() {
  docs_spec_task
  echo "# more rules" >>CLAUDE.md
  bash "$SCRIPTS/verify.sh" >/dev/null
  bash "$SCRIPTS/commit.sh" "$(message 'docs(greet): spec')" >/dev/null
  out="$(bash "$SCRIPTS/verify.sh" --integrate)"
  [[ "$out" == *"slow tests"* || "$out" == *"check_integrate"* ]] || fail "check_integrate skipped: $out"
  [[ "$out" == *"phase: close/review"* && "$out" != *"docs only"* ]] || fail "$out"
  # an S task changes the backlog alone, and keeps its whole close
  bash "$SCRIPTS/journal.sh" set phase close/check
  git switch -q main
  git branch -q -D feature/greet/default-name
  open_task
  echo "- other" >>.workflow/backlog.md
  bash "$SCRIPTS/verify.sh" >/dev/null
  bash "$SCRIPTS/commit.sh" "$(message 'docs(backlog): more')" >/dev/null
  out="$(bash "$SCRIPTS/verify.sh" --integrate)"
  [[ "$out" == *"phase: close/review"* ]] || fail "$out"
}

test_a_decision_record_changed_rather_than_added_is_no_doc_of_the_spec() {
  docs_spec_task
  echo "superseded" >>docs/adr/0000-template.md
  bash "$SCRIPTS/verify.sh" >/dev/null
  bash "$SCRIPTS/commit.sh" "$(message 'docs(greet): spec')" >/dev/null
  out="$(bash "$SCRIPTS/verify.sh" --integrate)"
  [[ "$out" == *"phase: close/review"* ]] || fail "$out"
}

test_commit_of_a_sync_moves_a_spec_task_of_docs_only_to_the_write() {
  docs_spec_task
  bash "$SCRIPTS/commit.sh" "$(message 'docs(greet): spec')" >/dev/null
  git switch -q main
  echo other >other.txt
  git add -A && git commit -qm "chore(repo): move main"
  git switch -q feature/greet/default-name
  bash "$SCRIPTS/sync.sh" >/dev/null
  bash "$SCRIPTS/verify.sh" --integrate >/dev/null
  expect_eq "$(bash "$SCRIPTS/journal.sh" get phase)" close/check "a merge under way moved"
  out="$(bash "$SCRIPTS/commit.sh" "$(message "Merge branch 'main'")")"
  [[ "$out" == *"phase: close/write"* ]] || fail "$out"
}

test_every_skill_allows_the_scripts_its_phases_run() {
  local plugin="$SCRIPTS/.." skill dir name allowed
  local -a missing=()
  for skill in "$plugin"/skills/*/SKILL.md; do
    dir="${skill%/SKILL.md}"
    allowed="$(sed -n '2,/^---$/p' "$skill" | grep '^allowed-tools:' || true)"
    # integrate.sh asks the human each time, on purpose
    while read -r name; do
      [[ "$name" == integrate.sh || "$allowed" == *"scripts/$name"* ]] || missing+=("${dir##*/}: $name")
    done < <(cat "$skill" "$dir"/phases/*.md 2>/dev/null | grep -oE '(<scripts>|scripts)/[a-z-]+\.sh' | sed 's|.*/||' | sort -u)
  done
  ((${#missing[@]} == 0)) || fail "run, but not allowed: ${missing[*]}"
}

# An S task with a commit, uncommitted work, an input, the explorer's map,
# an open finding and a lesson candidate, on a main that moved since.
s_attempt() {
  printf 'the brief\n' >"$WORK/brief.md"
  bash "$SCRIPTS/branch.sh" S docs/readme/describe-project "$(intent)" --inputs readme "$WORK/brief.md" >/dev/null
  printf 'the map\n' >"$WORK/map.md"
  bash "$SCRIPTS/journal.sh" keep map "$WORK/map.md" >/dev/null
  verified_commit "Attempt."
  move_main
  echo "More attempt." >>README.md
  echo "draft" >draft.txt
  awk '{ print } /^## Open findings$/ { print ""; print "- a finding on the attempt" }
    /^## Lesson candidates$/ { print ""; print "- a lesson candidate" }' .workflow/journal.md >"$WORK/journal" &&
    mv "$WORK/journal" .workflow/journal.md
}

test_restart_reopens_an_s_task_as_l_from_an_up_to_date_main() {
  s_attempt
  tip="$(git rev-parse HEAD)"
  out="$(bash "$SCRIPTS/restart.sh" "the default name is public behavior")"
  expect_eq "$(git branch --show-current)" docs/readme/describe-project
  expect_eq "$(git rev-parse HEAD)" "$(git rev-parse main)"
  if git merge-base --is-ancestor "$tip" HEAD; then fail "the attempt is still on the branch"; fi
  expect_eq "$(git status --porcelain | sort | tr '\n' ' ')" "?? .workflow/inputs/ ?? .workflow/journal.md "
  expect_eq "$(cat .workflow/inputs/readme/brief.md)" "the brief"
  [[ ! -e draft.txt ]] || fail "the attempt's new file stayed"
  expect_eq "$(bash "$SCRIPTS/journal.sh" get tier)" L
  expect_eq "$(bash "$SCRIPTS/journal.sh" get phase)" l/spec
  expect_eq "$(bash "$SCRIPTS/journal.sh" get command)" task
  expect_eq "$(bash "$SCRIPTS/journal.sh" get base)" "$(git rev-parse --short main)"
  expect_eq "$(bash "$SCRIPTS/journal.sh" get verify_red_streak)" 0
  journal="$(cat .workflow/journal.md)"
  [[ "$journal" != *"a finding on the attempt"* ]] || fail "open findings kept: $journal"
  [[ "$journal" == *"- a lesson candidate"*"## Backlog candidates"* ]] || fail "lesson candidates lost: $journal"
  [[ "$journal" == *"tier L: the default name is public behavior"* ]] || fail "reason not logged: $journal"
  [[ "$journal" == *"## Inputs"*"- .workflow/inputs/readme/brief.md"* ]] || fail "inputs lost: $journal"
  [[ "$journal" != *"${tip:0:7}"* ]] || fail "the attempt's tip in the journal: $journal"
  [[ -f "$(sed -n 's/^- .* map: //p' .workflow/journal.md)" ]] || fail "the map is gone"
  [[ ! -e .git/overload/verified ]] || fail "the attempt's verified tree is kept"
  [[ "$out" == *"1 commit"*"${tip:0:7}"*"git reflog docs/readme/describe-project"* ]] || fail "$out"
  [[ "$out" == *"stash@{0}"* ]] || fail "$out"
  git stash show --include-untracked --name-only 'stash@{0}' | grep -qx draft.txt || fail "the uncommitted work is not in the stash"
  [[ "$(bash "$SCRIPTS/status.sh")" == *"tier: L"* ]] || fail "status"
}

test_restart_takes_only_an_s_task() {
  expect_fail "task's branch" bash "$SCRIPTS/restart.sh" "why"
  open_l_task
  expect_fail "tier L already" bash "$SCRIPTS/restart.sh" "why"
  git switch -q main
  rm .workflow/journal.md
  open_task
  expect_fail "Usage" bash "$SCRIPTS/restart.sh"
}

test_restart_aborts_a_sync_under_way() {
  open_task
  echo "mine" >other.txt
  verified_commit "more"
  move_main other.txt theirs
  bash "$SCRIPTS/sync.sh" >/dev/null 2>&1 || true
  [[ -f .git/MERGE_HEAD ]] || fail "no merge under way"
  out="$(bash "$SCRIPTS/restart.sh" "why")"
  [[ ! -f .git/MERGE_HEAD ]] || fail "the merge is still under way"
  expect_eq "$(git rev-parse HEAD)" "$(git rev-parse main)"
  [[ "$out" == *"aborted"* ]] || fail "$out"
}

test_restart_keeps_the_first_config_that_main_lacks() {
  git rm -q --cached .workflow/config
  git commit -qm "chore(repo): no config yet"
  open_task
  verified_commit "Attempt."
  bash "$SCRIPTS/restart.sh" "why" >/dev/null || fail "refused"
  expect_eq "$(git rev-parse HEAD)" "$(git rev-parse main)"
  [[ -f .workflow/config ]] || fail "the config is gone"
  [[ "$(bash "$SCRIPTS/status.sh")" == *"check = bash check.sh"* ]] || fail "$(bash "$SCRIPTS/status.sh")"
}

test_status_lists_on_main_the_specs_approved_and_not_built() {
  out="$(bash "$SCRIPTS/status.sh")"
  [[ "$out" == *"- specs to build: none"* ]] || fail "$out"
  mkdir -p .workflow/specs
  printf -- '---\nstatus: approved\n---\n\n## Chunks\n- [x] 1. A (test-first): a\n- [ ] 2. B (test-first): b\n' >.workflow/specs/a.md
  printf -- '---\nstatus: approved\n---\n\n## Chunks\n- [x] 1. A (test-first): a\n' >.workflow/specs/b.md
  printf -- '---\nstatus: dropped\n---\n\n## Chunks\n- [ ] 1. A (test-first): a\n' >.workflow/specs/c.md
  printf -- '---\nstatus: done\n---\n\n## Chunks\n- [x] 1. A (test-first): a\n' >.workflow/specs/d.md
  git add -A && git commit -qm "docs(repo): specs"
  out="$(bash "$SCRIPTS/status.sh")"
  [[ "$out" == *"- specs to build:"$'\n'"  - .workflow/specs/a.md: 1 of 2 chunks open"* ]] || fail "$out"
  [[ "$out" != *"b.md"* && "$out" != *"c.md"* && "$out" != *"d.md"* ]] || fail "$out"
  open_task
  [[ "$(bash "$SCRIPTS/status.sh")" != *"specs to build"* ]] || fail "listed on a task's branch"
}
