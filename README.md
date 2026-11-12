# Workflow Overload

A development workflow for [Claude Code](https://claude.com/claude-code), packaged as the plugin `workflow-overload`. It takes a request to a verified merge, spends agents and checks in proportion to the task, and starts only when you type `/overload`.

> **Status: 0.2.** Brainstorming, triage, the S path and the L path work: spec, probe, spec review, split, checkpoint 1, chunks written test-first by a test author that never reads the code under change, red check, implementer, step review, then the final review, lessons, checkpoint 2 and integration.

## Principles

- **Who writes does not judge.** Code, and later specs and tests, are reviewed by agents with a clean context, which report and never fix.
- **The main agent holds the intent and stays light.** Exploring and reviewing go to agents, which return only their result; on a plainly small change it reads the files it changes itself, since it would read them anyway.
- **Mechanical checks are scripts.** Verify is green or red, and a commit takes only the tree that verify just checked.
- **The human decides where it matters**: the tier, the result, the lessons and backlog items to keep, and every loop that does not converge in three rounds.

## Install

```
/plugin marketplace add enriconardo/workflow-overload
/plugin install workflow-overload@workflow-overload
```

Scripts need `bash`, `git` and `python3` (3.8 or later, standard library only).

## Use

| Command | What it does |
| --- | --- |
| `/overload setup [guidance]` | An agent reads the project, following your guidance if you give any ("take the commands from the Makefile"), and proposes `.workflow/config`, each value with its source, and the conventions your rule files lack; you settle it. Then verify must be green on main, a second agent measures `red_types` with throwaway tests, and it commits on your go. |
| `/overload <request>` | Opens a task: brainstorming, then the S or the L path. |
| `/overload` | Resumes the task of the current branch from its journal, after an interruption or a `/clear`. |

Inside a task the scripts that open the branch, update the journal, verify, commit and handle the suite run without a permission prompt; `integrate.sh` asks each time, on top of your go at the checkpoint. Without `/overload`, a session works as it would without the plugin: the entry skill cannot be invoked by the model, the agents declare themselves internal, and the hooks stay silent on a branch without a journal.

## The S path

For changes nothing outside sees (or docs, config, tooling), in one area, with clear requirements:

1. **Brainstorming**: restate the request, map the code (`code-explorer`; on a plainly small change, the main agent reads the files and their callers itself), ask, propose S or L; you confirm.
2. **Branch**: `branch.sh` opens it from an up-to-date main and writes the journal.
3. **Implement, verify, commit**: a bug fix starts from a failing test; `commit.sh` refuses any tree but the verified one.
4. **Final review** (`code-reviewer`): six blocking cases, findings at confidence 80 or more; fixes are commits of their own, and a new round reviews only what changed.
5. **Lessons** (`lesson-critic`): rules proposed only for problems that got past the step meant to catch them, judged before you see them.
6. **Checkpoint**: you give the go and pick the lessons and backlog items to keep.
7. **Integrate**: `integrate.sh` merges with `--no-ff` without the journal, adds a line of measures to `.workflow/metrics.jsonl`, re-verifies the merge's result when main moved, and leaves main untouched on a conflict or a red verify.

A task that turns out bigger goes to the L path on your go: its commits stay, uncommitted work goes in a stash, and the spec describes the whole change, its chunks only what is left.

## The L path

For everything else:

1. **Spec**, written by the main agent, which held the discussion; a decision record for a decision that outlives the task.
2. **Probe** (`prober`), only for external facts the spec rests on, in a temporary folder outside the repository, on the project's runtime.
3. **Spec review** (`spec-reviewer`): correctness, and a critique of the premises: was the problem seen, what is the strongest alternative, what is missing. It gets the spec and the code map, never a summary of the discussion.
4. **Split** (`spec-splitter`), above about 6–7 files or 10–15 test cases: the fewest chunks, each green alone, each test-first or not.
5. **Checkpoint 1**: you approve the plan; a `/clear` and `/overload` then resume from the journal with a small context.
6. **Per chunk**: tests first (`step-test-author`, which never reads the code under change, and records its suite with `suite.sh`), the **red check** (`red-check.sh`: every new test fails on an assertion or a stub's `NotImplemented`, not on an import error, while those already in HEAD may pass; a new one that passes already goes to the step reviewer, who checks it fails under a mutant, read from the runner's JUnit XML), the code (`step-implementer`, which cannot touch the recorded tests: `commit.sh` refuses), verify, the step review, a commit that ticks the chunk.
7. **Close** as on the S path, with the spec as the reference of the final review.

## Configuration

`.workflow/config` holds what is the project's own, as `key = value` lines that scripts read without executing; `/overload setup` writes it. The plugin owns when a check runs and the process around it: a commit takes only the verified tree, the test-author's suite stays untouched, a task starts from a clean main and merges with `--no-ff`. The project owns its commands, its names and its messages.

```
version    = 1
check      = pnpm check                                 # the commit gate, see *check*; empty: nothing checked
run_tests  = pnpm vitest run --reporter=junit {files}   # runs the given test files, prints JUnit XML; empty: no red check
main       = main
integrate  = merge
rules      = CLAUDE.md, docs/adr/
backlog    = .workflow/backlog.md
tests_glob = **/__tests__/**
red_types  = AssertionError, NotImplemented
```

| Key | Default | What it holds |
| --- | --- | --- |
| `version` | none, required | `1` |
| `check` | none, required, may be empty | the command that checks the whole tree before every commit |
| `run_tests` | empty: the red check is skipped | the command that runs the test files in `{files}` and prints JUnit XML |
| `main` | `main` | the branch tasks start from and merge into |
| `integrate` | `merge` | how a task lands: a local `--no-ff` merge, the only mode so far |
| `rules` | `CLAUDE.md` | the files and folders of the project's rules, comma-separated; decision records go in a folder of them |
| `backlog` | `.workflow/backlog.md` | where the backlog items the human approves go |
| `tests_glob` | the usual test file names of JavaScript, TypeScript, Python and Go | which files are tests: the suite records them, and `commit.sh` protects them |
| `red_types` | `AssertionError, NotImplemented` | the failure types the runner reports for an assertion and for a stub |

A value never holds ` #`, which starts a comment. A key the version does not know is refused, and so is a config without `check`: a misspelt key would otherwise leave `check` empty, and every commit would pass unchecked. Any key can be overridden for one session by `OVERLOAD_<KEY>`, even to empty: a session that cannot reach the project's container sets `OVERLOAD_CHECK` and `OVERLOAD_RUN_TESTS`.

Branch names and commit messages follow the project's rules (its CLAUDE.md, its contributing docs); where they state none, a branch `<type>/<description>` in kebab-case and a subject in the imperative of at most 72 characters. The project's hooks enforce them: `branch.sh` runs the `commit-msg` hook on the merge's subject before the task starts (git 2.36 or later), and `commit.sh` undoes a commit whose tree a `pre-commit` hook changed after the check. Stubs, the L specs (`.workflow/specs/`) and the test-author's reference model (`.workflow/reference/`) are the plugin's own: a stub only throws the language's not-implemented error, and `red_types` names the type the runner reports for it (`NotImplementedError` in Python).

### check

`check` is the commit gate: `verify.sh` runs it before every commit, and on the merge's result when main moved, and `commit.sh` takes only a tree it found green. It is a local subset of what the CI runs, and it:

- exits 0 on green, anything else on red;
- ends on its own: no watch mode, no prompt;
- changes no file: `--check`, not `--fix`. `verify.sh` hashes the tree again after the run, and a run that changed a file git does not ignore is red, with the files it changed;
- runs locally, with no secrets or services;
- is fast enough to run before every commit, and gives the same result on the same tree;
- prints the cause of a red in its last lines, the ones `verify.sh` shows.

It checks the whole tree, never only what changed: on main, at the first verify and on the merge's result, a scoped command would check nothing. Some examples:

```
check = make check
check = pnpm lint && pnpm typecheck && pnpm vitest run       # vitest run: no watch mode
check = pnpm prettier --check . && pnpm jest --ci             # --ci: a missing snapshot fails, it is not written
check = uv run ruff format --check . && uv run ruff check . && uv run pytest -q
check = docker compose exec -T app make check                # -T: no terminal needed
```

Before the first task, try it on a clean main:

```
git status --short          # nothing
<check>; echo "exit $?"     # exit 0, and it ended on its own
git status --short          # still nothing: the check changed no file
```

Run it twice: the same result both times, in a time you would wait for at every commit.

## Files in a project

| File | Lives | Holds |
| --- | --- | --- |
| `.workflow/config` | main | the project's settings |
| `.workflow/backlog.md` | main | the items the human approved at a checkpoint |
| `.workflow/metrics.jsonl` | main | one line per integrated task: rounds, verify runs, commits, files, tokens per role |
| `.workflow/journal.md` | the task's branch | phase, intent, candidates, open findings; dropped at the merge |
| `.workflow/specs/` | main | the L specs, ticked chunk by chunk |
| `.git/overload/` | the clone | the verified tree and the log of verify runs and red checks |
| `refs/overload/suite/<branch>/<n>` | the clone | the test-author's recorded suites, outside every branch; deleted at the merge |

## Measures

`plugins/workflow-overload/scripts/metrics.py` also reads the Claude Code transcripts of a project (`transcripts`) and the merges of its history (`git`), to compare a workflow with the one before it. Claude Code deletes transcripts after 30 days: set `"cleanupPeriodDays"` in `~/.claude/settings.json` to keep them.

## Development

See [CLAUDE.md](CLAUDE.md). `tests/run.sh` tests the scripts, `python3 -m unittest discover -s tests` the measures.

## License

[MIT](LICENSE)
