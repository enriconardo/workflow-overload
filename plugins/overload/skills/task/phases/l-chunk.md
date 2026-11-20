# L path: chunks

Each chunk goes through agents that did not write the spec, and scripts, and ends in a green commit. The chunk to work is the first one the spec does not tick; its phase is `l/chunk-<n>/<step>`.

A chunk's first step is `stub` when its line names `signatures` or `dependencies`, otherwise `test` when it is test-first or a chunk of tests only (tests, with their fixtures and helpers), otherwise `implement`: a chunk of docs or config only goes to the implementer.

## Per chunk

### 0. Stubs — `l/chunk-<n>/stub`, only when the chunk line names `signatures` or `dependencies`

The test-author cannot stub a declaration that already exists (a changed constructor or parameter list), and installs nothing, while a test of code that imports a missing package does not load. Run the `overload:step-implementer` agent in stub mode, with the spec's path, the chunk's number, and its signatures and dependencies. It adds the dependencies, changes only the signatures, each body a stub, and it writes no test. Do not commit. Then go on with 1.

### 1. Tests — `l/chunk-<n>/test`, test-first chunks and chunks of tests only

Run the `overload:step-test-author` agent with the spec's path, the chunk's number, the config's `rules`, `tests_glob` and `integrate_tests_glob`, and the scripts' folder. It writes the chunk's tests before any code, and stubs only for the new interfaces the spec declares, and records the suite with `suite.sh record`. It never reads the source the chunk changes. When it reports a module the tests need and the project lacks, add it to the chunk line's `dependencies` and go back to 0. When it reports that every case of the chunk is at the type level, the chunk has no red: change its type to `no test-first` in the spec, log it, and go to 3. A chunk whose tests all run outside `check` (end-to-end, through `run_integrate_tests`) stays test-first: the red check and verify run them through their own command. Never retype it for that.

### 2. Red check — `l/chunk-<n>/red`, test-first chunks only

`bash <scripts>/red-check.sh`. It checks the valid red that `overload:step-test-author` defines. A new test that passes already is listed in `red-check-green.txt` under the state folder the script names, for the step review. When it says it was skipped (no `run_tests` in the config), log that and go on; when it skipped some files only (no `run_integrate_tests`), log those files, and the rest is judged as usual. Otherwise the report goes back to the test-author as it came, for a new record and a new red check; three rounds at most, then `phases/escalate.md`. When the code is already in the working tree (a suite recorded again after a test reported wrong), run `red-check.sh --without-code`: it runs the suite against the source as it was at the last valid red, the stubs included, and puts the working tree back.

### 3. Implementation — `l/chunk-<n>/implement`

Run the `overload:step-implementer` agent with the spec's path, the chunk's number, the recorded test files (`suite.sh files`), the config's `rules`, and, on a later round, the findings to fix. It writes the code that makes the tests pass and no test: commit.sh refuses a tree where a recorded test changed, or, on a test-first chunk, any other test file.

Read its report before verify, heading by heading:

- **No report**, one without the headings of its *Output* (an empty or one-word answer): do not redo its work or its checks yourself. Ask it once for the report, continuing it with `SendMessage` when you can, else running it again on the chunk with a note that the working tree holds its work; still none, `phases/escalate.md`.
- **Not done**: each item is settled before verify. One the implementer can finish goes back to it; one it cannot goes under *Open findings*, for the human.
- **Cases missing**: to the test-author, who records the suite again, and the red check runs again.
- **Tests wrong**: decide on the spec (*A test reported wrong*).

### 4. Verify — `l/chunk-<n>/verify`

`bash <scripts>/verify.sh`. After `check`, it runs every suite recorded on the branch, this chunk's and the earlier ones', each file through the command of its glob (`run_tests`, or `run_integrate_tests` for those `check` leaves out), and wants them green: a test `check` leaves out still guards the chunks that follow. Red: back to the implementer with the output; the script stops you at the third red in a row.

### 5. Step review — `l/chunk-<n>/review`, when the spec has more than one chunk or the red check listed tests that pass already

Run the `overload:step-reviewer` agent with the spec's path, the chunk's number, the recorded test files, the range (the working tree against `HEAD`), and the red check's list of tests that passed already, if any. It checks that the code does what the chunk asks, and that the tests cover it. Code findings go back to the implementer (to 3). A test finding, a case with no test or a test that stays green when its behavior breaks, goes back to the test-author with the finding and the path of its mutant's diff file: it writes or fixes the test after the code, and shows its red as its *After the code* says. Then, on a test-first chunk, `red-check.sh --without-code`; on any chunk, verify (4): red there, the test found a fault in the code, which goes to the implementer. A test the finding calls wrong is handled as a test reported wrong. Three rounds at most per chunk. At each round, increment `step_review_rounds` in the journal, which counts the rounds of all chunks together, and log it with the chunk (`journal.sh log "step review chunk <n> round <k>: <m> findings"`); the final review's `review_rounds` stays its own.

### 6. Commit — `l/chunk-<n>/commit`

Tick the chunk in the spec (`- [x]`), then verify and commit: one commit for the chunk, its tests, its code and its tick, its message as *Names and messages* in the skill's rules says, the chunk's title in the body. Set the phase to the next chunk's first step.

## A chunk of tests only

A chunk that only adds tests, the behavior coming from earlier chunks, has no red: the splitter marks it no test-first. The test-author writes and records its tests (1) and nobody implements: the step review (5) always runs for it, given every one of its tests as the list of tests that pass already.

## A test reported wrong

A test "in the way" is how a test most often gets loosened to let code pass, so the one who must make it pass does not decide. You do, rereading the spec:

- the spec agrees with the test: back to the implementer;
- the spec disagrees: back to the test-author, who fixes it, records the suite again, and the red check runs again;
- the spec is ambiguous or silent: the human decides, since it is a decision on the spec. Note it under *Open findings* and ask.

## After the last chunk

Verify the whole branch (`verify.sh`), then go on with `phases/close.md`.
