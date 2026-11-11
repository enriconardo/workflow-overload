# L path: chunks

Each chunk goes through agents that did not write the spec, and scripts, and ends in a green commit. The chunk to work is the first one the spec does not tick; its phase is `l/chunk-<n>/<step>`.

A chunk's first step is `stub` when its line names `signatures` or `dependencies`, otherwise `test` when it is test-first or changes no source file, otherwise `implement`.

## Per chunk

### 0. Stubs — `l/chunk-<n>/stub`, only when the chunk line names `signatures` or `dependencies`

The test-author cannot stub a declaration that already exists (a changed constructor or parameter list), and installs nothing, while a test of code that imports a missing package does not load. Run the `workflow-overload:step-implementer` agent in stub mode, with the spec's path, the chunk's number, its signatures and dependencies, and the config's `stub` and `exec`. It adds the dependencies, changes only the signatures, each body the `stub` statement, and it writes no test. Do not commit. Then go on with 1.

### 1. Tests — `l/chunk-<n>/test`, test-first chunks and chunks with no source to change

Run the `workflow-overload:step-test-author` agent with the spec's path, the chunk's number, the config's `rules`, `tests_glob`, `stub` and `reference`, and the scripts' folder. It writes the chunk's tests before any code, and stubs only for the new interfaces the spec declares, and records the suite with `suite.sh record`. It never reads the source the chunk changes. When it reports a module the tests need and the project lacks, add it to the chunk line's `dependencies` and go back to 0.

### 2. Red check — `l/chunk-<n>/red`, test-first chunks only

`bash <scripts>/red-check.sh`. Valid red: every new test fails on an assertion or a stub's `NotImplemented`, or passes already; a test already in HEAD may pass. A new test that passes already (the code of an earlier chunk covers it) is listed in `red-check-green.txt` under the state folder the script names, for the step review. When it says it was skipped (no `test_files` in the config), log that and go on. Otherwise the report goes back to the test-author as it came, for a new record and a new red check; three rounds at most, then `phases/escalate.md`. When the code is already in the working tree (a suite recorded again after a test reported wrong), run `red-check.sh --without-code`: it runs the suite against the source as it was at the last valid red, the stubs included, and puts the working tree back.

### 3. Implementation — `l/chunk-<n>/implement`

Run the `workflow-overload:step-implementer` agent with the spec's path, the chunk's number, the recorded test files (`suite.sh files`), the config's `rules` and `exec`, and, on a later round, the findings to fix. It writes the code that makes the tests pass and no test: commit.sh refuses a tree where a recorded test changed, or, on a test-first chunk, any other test file. A case it reports missing goes to the test-author, who records the suite again, and the red check runs again.

When it reports a test it thinks wrong, decide on the spec (*A test reported wrong*).

### 4. Verify — `l/chunk-<n>/verify`

`bash <scripts>/verify.sh`. Red: back to the implementer with the output; the script stops you at the third red in a row.

### 5. Step review — `l/chunk-<n>/review`, when the spec has more than one chunk or the red check listed tests that pass already

Run the `workflow-overload:step-reviewer` agent with the spec's path, the chunk's number, the recorded test files, the range (the working tree against `HEAD`), and the red check's list of tests that passed already, if any. It checks that the code does what the chunk asks, and that the tests cover it. Code findings go back to the implementer (to 3); a test finding is handled as a test reported wrong. Three rounds at most per chunk. At each round, increment `step_review_rounds` in the journal, which counts the rounds of all chunks together, and log it with the chunk (`journal.sh log "step review chunk <n> round <k>: <m> findings"`); the final review's `review_rounds` stays its own.

### 6. Commit — `l/chunk-<n>/commit`

Tick the chunk in the spec (`- [x]`), then verify and commit: one commit for the chunk, its tests, its code and its tick, the subject in the config's format, the chunk's title in the body. Set the phase to the next chunk's first step.

## A chunk with no source to change

A chunk that only adds tests, the behavior coming from earlier chunks, has no red: the splitter marks it no test-first. The test-author writes and records its tests (1) and nobody implements: the step review (5) always runs for it, given every one of its tests as the list of tests that pass already.

## A test reported wrong

A test "in the way" is how a test most often gets loosened to let code pass, so the one who must make it pass does not decide. You do, rereading the spec:

- the spec agrees with the test: back to the implementer;
- the spec disagrees: back to the test-author, who fixes it, records the suite again, and the red check runs again;
- the spec is ambiguous or silent: the human decides, since it is a decision on the spec. Note it under *Open findings* and ask.

## After the last chunk

Verify the whole branch (`verify.sh`), then go on with `phases/close.md`.
