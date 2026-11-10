# shellcheck shell=bash
# The L path's suite records and red check. Run by tests/run.sh.

write_test() {
  mkdir -p __tests__
  printf '%s\n' "${@:2}" >"__tests__/$1"
}

test_suite_records_only_test_files_and_keeps_the_branch() {
  open_l_task
  head="$(git rev-parse HEAD)"
  write_test greet.test.ts "case a assert"
  echo "stub" >greet.ts
  bash "$SCRIPTS/suite.sh" record | grep -q "__tests__/greet.test.ts" || fail "not recorded"
  expect_eq "$(git rev-parse HEAD)" "$head" "the branch did not move"
  expect_eq "$(bash "$SCRIPTS/suite.sh" files)" "__tests__/greet.test.ts"
  git show-ref | grep -q "refs/overload/suite/feature/greet/default-name/1" || fail "no ref"
  [[ -n "$(git status --porcelain -- __tests__)" ]] || fail "the working tree changed"
}

test_suite_record_refuses_nothing_and_a_reference_model() {
  open_l_task
  expect_fail "nothing to record" bash "$SCRIPTS/suite.sh" record
  write_test a.test.ts "case a assert"
  mkdir -p .workflow/reference && echo x >.workflow/reference/model.ts
  expect_fail "reference model" bash "$SCRIPTS/suite.sh" record
}

test_commit_refuses_a_changed_recorded_test() {
  open_l_task
  write_test greet.test.ts "case a assert"
  bash "$SCRIPTS/suite.sh" record >/dev/null
  write_test greet.test.ts "case a pass"
  bash "$SCRIPTS/verify.sh" >/dev/null
  expect_fail "differ from the suite the test-author handed over" bash "$SCRIPTS/commit.sh" "$(message 'feat(greet): x')"
  write_test greet.test.ts "case a assert"
  bash "$SCRIPTS/verify.sh" >/dev/null
  bash "$SCRIPTS/commit.sh" "$(message 'feat(greet): x')" >/dev/null
}

test_commit_refuses_an_unrecorded_test_file_during_a_test_first_chunk() {
  write_test old.test.ts "case old pass"
  git add -A && git commit -qm "test(greet): an existing test"
  open_l_task
  write_test a.test.ts "case a assert"
  bash "$SCRIPTS/suite.sh" record >/dev/null
  write_test extra.test.ts "case mine pass"
  bash "$SCRIPTS/verify.sh" >/dev/null
  expect_fail "not in the suite the test-author recorded" bash "$SCRIPTS/commit.sh" "$(message 'feat(greet): x')"
  rm __tests__/extra.test.ts
  write_test old.test.ts "case old skip"
  bash "$SCRIPTS/verify.sh" >/dev/null
  expect_fail "__tests__/old.test.ts" bash "$SCRIPTS/commit.sh" "$(message 'feat(greet): x')"
  git checkout -q -- __tests__/old.test.ts
  bash "$SCRIPTS/verify.sh" >/dev/null
  bash "$SCRIPTS/commit.sh" "$(message 'feat(greet): x')" >/dev/null
  # the next chunk is not test-first: no record on this HEAD, tests are free
  write_test wiring.test.ts "case w pass"
  bash "$SCRIPTS/verify.sh" >/dev/null
  bash "$SCRIPTS/commit.sh" "$(message 'feat(greet): wire it')" >/dev/null
}

test_a_new_record_supersedes_the_old_one() {
  open_l_task
  write_test greet.test.ts "case a assert"
  bash "$SCRIPTS/suite.sh" record >/dev/null
  write_test greet.test.ts "case a notimpl"
  bash "$SCRIPTS/suite.sh" record >/dev/null
  bash "$SCRIPTS/suite.sh" check
  bash "$SCRIPTS/suite.sh" diff | grep -q "as recorded (2)" || fail "not the second record"
}

test_a_new_record_covers_a_file_put_back_to_head() {
  write_test old.test.ts "case old pass"
  git add -A && git commit -qm "test(greet): an existing test"
  open_l_task
  write_test old.test.ts "case old assert"
  write_test a.test.ts "case a assert"
  bash "$SCRIPTS/suite.sh" record >/dev/null
  # the test-author puts old.test.ts back as HEAD has it, and records again
  git checkout -q -- __tests__/old.test.ts
  bash "$SCRIPTS/suite.sh" record >/dev/null
  bash "$SCRIPTS/suite.sh" check
  bash "$SCRIPTS/suite.sh" diff | grep -q "old.test.ts: as recorded (2)" || fail "not covered by the second record"
  # and a change to it after that is still refused
  write_test old.test.ts "case old skip"
  expect_fail "__tests__/old.test.ts" bash "$SCRIPTS/suite.sh" check
}

test_red_check_accepts_assertions_and_not_implemented() {
  fake_runner
  open_l_task
  write_test a.test.ts "case one assert" "case two notimpl"
  bash "$SCRIPTS/suite.sh" record >/dev/null
  out="$(bash "$SCRIPTS/red-check.sh")"
  [[ "$out" == *"valid red, every new test fails"* ]] || fail "$out"
}

test_red_check_refuses_load_errors_passes_skips_and_type_errors() {
  fake_runner
  open_l_task
  write_test a.test.ts "load"
  write_test b.test.ts "case green pass" "case red assert"
  write_test c.test.ts "case s skip"
  write_test d.test.ts "case t typeerror"
  bash "$SCRIPTS/suite.sh" record >/dev/null
  set +e
  out="$(bash "$SCRIPTS/red-check.sh" 2>&1)"
  status=$?
  set -e
  expect_eq "$status" 1
  [[ "$out" == *"a.test.ts"*"LOAD ERROR"* ]] || fail "load: $out"
  [[ "$out" == *"b.test.ts > green: passes already"* ]] || fail "pass: $out"
  [[ "$out" == *"c.test.ts > s: skipped"* ]] || fail "skip: $out"
  [[ "$out" == *"d.test.ts > t: red for the wrong reason, TypeError"* ]] || fail "type: $out"
  [[ "$out" == *"b.test.ts > red: red, AssertionError"* ]] || fail "red ok: $out"
}

test_red_check_judges_only_the_tests_new_to_a_file() {
  fake_runner
  write_test a.test.ts "case old pass"
  git add -A && git commit -qm "test(greet): an existing test"
  open_l_task
  write_test a.test.ts "case old pass" "case new assert"
  bash "$SCRIPTS/suite.sh" record >/dev/null
  out="$(bash "$SCRIPTS/red-check.sh")"
  [[ "$out" == *"a.test.ts > old: passes, already in HEAD"* && "$out" == *"valid red"* ]] || fail "$out"
  expect_eq "$(git show HEAD:__tests__/a.test.ts)" "case old pass" "HEAD untouched"
  expect_eq "$(cat __tests__/a.test.ts)" $'case old pass\ncase new assert' "the working file restored"

  write_test a.test.ts "case old typeerror" "case new pass"
  bash "$SCRIPTS/suite.sh" record >/dev/null
  set +e
  out="$(bash "$SCRIPTS/red-check.sh" 2>&1)"
  status=$?
  set -e
  expect_eq "$status" 1
  [[ "$out" == *"a.test.ts > new: passes already"* ]] || fail "new pass: $out"
  [[ "$out" == *"a.test.ts > old: red for the wrong reason, TypeError"* ]] || fail "old type: $out"
}

test_red_check_hands_new_green_tests_to_the_step_reviewer() {
  fake_runner
  open_l_task
  write_test a.test.ts "case red assert" "case green pass"
  bash "$SCRIPTS/suite.sh" record >/dev/null
  out="$(bash "$SCRIPTS/red-check.sh")"
  [[ "$out" == *"valid red"*"1 new test passes already"*"mutation check"* ]] || fail "$out"
  expect_eq "$(cat "$(git rev-parse --git-path overload)/red-check-green.txt")" "__tests__/a.test.ts > green"
}

test_red_check_leaves_out_the_test_files_the_suite_deletes() {
  fake_runner
  write_test gone.test.ts "case old pass"
  git add -A && git commit -qm "test(greet): a test to retire"
  open_l_task
  git rm -q __tests__/gone.test.ts
  write_test a.test.ts "case new assert"
  bash "$SCRIPTS/suite.sh" record >/dev/null
  out="$(bash "$SCRIPTS/red-check.sh")"
  [[ "$out" == *"valid red"* ]] || fail "$out"
  [[ "$out" != *"gone.test.ts"*"not in the runner"* ]] || fail "deleted file judged: $out"
}

test_red_check_without_code_runs_the_suite_against_the_stubs() {
  fake_runner
  set_config test_files 'cat greet.ts; python3 runner.py {files}'
  git add -A && git commit -qm "chore(repo): runner shows the source"
  open_l_task
  write_test a.test.ts "case a assert"
  echo "stub" >greet.ts
  bash "$SCRIPTS/suite.sh" record >/dev/null
  bash "$SCRIPTS/red-check.sh" >/dev/null
  # the implementer has written the code, a test is fixed and recorded again
  echo "real code" >greet.ts
  echo "more code" >other.ts
  write_test a.test.ts "case a notimpl"
  bash "$SCRIPTS/suite.sh" record >/dev/null
  out="$(bash "$SCRIPTS/red-check.sh" --without-code)"
  [[ "$out" == *"valid red"* ]] || fail "not valid: $out"
  grep -qx "stub" "$(git rev-parse --git-path overload)/red-check-output.txt" || fail "the run did not see the stubs"
  ! grep -qx "real code" "$(git rev-parse --git-path overload)/red-check-output.txt" || fail "the run saw the code"
  expect_eq "$(cat greet.ts)" "real code" "the code is back"
  expect_eq "$(cat other.ts)" "more code" "the new file is back"
}

test_red_check_without_code_and_no_valid_red_before_runs_against_head() {
  fake_runner
  set_config test_files 'ls; python3 runner.py {files}'
  git add -A && git commit -qm "chore(repo): runner lists the tree"
  open_l_task
  write_test a.test.ts "case a assert"
  echo "code" >greet.ts
  bash "$SCRIPTS/suite.sh" record >/dev/null
  bash "$SCRIPTS/red-check.sh" --without-code >/dev/null
  ! grep -qx "greet.ts" "$(git rev-parse --git-path overload)/red-check-output.txt" || fail "the code was in place"
  expect_eq "$(cat greet.ts)" "code" "the code is back"
}

test_red_check_refuses_a_suite_where_nothing_fails() {
  fake_runner
  write_test a.test.ts "case old pass"
  git add -A && git commit -qm "test(greet): an existing test"
  open_l_task
  write_test a.test.ts "case old pass" ""
  bash "$SCRIPTS/suite.sh" record >/dev/null
  expect_fail "no recorded test fails" bash "$SCRIPTS/red-check.sh"
}

test_red_check_without_test_files_is_skipped() {
  set_config test_files ''
  git add -A && git commit -qm "chore(repo): no test_files"
  open_l_task
  write_test a.test.ts "case one assert"
  bash "$SCRIPTS/suite.sh" record >/dev/null
  out="$(bash "$SCRIPTS/red-check.sh")"
  [[ "$out" == *"red check skipped"* ]] || fail "$out"
  grep -q $'\tred-check\tskipped' "$(git rev-parse --git-path overload)/runs.log" || fail "not logged"
}

test_red_check_without_xml_says_so() {
  set_config test_files 'echo nothing {files}'
  git add -A && git commit -qm "chore(repo): no xml"
  open_l_task
  write_test a.test.ts "case one assert"
  bash "$SCRIPTS/suite.sh" record >/dev/null
  expect_fail "printed no JUnit XML" bash "$SCRIPTS/red-check.sh"
}

test_integrate_clears_the_suite() {
  open_l_task
  write_test greet.test.ts "case a assert"
  bash "$SCRIPTS/suite.sh" record >/dev/null
  git update-ref refs/overload/base/feature/greet/default-name HEAD
  bash "$SCRIPTS/verify.sh" >/dev/null
  bash "$SCRIPTS/commit.sh" "$(message 'feat(greet): x')" >/dev/null
  bash "$SCRIPTS/integrate.sh" >/dev/null
  [[ -z "$(git for-each-ref refs/overload/suite refs/overload/base)" ]] || fail "suite refs left"
}

test_integrate_refuses_an_l_spec_not_done() {
  open_l_task
  mkdir -p .workflow/specs
  printf -- '---\nstatus: approved\n---\n\n## Chunks\n\n- [x] 1. first\n- [ ] 2. second\n' >.workflow/specs/s.md
  bash "$SCRIPTS/journal.sh" set spec .workflow/specs/s.md
  bash "$SCRIPTS/verify.sh" >/dev/null
  bash "$SCRIPTS/commit.sh" "$(message 'docs(greet): spec')" >/dev/null
  expect_fail "chunks not ticked" bash "$SCRIPTS/integrate.sh"
  sed -i.bak 's/^- \[ \] 2/- [x] 2/' .workflow/specs/s.md && rm .workflow/specs/s.md.bak
  bash "$SCRIPTS/verify.sh" >/dev/null
  bash "$SCRIPTS/commit.sh" "$(message 'docs(greet): tick')" >/dev/null
  expect_fail "is not 'status: done'" bash "$SCRIPTS/integrate.sh"
  sed -i.bak 's/^status: approved/status: done/' .workflow/specs/s.md && rm .workflow/specs/s.md.bak
  bash "$SCRIPTS/verify.sh" >/dev/null
  bash "$SCRIPTS/commit.sh" "$(message 'docs(greet): done')" >/dev/null
  bash "$SCRIPTS/integrate.sh" >/dev/null
}
