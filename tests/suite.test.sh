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

test_a_renamed_test_file_stays_in_the_suite() {
  write_test old.test.ts "case a pass" "case b pass" "case c pass"
  git add -A && git commit -qm "test(greet): an existing test"
  open_l_task
  git mv __tests__/old.test.ts __tests__/new.test.ts
  printf '%s\n' "case d assert" >>__tests__/new.test.ts
  bash "$SCRIPTS/suite.sh" record >/dev/null
  bash "$SCRIPTS/suite.sh" files | grep -qx "__tests__/old.test.ts" || fail "the old path is not in the suite"
  bash "$SCRIPTS/suite.sh" check
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

# The tests `check` leaves out, end-to-end in e2e/, run by their own command.
integrate_tests() {
  set_config integrate_tests_glob 'e2e/**'
  git add -A && git commit -qm "chore(repo): tests outside check"
}

write_e2e() {
  mkdir -p e2e
  printf '%s\n' "${@:2}" >"e2e/$1"
}

test_suite_records_and_guards_the_tests_outside_check() {
  integrate_tests
  write_e2e old.e2e.ts "case old pass"
  git add -A && git commit -qm "test(greet): an existing end-to-end test"
  open_l_task
  write_e2e a.e2e.ts "case a assert"
  write_test b.test.ts "case b assert"
  bash "$SCRIPTS/suite.sh" record >/dev/null
  expect_eq "$(bash "$SCRIPTS/suite.sh" files)" $'__tests__/b.test.ts\ne2e/a.e2e.ts'
  write_e2e a.e2e.ts "case a pass"
  expect_fail "e2e/a.e2e.ts" bash "$SCRIPTS/suite.sh" check
  write_e2e a.e2e.ts "case a assert"
  write_e2e old.e2e.ts "case old skip"
  expect_fail "not in the suite the test-author recorded" bash "$SCRIPTS/suite.sh" check
}

# A second runner for the tests outside check, which says it ran.
e2e_runner() {
  fake_runner
  integrate_tests
  set_config run_integrate_tests 'echo "e2e runner"; python3 runner.py {files}'
  git add -A && git commit -qm "chore(repo): an end-to-end runner"
}

test_red_check_runs_each_test_file_through_its_own_command() {
  e2e_runner
  write_e2e old.e2e.ts "case old pass"
  git add -A && git commit -qm "test(greet): an existing end-to-end test"
  open_l_task
  write_test a.test.ts "case green pass"
  write_e2e old.e2e.ts "case old pass" "case new notimpl"
  bash "$SCRIPTS/suite.sh" record >/dev/null
  out="$(bash "$SCRIPTS/red-check.sh")"
  [[ "$(red_report)" == *"e2e/old.e2e.ts > old: passes, already in HEAD"* ]] || fail "existing: $(red_report)"
  [[ "$(red_report)" == *"e2e/old.e2e.ts > new: red, NotImplemented"* ]] || fail "red: $(red_report)"
  [[ "$out" == *"valid red"*"1 new test passes already"* ]] || fail "across both runs: $out"
  state="$(git rev-parse --git-path overload)"
  grep -q "e2e runner" "$state/red-check-integrate-output.txt" || fail "not through run_integrate_tests"
  ! grep -q "e2e/" "$state/red-check-output.txt" || fail "an end-to-end test ran through run_tests"
  expect_eq "$(cat e2e/old.e2e.ts)" $'case old pass\ncase new notimpl' "the working file restored"
}

test_red_check_names_only_the_output_its_runs_wrote() {
  e2e_runner
  open_l_task
  write_e2e a.e2e.ts "case a typeerror"
  bash "$SCRIPTS/suite.sh" record >/dev/null
  set +e
  out="$(bash "$SCRIPTS/red-check.sh" 2>&1)"
  set -e
  [[ "$out" == *"red-check-integrate-output.txt"* && "$out" != *"red-check-output.txt"* ]] || fail "$out"
}

test_red_check_without_run_integrate_tests_skips_only_those_files() {
  fake_runner
  integrate_tests
  open_l_task
  write_test a.test.ts "case a assert"
  write_e2e b.e2e.ts "case b assert"
  bash "$SCRIPTS/suite.sh" record >/dev/null
  out="$(bash "$SCRIPTS/red-check.sh")"
  [[ "$out" == *"e2e/b.e2e.ts"*"no 'run_integrate_tests'"* && "$out" == *"valid red"* ]] || fail "$out"
  # the chunk's test in check withdrawn: only the skipped file is left
  rm -r __tests__
  write_e2e b.e2e.ts "case b notimpl"
  bash "$SCRIPTS/suite.sh" record >/dev/null
  out="$(bash "$SCRIPTS/red-check.sh")"
  [[ "$out" == *"red check skipped"* ]] || fail "only skipped files: $out"
}

test_red_check_names_the_command_that_printed_no_xml() {
  fake_runner
  integrate_tests
  set_config run_integrate_tests 'echo nothing {files}'
  git add -A && git commit -qm "chore(repo): an end-to-end runner without xml"
  open_l_task
  write_test a.test.ts "case a assert"
  write_e2e b.e2e.ts "case b assert"
  bash "$SCRIPTS/suite.sh" record >/dev/null
  expect_fail "check the config's run_integrate_tests" bash "$SCRIPTS/red-check.sh"
}

# the red check's line per testcase, which it leaves in the state folder
red_report() {
  cat "$(git rev-parse --git-path overload)/red-check-report.txt"
}

test_red_check_prints_a_summary_and_leaves_each_test_in_its_report() {
  fake_runner
  open_l_task
  write_test a.test.ts "case one assert" "case two assert" "case three notimpl"
  bash "$SCRIPTS/suite.sh" record >/dev/null
  out="$(bash "$SCRIPTS/red-check.sh")"
  [[ "$out" == *"valid red"* && "$out" == *"reds: AssertionError 2 new; NotImplemented 1 new"* ]] || fail "$out"
  [[ "$out" == *"2 × AssertionError: expected 1 to be 2"* ]] || fail "shared message: $out"
  [[ "$out" != *"a.test.ts > one"* ]] || fail "a line per testcase: $out"
  [[ "$out" == *"the report, a line per test: $(git rev-parse --git-path overload)/red-check-report.txt"* ]] || fail "$out"
  [[ "$(red_report)" == *"__tests__/a.test.ts > one: red, AssertionError"* ]] || fail "$(red_report)"
  # a run with no XML leaves no report of an earlier run behind
  set_config run_tests 'echo nothing {files}'
  expect_fail "printed no JUnit XML" bash "$SCRIPTS/red-check.sh"
  [[ ! -e "$(git rev-parse --git-path overload)/red-check-report.txt" ]] || fail "a stale report"
}

test_red_check_accepts_assertions_and_not_implemented() {
  fake_runner
  open_l_task
  write_test a.test.ts "case one assert" "case two notimpl"
  bash "$SCRIPTS/suite.sh" record >/dev/null
  out="$(bash "$SCRIPTS/red-check.sh")"
  [[ "$out" == *"valid red, every new test fails"* ]] || fail "$out"
}

test_red_check_reads_a_report_the_runner_writes_to_dev_stdout() {
  fake_runner
  # as pytest --junitxml=/dev/stdout: the report opens /dev/stdout anew, around the runner's own lines
  cat >"$REPO/stdout-runner.py" <<'PY'
import subprocess, sys
report = subprocess.run([sys.executable, "runner.py"] + sys.argv[1:], capture_output=True, text=True).stdout
print("collected 2 items", flush=True)
with open("/dev/stdout", "w") as handle:
    handle.write(report[report.index("<?xml"):])
print("2 failed in 0.01s", flush=True)
PY
  set_config run_tests 'python3 stdout-runner.py {files}'
  git add -A && git commit -qm "chore(repo): a runner that writes its report to /dev/stdout"
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
  report="$(red_report)"
  [[ "$report" == *"a.test.ts"*"LOAD ERROR"* ]] || fail "load: $report"
  [[ "$report" == *"b.test.ts > green: passes already"* ]] || fail "pass: $report"
  [[ "$report" == *"c.test.ts > s: skipped"* ]] || fail "skip: $report"
  [[ "$report" == *"d.test.ts > t: red for the wrong reason, TypeError"* ]] || fail "type: $report"
  [[ "$report" == *"b.test.ts > red: red, AssertionError"* ]] || fail "red ok: $report"
  [[ "$out" == *"1 × red for the wrong reason, TypeError"*"(e.g. __tests__/d.test.ts > t)"* ]] || fail "summary: $out"
}

test_red_check_judges_only_the_tests_new_to_a_file() {
  fake_runner
  write_test a.test.ts "case old pass"
  git add -A && git commit -qm "test(greet): an existing test"
  open_l_task
  write_test a.test.ts "case old pass" "case new assert"
  bash "$SCRIPTS/suite.sh" record >/dev/null
  out="$(bash "$SCRIPTS/red-check.sh")"
  [[ "$(red_report)" == *"a.test.ts > old: passes, already in HEAD"* && "$out" == *"valid red"* ]] || fail "$out"
  expect_eq "$(git show HEAD:__tests__/a.test.ts)" "case old pass" "HEAD untouched"
  expect_eq "$(cat __tests__/a.test.ts)" $'case old pass\ncase new assert' "the working file restored"

  write_test a.test.ts "case old typeerror" "case new pass"
  bash "$SCRIPTS/suite.sh" record >/dev/null
  set +e
  out="$(bash "$SCRIPTS/red-check.sh" 2>&1)"
  status=$?
  set -e
  expect_eq "$status" 1
  [[ "$(red_report)" == *"a.test.ts > new: passes already"* ]] || fail "new pass: $(red_report)"
  [[ "$(red_report)" == *"a.test.ts > old: red for the wrong reason, TypeError"* ]] || fail "old type: $(red_report)"
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
  set_config run_tests 'cat greet.ts; python3 runner.py {files}'
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
  set_config run_tests 'ls; python3 runner.py {files}'
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

test_red_check_without_run_tests_is_skipped() {
  set_config run_tests ''
  git add -A && git commit -qm "chore(repo): no run_tests"
  open_l_task
  # as before the tests outside check: skipped before the suite is looked at
  out="$(bash "$SCRIPTS/red-check.sh")"
  [[ "$out" == *"red check skipped"* ]] || fail "no suite: $out"
  write_test a.test.ts "case one assert"
  bash "$SCRIPTS/suite.sh" record >/dev/null
  out="$(bash "$SCRIPTS/red-check.sh")"
  [[ "$out" == *"red check skipped"* ]] || fail "$out"
  [[ ! -e "$(git rev-parse --git-path overload)/runs.log" ]] || fail "run log written"
}

test_junit_types_found_prints_what_the_runner_reported() {
  fake_runner
  write_test probe-assert.test.ts "case a assert"
  write_test probe-stub.test.ts "case s notimpl"
  write_test probe-load.test.ts "load"
  files=(__tests__/probe-assert.test.ts __tests__/probe-stub.test.ts __tests__/probe-load.test.ts)
  python3 runner.py "${files[@]}" >"$WORK/out.txt"
  out="$(python3 "$SCRIPTS/junit.py" --types-found "$WORK/out.txt" "${files[@]}" __tests__/missing.test.ts)"
  expect_eq "$out" "__tests__/probe-assert.test.ts > a: AssertionError
__tests__/probe-stub.test.ts > s: NotImplemented
__tests__/probe-load.test.ts > __tests__/probe-load.test.ts: LOAD ERROR
__tests__/missing.test.ts: not in the runner's report"
  echo nothing >"$WORK/empty.txt"
  expect_fail "printed no JUnit XML" python3 "$SCRIPTS/junit.py" --types-found "$WORK/empty.txt" "${files[@]}"
}

test_red_check_without_xml_says_so() {
  set_config run_tests 'echo nothing {files}'
  git add -A && git commit -qm "chore(repo): no xml"
  open_l_task
  write_test a.test.ts "case one assert"
  bash "$SCRIPTS/suite.sh" record >/dev/null
  expect_fail "printed no JUnit XML" bash "$SCRIPTS/red-check.sh"
}

test_verify_runs_every_recorded_suite_of_the_branch() {
  fake_runner
  open_l_task
  write_test first.test.ts "case a pass" "case s skip"
  bash "$SCRIPTS/suite.sh" record >/dev/null
  out="$(bash "$SCRIPTS/verify.sh")"
  [[ "$out" == *"verify: green"*"the recorded tests"* ]] || fail "$out"
  grep -q "1 passed, 1 skipped, in 1 file" "$(git rev-parse --git-path overload)/verify-output.txt" || fail "no count"
  bash "$SCRIPTS/commit.sh" "$(message 'feat(greet): first')" >/dev/null
  # the next chunk: its suite and the first one run together
  write_test second.test.ts "case b assert"
  bash "$SCRIPTS/suite.sh" record >/dev/null
  if out="$(bash "$SCRIPTS/verify.sh" 2>&1)"; then fail "green: $out"; fi
  [[ "$out" == *"second.test.ts > b: fails, AssertionError"*"verify: red"*"the recorded tests"* ]] || fail "$out"
  # shellcheck source=../plugins/overload/scripts/lib.sh
  source "$SCRIPTS/lib.sh"
  is_verified && fail "a red suite left the tree verified"
  expect_eq "$(bash "$SCRIPTS/journal.sh" get verify_red_streak)" "1"
}

test_verify_runs_the_recorded_tests_outside_check_through_their_command() {
  e2e_runner
  open_l_task
  write_test a.test.ts "case a pass"
  write_e2e b.e2e.ts "case b pass"
  bash "$SCRIPTS/suite.sh" record >/dev/null
  out="$(bash "$SCRIPTS/verify.sh")"
  [[ "$out" == *"verify: green"*"the recorded tests"* ]] || fail "$out"
  state="$(git rev-parse --git-path overload)"
  grep -q "e2e runner" "$state/verify-integrate-suite-output.txt" || fail "not through run_integrate_tests"
  grep -q "2 passed, 0 skipped, in 2 files" "$state/verify-output.txt" || fail "not judged as one run"
  bash "$SCRIPTS/commit.sh" "$(message 'feat(greet): first')" >/dev/null
  write_e2e c.e2e.ts "case c assert"
  bash "$SCRIPTS/suite.sh" record >/dev/null
  if out="$(bash "$SCRIPTS/verify.sh" 2>&1)"; then fail "green: $out"; fi
  [[ "$out" == *"e2e/c.e2e.ts > c: fails, AssertionError"* ]] || fail "$out"
  set_config run_integrate_tests 'echo "e2e runner"; python3 runner.py {files}; exit 4'
  write_e2e c.e2e.ts "case c pass"
  bash "$SCRIPTS/suite.sh" record >/dev/null
  expect_fail "run_integrate_tests exited 4" bash "$SCRIPTS/verify.sh"
}

test_verify_and_red_check_match_each_run_to_its_own_files() {
  fake_runner
  set_config integrate_tests_glob 'e2e/**/*.spec.ts'
  set_config run_integrate_tests 'python3 runner.py --base {files}'
  git add -A && git commit -qm "chore(repo): an end-to-end runner naming suites by file name"
  open_l_task
  mkdir -p src
  printf 'case u pass\n' >src/login.spec.ts
  write_e2e login.spec.ts "case e pass"
  bash "$SCRIPTS/suite.sh" record >/dev/null
  out="$(bash "$SCRIPTS/verify.sh")"
  [[ "$out" == *"verify: green"* ]] || fail "verify: $out"
  printf 'case e pass\ncase f assert\n' >e2e/login.spec.ts
  bash "$SCRIPTS/suite.sh" record >/dev/null
  out="$(bash "$SCRIPTS/red-check.sh")"
  [[ "$out" == *"valid red"* && "$(red_report)" == *"e2e/login.spec.ts > f: red, AssertionError"* ]] || fail "red check: $out"
  # within one run: the suite login.spec.ts ends e2e/admin/login.spec.ts too
  bash "$SCRIPTS/suite.sh" clear
  mkdir -p e2e/admin
  printf 'case a pass\n' >e2e/admin/login.spec.ts
  write_e2e login.spec.ts "case e pass"
  bash "$SCRIPTS/suite.sh" record >/dev/null
  out="$(bash "$SCRIPTS/verify.sh")"
  [[ "$out" == *"verify: green"* ]] || fail "verify, same name in two folders: $out"
}

test_verify_without_run_integrate_tests_says_their_files_did_not_run() {
  fake_runner
  integrate_tests
  open_l_task
  write_test a.test.ts "case a pass"
  write_e2e b.e2e.ts "case b assert"
  bash "$SCRIPTS/suite.sh" record >/dev/null
  out="$(bash "$SCRIPTS/verify.sh")"
  [[ "$out" == *"verify: green"*"no 'run_integrate_tests'"*"e2e/b.e2e.ts"* ]] || fail "$out"
}

test_verify_is_red_on_a_runner_that_fails_or_prints_no_xml() {
  fake_runner
  set_config run_tests 'echo no xml here {files}'
  git add -A && git commit -qm "chore(repo): a runner without xml"
  open_l_task
  write_test a.test.ts "case a pass"
  bash "$SCRIPTS/suite.sh" record >/dev/null
  expect_fail "printed no JUnit XML" bash "$SCRIPTS/verify.sh"
  set_config run_tests 'python3 runner.py {files}; exit 3'
  expect_fail "exited 3" bash "$SCRIPTS/verify.sh"
}

test_verify_without_run_tests_or_a_suite_runs_check_only() {
  open_l_task
  write_test a.test.ts "case a assert"
  bash "$SCRIPTS/suite.sh" record >/dev/null
  out="$(bash "$SCRIPTS/verify.sh")"
  [[ "$out" == *"verify: green"* && "$out" != *"recorded tests"* ]] || fail "$out"
}

test_verify_leaves_out_the_test_files_a_suite_deletes() {
  fake_runner
  write_test gone.test.ts "case g pass"
  git add -A && git commit -qm "test(greet): gone"
  open_l_task
  git rm -q __tests__/gone.test.ts
  write_test kept.test.ts "case k pass"
  bash "$SCRIPTS/suite.sh" record >/dev/null
  out="$(bash "$SCRIPTS/verify.sh")"
  [[ "$out" == *"verify: green"*"the recorded tests"* ]] || fail "$out"
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
