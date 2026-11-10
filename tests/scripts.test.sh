# shellcheck shell=bash
# The S path's scripts: config, branch, journal, verify, commit, integrate,
# and the hooks. Run by tests/run.sh, each test in a fresh repository.

source_lib() {
  # shellcheck source=../plugins/workflow-overload/scripts/lib.sh
  source "$SCRIPTS/lib.sh"
}

test_config_reads_values_comments_and_defaults() {
  source_lib
  expect_eq "$(cfg verify)" "bash check.sh"
  expect_eq "$(cfg exec)" ""
  expect_eq "$(cfg integrate)" "merge" "default"
  expect_eq "$(cfg commit)" "<type>(<scope>): <summary>" "default"
}

test_config_env_overrides_even_when_empty() {
  source_lib
  echo 'exec = ./dev.sh exec' >>.workflow/config
  expect_eq "$(cfg exec)" "./dev.sh exec"
  expect_eq "$(OVERLOAD_EXEC='' cfg exec)" ""
  expect_eq "$(OVERLOAD_VERIFY='make check' cfg verify)" "make check"
}

test_config_refuses_another_version() {
  set_config version 2
  expect_fail "reads version 1" bash "$SCRIPTS/verify.sh"
}

test_branch_opens_task_with_journal() {
  open_task
  expect_eq "$(git branch --show-current)" "docs/readme/describe-project"
  expect_eq "$(bash "$SCRIPTS/journal.sh" get tier)" "S"
  expect_eq "$(bash "$SCRIPTS/journal.sh" get phase)" "s/implement"
  grep -q "Goal: say what the project does." .workflow/journal.md || fail "intent missing from the journal"
}

test_branch_refuses_bad_names_and_states() {
  expect_fail "not among the config's types" bash "$SCRIPTS/branch.sh" S feat readme x "$(intent)"
  expect_fail "not kebab-case" bash "$SCRIPTS/branch.sh" S docs Readme x "$(intent)"
  expect_fail "tier is S or L" bash "$SCRIPTS/branch.sh" M docs readme x "$(intent)"
  echo change >>README.md
  expect_fail "uncommitted changes" bash "$SCRIPTS/branch.sh" S docs readme x "$(intent)"
  git checkout -q README.md
  git switch -q -c other
  expect_fail "a task starts from main" bash "$SCRIPTS/branch.sh" S docs readme x "$(intent)"
}

test_branch_refuses_a_name_too_long_for_the_merge_subject() {
  expect_fail "merge subject would be over 72" bash "$SCRIPTS/branch.sh" S docs readme \
    "a-very-long-description-that-goes-on-and-on-and-on-forever" "$(intent)"
}

test_journal_set_inc_log() {
  open_task
  bash "$SCRIPTS/journal.sh" set phase s/review
  expect_eq "$(bash "$SCRIPTS/journal.sh" get phase)" "s/review"
  expect_eq "$(bash "$SCRIPTS/journal.sh" inc review_rounds)" "1"
  bash "$SCRIPTS/journal.sh" set lessons 2
  expect_eq "$(bash "$SCRIPTS/journal.sh" get lessons)" "2"
  bash "$SCRIPTS/journal.sh" log "review found nothing"
  tail -n 1 .workflow/journal.md | grep -q "review found nothing" || fail "log line missing"
  # a new key lands in the header, before the first section
  expect_eq "$(sed -n '/^## /q; /^lessons:/p' .workflow/journal.md)" "lessons: 2"
}

test_branch_keeps_the_intent_inside_its_section() {
  printf '## Problem\nThe README is short.\n# Goal\nSay more.\n' >"$WORK/headed.md"
  bash "$SCRIPTS/branch.sh" S docs readme describe-project "$WORK/headed.md" >/dev/null
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
  grep -c $'\tred\t' "$(git rev-parse --git-path overload)/runs.log" | grep -qx 1 || fail "red run not logged"
}

test_verify_without_a_command_records_the_tree_unchecked() {
  set_config verify ''
  git add -A && git commit -qm "chore(repo): no verify"
  open_task
  echo "More." >>README.md
  out="$(bash "$SCRIPTS/verify.sh")"
  [[ "$out" == *"no 'verify' command"*"nothing checked"* ]] || fail "$out"
  source_lib
  is_verified || fail "tree not recorded"
  grep -q $'\tnone\t' "$(git rev-parse --git-path overload)/runs.log" || fail "run not logged as none"
  bash "$SCRIPTS/commit.sh" "$(message 'docs(readme): say more')" >/dev/null
}

test_verify_red_is_red_through_a_pipe_in_the_command() {
  set_config verify 'bash check.sh | cat' 
  git commit -qam "chore(repo): pipe"
  open_task
  touch red
  expect_fail "verify: red" bash "$SCRIPTS/verify.sh"
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

test_commit_needs_a_verified_tree_and_the_format() {
  open_task
  echo "More." >>README.md
  expect_fail "not the one the last green verify checked" bash "$SCRIPTS/commit.sh" "$(message 'docs(readme): say what it does')"
  bash "$SCRIPTS/verify.sh" >/dev/null
  expect_fail "does not follow the config's format" bash "$SCRIPTS/commit.sh" "$(message 'Update README')"
  expect_fail "does not follow the config's format" bash "$SCRIPTS/commit.sh" "$(message 'feature(readme): say what it does')"
  bash "$SCRIPTS/commit.sh" "$(message 'docs(readme): say what it does')" | grep -q "committed" || fail "no commit"
  git show --name-only --format= HEAD | grep -qx .workflow/journal.md || fail "journal not committed"
  echo "Again." >>README.md
  expect_fail "not the one the last green verify checked" bash "$SCRIPTS/commit.sh" "$(message 'docs(readme): again')"
}

test_commit_follows_a_bracketed_format() {
  set_config commit '[<scope>] <type>: <summary>' 
  git commit -qam "chore(repo): bracket format"
  open_task
  echo "More." >>README.md
  bash "$SCRIPTS/verify.sh" >/dev/null
  expect_fail "does not follow" bash "$SCRIPTS/commit.sh" "$(message 'docs(readme): x')"
  bash "$SCRIPTS/commit.sh" "$(message '[@scope/pkg] docs: say what it does')" >/dev/null
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

test_integrate_merges_without_journal_and_with_measures() {
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
  python3 - <<'PY' || fail "bad measures"
import json
rows = [json.loads(l) for l in open(".workflow/metrics.jsonl")]
assert len(rows) == 1, rows
r = rows[0]
assert r["branch"] == "docs/readme/describe-project", r
assert r["journal"]["tier"] == "S", r
assert r["verify"]["runs"] == 1 and r["verify"]["red"] == 0 and r["verify"]["red_checks"] == 0, r
assert r["commits"] == 1 and r["files"] == 2, r
PY
  [[ -z "$(git status --porcelain)" ]] || fail "dirty after integrate"
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
  bash "$SCRIPTS/branch.sh" S docs readme describe-the-project-in-detail "$(intent)" >/dev/null
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

test_integrate_refuses_an_unverified_head() {
  open_task
  verified_commit "more"
  echo "x" >>README.md
  expect_fail "uncommitted changes" bash "$SCRIPTS/integrate.sh"
  git checkout -q README.md
  rm -f "$(git rev-parse --git-path overload)/verified"
  expect_fail "not the tree the last green verify checked" bash "$SCRIPTS/integrate.sh"
}

test_integrate_reverifies_when_main_moved() {
  open_task
  verified_commit "more"
  git switch -q main
  echo "other" >other.txt
  git add other.txt && git commit -qm "chore(repo): other"
  git switch -q docs/readme/describe-project
  # Captured, not piped to grep -q, whose early exit would cut the script.
  out="$(bash "$SCRIPTS/integrate.sh")"
  [[ "$out" == *"verifying the merge's result"* ]] || fail "no re-verify: $out"
  [[ -f other.txt && -f .workflow/metrics.jsonl ]] || fail "merge incomplete"
}

test_integrate_red_on_merge_result_leaves_main_intact() {
  open_task
  verified_commit "more"
  git switch -q main
  touch red && git add red && git commit -qm "chore(repo): break main"
  before="$(git rev-parse main)"
  git switch -q docs/readme/describe-project
  expect_fail "verify is red on the merge's result" bash "$SCRIPTS/integrate.sh"
  expect_eq "$(git rev-parse main)" "$before"
  expect_eq "$(git branch --show-current)" "docs/readme/describe-project"
  [[ -f .workflow/journal.md ]] || fail "journal lost"
}

test_integrate_conflict_leaves_main_intact() {
  open_task
  verified_commit "branch line"
  git switch -q main
  echo "main line" >>README.md && git commit -qam "chore(repo): conflict"
  before="$(git rev-parse main)"
  git switch -q docs/readme/describe-project
  expect_fail "conflicts" bash "$SCRIPTS/integrate.sh"
  expect_eq "$(git rev-parse main)" "$before"
  expect_eq "$(git branch --show-current)" "docs/readme/describe-project"
  [[ -z "$(git status --porcelain -- README.md)" ]] || fail "merge left behind"
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
  [[ "$(session_start startup)" == *"continues only when the user types /overload"* ]] || fail "startup"
  [[ "$(session_start clear)" == *"phase s/implement"* ]] || fail "clear"
  [[ "$(session_start compact)" == *"reread .workflow/journal.md"* ]] || fail "compact"
  expect_eq "$(session_start resume)" "" "a resumed session holds the task"
}

test_status_reports_config_journal_and_verify() {
  out="$(bash "$SCRIPTS/status.sh")"
  [[ "$out" == *"journal: none"* ]] || fail "$out"
  open_task
  echo "More." >>README.md
  bash "$SCRIPTS/verify.sh" >/dev/null
  out="$(bash "$SCRIPTS/status.sh")"
  [[ "$out" == *"tier: S"* && "$out" == *"working tree: verified"* ]] || fail "$out"
  rm .workflow/config
  [[ "$(bash "$SCRIPTS/status.sh")" == *"config: none"* ]] || fail "no config not reported"
}

test_branch_carries_the_first_config_of_init() {
  git rm -q --cached .workflow/config
  git commit -qm "chore(repo): no config yet"
  echo "# Backlog" >.workflow/backlog.md
  open_task
  expect_eq "$(git branch --show-current)" "docs/readme/describe-project"
  echo "More." >>README.md
  expect_fail "uncommitted changes" bash -c "git switch -q main && bash '$SCRIPTS/branch.sh' S docs other thing '$(intent)'"
}
