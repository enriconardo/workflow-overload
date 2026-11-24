# Workflow Overload

A development workflow for [Claude Code](https://claude.com/claude-code), packaged as the plugin `overload` of the marketplace `workflow-overload`. It takes a request to a verified merge, spends agents and checks in proportion to the task, and starts only when you type `/overload:task` or `/overload:build`.

## What this is and why it exists

An agent left alone on a change writes the code, writes the tests that confirm it, reviews its own work and commits whatever it last saw pass. Each of those steps hides the defects of the one before: tests written after the code confirm what it does today, bugs included; a review by the author sees what the author meant, not what they wrote; a long session carries its drift toward the human's first idea into every later step.

Workflow Overload splits those roles. The main agent holds the intent and talks with you; agents with a clean context explore, write tests from the spec without reading the code under change, implement, and review; scripts do every mechanical check, so a commit takes only the tree a green check just saw. A small change goes through a short path (S) with one review; anything that a consumer sees, or that spans areas, goes through a long one (L): a reviewed spec that you approve and that lands on main first, then its build, in a session of its own, in chunks written test-first, each with its review. A change too large for one spec becomes a plan: requirements, the decisions that span them, and items, each a task of its own, S or L, merged into main one at a time. You decide the tier, the result and what the task leaves behind.

It is a plugin with three commands: `/overload:setup` configures a project once, `/overload:task` works on a request, up to the code of a small change, the approved spec of a large one or the approved plan of one too large for a spec, and on the items of that plan; `/overload:build` builds an approved spec. Without them, a session works as it would without the plugin.

### Principles

- **Who writes does not judge.** Code, specs and tests are reviewed by agents with a clean context, which report and never fix.
- **The main agent holds the intent and stays light.** Exploring, probing, implementing an L chunk and reviewing go to agents, which return only their result. On a plainly small change it reads the files it changes itself, since it would read them anyway.
- **Mechanical checks are scripts.** Verify is green or red, a commit takes only the tree verify just checked, and a test-first suite must fail for the right reason before any code is written.
- **The human decides where it matters**: the tier, the result, the lessons and backlog items to keep, and every loop that does not converge in three rounds.
- **The workflow starts only with `/overload:task` or `/overload:build`.** The model cannot invoke the skills, the agents declare themselves internal, and the hooks stay silent on a branch without a task.
- **The project keeps its own conventions.** Its commands, branch names and commit messages live in its config and rule files; the plugin owns only when a check runs and the process around it.

## Quick start

You need Claude Code, `bash`, `git` and `python3` (3.8 or later, standard library only), and a git project whose checks pass on its main branch, or a new one with no commit yet. With git older than 2.36, a task's merge subject is not checked against the project's `commit-msg` hook before the task starts.

1. **Install** the plugin, from Claude Code:

   ```
   /plugin marketplace add enriconardo/workflow-overload
   /plugin install overload@workflow-overload
   ```

   From 0.4 or earlier, where the plugin was named `workflow-overload`: `/plugin uninstall workflow-overload@workflow-overload` first. A project's config stays as it is.

2. **Set up the project.** On its main branch, with a clean tree:

   ```
   /overload:setup
   ```

   An agent reads the project and proposes `.workflow/config`, each value with its source, plus the conventions your rule files lack and, when they name none, a folder for decision records with a template. Answer its questions, accept or change the values; it then runs your `check` on main, which must be green, measures how your test runner reports a failure, and commits the config on your go. Guidance helps when the project is unusual: `/overload:setup take the commands from the Makefile`.

   In a repository with no commit (after `git init`), setup lays only the workflow's skeleton: `check` and `run_tests` empty, the backlog, the branch and commit conventions you settle, and the first commit on the main branch. It chooses no language or tool: the first task does, with its review and decision records, and writes `check` and `run_tests` in the config in its own diff. Until then every commit passes unchecked, and each task says so. After that task, run `/overload:setup` again to measure `red_types`.

3. **Run a first task**, something small:

   ```
   /overload:task fix the typo in the install section of the README
   ```

   It restates the request, asks what is unclear, and proposes S. On your confirmation it opens a branch, makes the change, verifies, commits, runs the final review, and stops at a checkpoint with a summary. Give the go: it merges into main with `--no-ff` and deletes the branch.

That is the whole loop. A larger request goes through the L path in two tasks: `/overload:task` writes its spec, which merges into main once you approve it; then `/overload:build <spec>`, best in a new session, builds it on a branch of its own and merges the code. One too large for a spec gets a plan, merged the same way, and then `/overload:task <plan> <n>` opens each of its items in turn. If a session ends halfway, the command that opened the task, typed without arguments on its branch, resumes it from its journal.

## Configuration and usage

### Commands

| Command | What it does |
| --- | --- |
| `/overload:setup [guidance]` | Proposes `.workflow/config` and the conventions your rule files lack; you settle it. Then verify must be green on main, a second agent measures `red_types` with throwaway tests, and it commits on your go. No branch, no journal. |
| `/overload:task <request>` | Opens a task: brainstorming, then the S path, the spec of an L, or a plan, up to its approval and its merge into main. Name the documents that go with the request (a brief, a mockup, a sample format): they land in `.workflow/inputs/`. |
| `/overload:task <plan> [<n>]` | Opens item `n` of the open plan, as an S task or the spec of an L, when nothing else of the plan is open and the items it depends on are done. Without `n`, shows the next item and the command that works it. |
| `/overload:task <plan> <the change>` | Revises the open plan, or drops it, in a task of its own with its checkpoint. |
| `/overload:task <spec> <why>` | Drops a spec approved on main and not built, in a task of its own with its checkpoint. |
| `/overload:build <spec>` | Builds a spec approved on main, chunk by chunk, on a branch of its own, then merges it. It checks first whether main changed the files the spec rests on since its approval. |
| `/overload:task`, `/overload:build` | On a task's branch, the command that opened the task resumes it from its journal, after an interruption or a `/clear`. On main, `/overload:build` lists the specs to build and chooses none; the status both read names the open plan's next item. |

Inside a task, the scripts that open the branch, update the journal, verify, commit, handle the suite and take in a moved main run without a permission prompt; `integrate.sh` asks each time, on top of your go at the checkpoint. While a task is open, a hook refuses a `git commit` or `git merge` typed directly. On a branch with an open task, a new session is told the task waits for its command, `/overload:task` or `/overload:build`, and a compacted one is told to reread the journal.

### `.workflow/config`

The config holds what is the project's own, as `key = value` lines that scripts read without executing; `/overload:setup` writes it.

```
version              = 1
check                = pnpm check                                # the commit gate, see *check*; empty: nothing checked
check_integrate      = pnpm test:e2e                             # the slow local tests, see *check_integrate*; empty: none
run_tests            = pnpm vitest run --reporter=junit --outputFile=/dev/stdout {files}  # runs the given test files, prints JUnit XML; empty: no red check
run_integrate_tests  = pnpm playwright test --reporter=line,junit {files}                 # the same for the tests check leaves out
main                 = main
integrate            = merge
rules                = CLAUDE.md, docs/adr/
backlog              = .workflow/backlog.md
tests_glob           = **/__tests__/**
integrate_tests_glob = e2e/**/*.e2e.ts
red_types            = AssertionError, NotImplemented, expect.*
```

| Key | Default | What it holds |
| --- | --- | --- |
| `version` | none, required | `1` |
| `check` | none, required, may be empty | the command that checks the whole tree before every commit |
| `check_integrate` | empty: nothing more runs | the slow but local tests (integration, end-to-end without external services), once per task before the final review and again after a sync with main |
| `run_tests` | empty: the red check is skipped | the command that runs the test files in `{files}` and prints JUnit XML |
| `run_integrate_tests` | empty: their red check is skipped | the same command for the test files of `integrate_tests_glob`, those `check` leaves out |
| `main` | `main` | the branch tasks start from and merge into |
| `integrate` | `merge` | how a task lands: a local `--no-ff` merge, the only mode so far |
| `rules` | `CLAUDE.md` | the project's rule files and folders, comma-separated; decision records go in a folder of them |
| `backlog` | `.workflow/backlog.md` | where the backlog items you approve go |
| `tests_glob` | the usual test file names of JavaScript, TypeScript, Python and Go | which files are tests: the suite records them, and `commit.sh` protects them |
| `integrate_tests_glob` | empty: none | which test files `check` leaves out, those `check_integrate` runs: the suite records and protects them too, and `run_integrate_tests` runs them |
| `red_types` | `AssertionError, NotImplemented` | the failure types the runners report for an assertion and for a stub |

A value never holds ` #`, which starts a comment. A key the version does not know is refused, and so is a config without `check`: a misspelt key would otherwise leave `check` empty, and every commit would pass unchecked. A config of another version is refused with what to change; there is no migration.

Any key can be overridden for one session by `OVERLOAD_<KEY>`, even to empty: a session that cannot reach the project's container sets `OVERLOAD_CHECK` and `OVERLOAD_RUN_TESTS`.

### `check`

`check` is the commit gate: `verify.sh` runs it before every commit, and `commit.sh` takes only a tree it found green. It is a local subset of what the CI runs, and it:

- exits 0 on green, anything else on red;
- ends on its own: no watch mode, no prompt;
- changes no file: `--check`, not `--fix`. `verify.sh` hashes the tree again after the run, and a run that changed a file git does not ignore is red, with the files it changed;
- runs locally, with no secrets or services;
- is fast enough to run before every commit, and gives the same result on the same tree;
- prints the cause of a red in its last lines, the ones `verify.sh` shows.

It checks the whole tree, never only what changed: on main at the first verify, and after main is taken into a branch, a scoped command would check nothing. Some examples:

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

### `check_integrate`

`check_integrate` runs the tests too slow for every commit but still local: integration, end-to-end with no external service. It follows `check`'s rules but speed. `verify.sh --integrate` runs it after a green `check`, once per task before the final review, and again after the task takes in a moved main; `integrate.sh` refuses a branch where it has not run green since main last moved. Tests that need services or secrets stay in the project's CI, out of both commands. Empty, nothing more runs.

### `run_tests` and `red_types`

`run_tests` runs the test files named in `{files}` and prints JUnit XML on stdout, inside the same container or wrapper as `check`: vitest `--reporter=junit --outputFile=/dev/stdout` (without it vitest 5 writes the report to a file), jest with `jest-junit` to stdout, pytest `--continue-on-collection-errors --junitxml=/dev/stdout` with its default traceback, go `gotestsum --junitfile /dev/stdout`. The red check runs it on a chunk's new suite, which must fail for the right reason; `verify.sh` runs it on every suite recorded on the branch, which must pass, so that a test `check` leaves out still runs at each later chunk. Without it, the red check is skipped and every task logs that, and verify runs `check` alone.

`run_integrate_tests` is the same command for the test files of `integrate_tests_glob`, those `check` leaves out and `check_integrate` runs, inside the same container or wrapper as `check_integrate`: Playwright `--reporter=line,junit`, whose `line` reporter prints the cause of a file that fails to load, which the JUnit report leaves out. A file both globs match counts as outside `check`. The glob names test files only, never their helpers (`e2e/**/*.e2e.ts`, not `e2e/**`): a helper the task changes would be recorded and handed to the runner, which reports no test for it. Playwright reads the paths it is given as regular expressions: a test file whose name holds `[`, `(` or `+` is not found. The suite records and protects those files too; the red check runs each recorded file through the command of its glob and judges both runs as one, and so does verify. With `run_integrate_tests` empty, their red check is skipped and verify says they did not run. `red_types` serves both runners: the setup measures each and writes the types of both.

`red_types` names the failure types the runner reports for a failed assertion and for a stub's not-implemented error (`NotImplementedError` in Python). A type ending in `*` matches every type it starts: Playwright names an assertion's type after its matcher (`expect.toBe`, `expect.toBeVisible`), so `expect.*`. `/overload:setup` measures it with throwaway tests; when it finds the measure unreliable it leaves `run_tests` empty and says why.

### Names, messages and hooks

Branch names and commit messages follow the project's rules (its CLAUDE.md, its contributing docs); where they state none, a branch `<type>/<description>` in kebab-case and a subject in the imperative of at most 72 characters. The project's git hooks have the last word: `branch.sh` runs the `commit-msg` hook on the merge's subject before the task starts (git 2.36 or later), and `commit.sh` undoes a commit whose tree a `pre-commit` hook changed after the check.

### Files in a project

| File | Lives | Holds |
| --- | --- | --- |
| `.workflow/config` | main | the project's settings |
| `.workflow/backlog.md` | main | the items you approved at a checkpoint |
| `.workflow/journal.md` | the task's branch | phase, intent, candidates, open findings; dropped at the merge |
| `.workflow/specs/` | main | the L specs: approved by a task, ticked chunk by chunk by their build, done at its merge, or dropped by a task with the reason |
| `.workflow/plans/` | main | the plans: approved and revised by a task, an item ticked by the task that ends it, or dropped by a task with the reason; one open at a time |
| `.workflow/inputs/<slug>/` | main | the documents given with a request, named as the spec or task that uses them |
| `.workflow/reference/` | the working tree, briefly | the test-author's throwaway model of a type-level case; deleted before its suite is recorded |
| `.git/overload/` | the clone | the verified tree, the output of the last verify and red check and the red check's report, and the files a task keeps for a later session (the explorer's map), in a folder per branch removed at its merge; which branch works an item of the plan, until its merge |
| `refs/overload/suite/<branch>/<n>` | the clone | the test-author's recorded suites, outside every branch; deleted at the merge |

## The workflow explained

```
/overload:task <request>
  └─ brainstorming ── triage: S, L or a plan, you confirm
       ├─ S: branch → implement → verify → commit
       │       → close: slow tests → final review → lessons → checkpoint → integrate
       ├─ L: branch → spec → probe → spec review → split → lessons → checkpoint
       │       → commit the approved spec → close: sync, check → integrate
       └─ plan: branch → plan and its decision records → plan review → lessons
               → checkpoint → commit the approved plan → close: sync, check → integrate
                                                    │ the plan on main
/overload:task <plan> <n>                           ▼
  └─ the item's brainstorming ── its tier, you confirm ── S or L, as above,
       one item at a time; the task that ends it ticks it
/overload:task <plan> <the change>, /overload:task <spec> <why>
  └─ revision: branch → the plan revised → plan review → lessons → checkpoint
     drop: branch → dropped, with the reason → lessons → checkpoint
       → commit → close: sync, check → integrate
                                                               │ the spec on main
/overload:build <spec>                                          ▼
  └─ branch → expiry check → per chunk: stubs → tests → red check → implement
                                        → verify → step review → commit
       → close: slow tests → final review → lessons → checkpoint → integrate
```

Every step is a phase recorded in the branch's journal, so a task survives an interruption, a `/clear` or a compaction: the command that opened it reads the journal and resumes where it stopped. Where a script's outcome decides the next step (a green verify, a valid red, a commit), the script moves the phase itself, and a red never moves it.

### Brainstorming and triage

The main agent restates the request (the problem, the goal, the constraints) and maps the code it touches through `code-explorer`, which returns a short map with `file:line`, kept with the task for the sessions to come; on a plainly small change it reads the files and their callers itself. It asks its questions in one message, then proposes a tier with a line of reasons. The documents you give with the request (a brief, a mockup, a sample format) are copied into `.workflow/inputs/<slug>/` when the branch opens and reach main with the task, so that a later session finds them; it tells you which, and one you leave out stays out. The spec translates them, and the spec reviewer checks that each of their points is covered or out of scope.

**S** when all of these hold:

- nothing a consumer sees changes (public API, observable behavior, defaults, error types, dependency ranges), or the change is docs, config or tooling only. A bug fix that brings the behavior back to what the docs say counts as no change; one that has to decide what the behavior should be is L;
- one package or area, within about 6–7 files or 10–15 test cases;
- no data migration, nothing on security;
- clear requirements, known code and dependencies.

**L** is everything else. `branch.sh` then opens the task's branch from an up-to-date main and writes the journal with the intent.

### The S path

No spec, one reviewer, one checkpoint; the journal's intent stands in for the spec and goes in the commit's body.

1. **Implement**: the main agent writes the change; a bug fix starts from a test that reproduces it and fails.
2. **Verify** with `verify.sh`; at the third red in a row it stops and the task escalates.
3. **Commit** with `commit.sh`, which refuses any tree but the verified one.
4. **Close**, below.

A task that turns out bigger goes to the L path on your go, and starts again from main: its code did not go through the L path's tests first, and the spec must come from the problem, not from a sketched solution. The main agent logs in the journal the facts the attempt found; `restart.sh` recreates the branch from main with that journal, as an L task at its spec, puts the uncommitted work in a stash, and prints what it discarded: the attempt's commits stay reachable in `git reflog <branch>`, but the journal names none of it.

### The L path: the spec

An L task ends with its spec approved on main; `/overload:build` builds it.

1. **Spec**, written by the main agent, which held the discussion: why, what, decisions with their alternatives, test cases, the docs that change with the behavior, chunks. What the build needs from the discussion, your decisions and rulings with your words, goes in the spec: the journal does not reach the build. Its frontmatter's `depends_on` names the files it rests on. A decision that outlives the task also gets a decision record.
2. **Probe** (`prober`), only for external facts the spec rests on (versions, APIs, a dependency's behavior), in a temporary folder outside the repository.
3. **Spec review** (`spec-reviewer`): correctness, and a critique of the premises: was the problem seen, what is the strongest alternative, what is missing. It gets the spec and the code map, never a summary of the discussion, and does not read the journal.
4. **Split** (`spec-splitter`), above about 6–7 files or 10–15 test cases: the fewest chunks, each green alone, each test-first, of tests only, or neither.
5. **Lessons and checkpoint**, the task's only checkpoint: you approve the spec and pick the lessons and backlog items to keep. A spec split into more than about 5 chunks is too large for one build: the checkpoint proposes to turn it into a plan, unless a plan is open, and for an item's spec into a revision of the plan that splits the item. On your go, `restart.sh --plan` keeps the spec's draft out of the tree, for the plan to start from, and the task goes on as a plan task.
6. **Merge**: the spec is committed as `status: approved`. A task of docs only (specs, plans, their inputs, rules files, the backlog) closes without `check_integrate` and without the final review, which the spec review and your approval stand for: it takes in a moved main, runs `check`, writes what you picked, and merges. It ends by naming `/overload:build <spec>`, best after a `/clear`: the build needs none of this session's context.

### A plan and its items

A change with several groups of independent decisions, or several areas a consumer sees, is too large for one spec: the triage proposes a plan, and one plan is open at a time. The main agent writes it in `.workflow/plans/`, with what fixes its decisions before any code (decision records, a glossary, a domain model):

- **Requirements**, by area, each with an ID that carries the area (`AUTH-01`) and how it is verified: a test, a test outside `check`, an acceptance step a person runs, a measure.
- **Cross-cutting decisions**, each with its alternatives and why, and where a cut cannot keep main green, how it does anyway: expand/contract, branch by abstraction, a feature flag.
- **Items** in order, each a task that leaves main green and coherent by itself, with its estimated tier, the requirements it covers, the one it closes when several items cover a requirement, and the items it depends on.
- **Acceptance**, the steps a person runs once every item is done, written now with the requirements; with a CI, a last step checks main is green after the push.

`plan.sh` checks its format: every requirement covered, closed and, when it needs one, tried by a step. `plan-reviewer` judges what a script cannot: whether each item leaves main green and coherent, the order, an item too large, a decision deferred that conditions every item, the decisions and documents against the plan. You approve it at the task's only checkpoint, and it merges like a spec, without the final review.

Then `/overload:task <plan> <n>` opens an item: its brainstorming starts from the item's intent and asks only what the plan leaves open, and the plan's estimate is the tier it proposes. An S item is a task like any other; an L item's spec names its plan and item, its reviewer reads the plan, and its build watches the plan for changes since the spec's approval. The task that ends an item, the S or the build, ticks it in the plan in its last commit, and refines the acceptance steps its change affects; what it finds that changes later items goes to its checkpoint as a revision, never into the plan by itself. `integrate.sh` refuses an item's task that changes another item, or leaves its own unticked.

### Changing a plan or a spec on main

A plan or a spec on main is a decision, and changes only through a task with its own checkpoint. `/overload:task <plan> <the change>` revises the open plan or drops it; `/overload:task <spec> <why>` drops a spec approved and not built (a spec changes otherwise in its build, as a correction, or is dropped and written anew).

- **A revision** goes through the plan's steps, its reviewer judging the revision against the rest of the plan and what the ticked items built. It changes only items not ticked and not open on a branch, which keep their numbers; a new item, a split item's new part included, takes the next free number. An item it removes takes its approved spec to `dropped` in the same task; one it changes keeps it, and its build reviews it against the revised plan first, or drops it, as you choose.
- **A drop** sets `status: dropped`, with the reason under `## Dropped`, and marks the decision records it cites as withdrawn or superseded, as the project's convention says. A plan dropped drops the approved specs of its items with it; what its ticked items built stays. A drop waits while an item of the plan is open on a branch. A spec dropped reopens its item, when it has one.

`integrate.sh` checks each of these: a revision that changes a ticked item or one a branch works, or ticks one; a drop without its reason, or that changes the plan's items; an approved spec left behind for an item removed or dropped; any other spec or plan changed.

### The L path: the build

`/overload:build <spec>` opens a branch from main for a spec approved there with a chunk left to build. Its journal points to the spec, which holds the intent.

**Expiry.** The spec was judged on the code as it was at its approval, the merge that brought it to main. When main changed since then a file of its `depends_on`, of the config's `rules`, or the config, the build starts with a new review: `code-explorer` maps the change, and `spec-reviewer` judges whether the spec still holds; a correction it calls for goes through you. When main moved elsewhere, you are told, with the dependencies the spec names in words, which no script sees change.

Then each chunk ends in one green commit, written by agents that did not write the spec.

1. **Stubs** (`step-implementer` in stub mode), when the chunk changes existing signatures or adds dependencies.
2. **Tests** (`step-test-author`), from the spec, never reading the code under change; it records its suite with `suite.sh`, outside every branch.
3. **Red check** (`red-check.sh`): every new test must fail on an assertion or a stub's not-implemented error, never on an import or load error, read from the runner's JUnit XML. It prints a summary, the problems and the reds grouped by type and message, and leaves its line per test in a report under `.git/overload/`. A new test that passes already goes to the step reviewer, who checks it fails under a mutant.
4. **Implement** (`step-implementer`) until the tests pass. It cannot touch the recorded tests: `commit.sh` refuses. A test it thinks wrong goes to the main agent, who decides on the spec, or asks you when the spec is silent.
5. **Verify**, `check` and every suite recorded on the branch, then the **step review** (`step-reviewer`): the code does what the chunk asks, and the tests cover it.
6. **Commit** the chunk, its tests, its code and its tick in the spec.

A spec found wrong halfway stops the chunk: any change to it but a tick (a chunk's type, a ruling on a case it left open, a chunk added at the checkpoint) is a correction, reviewed by `spec-reviewer` on its diff, and waits for your go. A spec whose premise is gone goes back to `/overload:task`.

### Close

Every task ends the same way: an S, the spec task of an L, a plan task, a change of a plan or spec, a build. A task that decides on main (a spec, a plan, a change) of docs only runs steps 1, 5 and 6 alone, with `check` and no `check_integrate`: its lessons went to its checkpoint. In a build, `step-implementer` writes the fixes, each from a test that reproduces it; elsewhere the main agent does.

1. **Sync and integration check**: when main moved, `sync.sh` merges it into the branch without committing; `verify.sh --integrate` then runs `check` and `check_integrate`, the slow local tests. A red is fixed on the branch like any other, and the merge is committed with its fixes; a red that main shows alone, or a conflict, comes to you.
2. **Final review** (`code-reviewer`) of the whole range against the intent or the spec. Only six cases block: a bug a plausible caller meets, a security defect, a requirement missed or out of scope, a missing or vacuous test, a broken convention no tool checks, a misleading doc. Findings below confidence 80 are counted, not reported. Fixes are commits of their own, and a new round reviews only what changed.
3. **Lessons** (`lesson-critic`): rules proposed only for problems that got past the step meant to catch them, judged against the rules they would join before you see them.
4. **Checkpoint**: a summary of the change, the last verify, the findings that need your judgment, the backlog candidates and the lessons. You give the go and pick what to keep, or ask for changes.
5. **Lessons and backlog**: the ones you picked are written and committed on their own; a build sets its spec's `status: done`, and the task that ends an item ticks it.
6. **Integrate** (`integrate.sh`): brings main up to its upstream, refuses a branch that does not hold it (back to the sync) or where `check_integrate` has not run since, checks the spec is as its command leaves it (approved with a chunk to build after a task, done with every chunk ticked after a build) and the plan as its task leaves it (approved with nothing ticked; for an item, only its own line changed, ticked once the item ends), and a change as the section above says, merges with `--no-ff` without the journal, and deletes the branch and its suite.

### Escalation

A loop that reaches its third round without converging, a stuck step, a finding that needs judgment, or a conflict when taking in main stops and comes to you, with what was tried and three choices: **retry** one more round, **skip** and record the problem (never on a red verify), or **stop**, leaving the branch and its journal for a later session of the command that opened it.

### The agents

All are internal to the skills and called as `overload:<name>`.

| Agent | Model | Role |
| --- | --- | --- |
| `setup-explorer` | sonnet | reads a project and proposes its config; read-only |
| `setup-red-probe` | sonnet | measures `red_types` with throwaway tests |
| `code-explorer` | sonnet | maps the code a request touches and saves the map; changes nothing in the repository |
| `prober` | sonnet | checks external facts in a throwaway environment |
| `spec-reviewer` | opus | reviews an L spec and challenges its premises, and in a build an expired spec or a correction; read-only |
| `plan-reviewer` | opus | reviews a plan's cut into items, its cross-cutting decisions and its documents; read-only |
| `spec-splitter` | sonnet | splits a spec into the fewest green chunks; read-only |
| `step-test-author` | opus | writes a chunk's tests from the spec, before the code |
| `step-implementer` | sonnet | writes a chunk's code until its tests pass |
| `step-reviewer` | opus | reviews a chunk's code and tests; read-only |
| `code-reviewer` | opus | reviews the task's diff against its intent or spec; read-only |
| `lesson-critic` | opus | judges proposed lessons from their evidence; read-only |

## Contributing

Workflow Overload is maintained by one person and integrates by local merge, without pull requests: open an issue to report a bug or discuss a change before working on it. [CLAUDE.md](CLAUDE.md) holds the full rules; the essentials follow.

### Layout

```
.claude-plugin/marketplace.json   the marketplace: one plugin, ./plugins/overload
plugins/overload/                 what an install copies
  .claude-plugin/plugin.json      name, version
  skills/task/SKILL.md            /overload:task, opens or resumes a task: an S, or an L's spec
  skills/task/phases/             the task skill's own phases, one file each
  skills/build/SKILL.md           /overload:build, builds a spec approved on main
  skills/build/phases/            the build skill's own phases
  skills/setup/SKILL.md           /overload:setup, writes .workflow/config
  shared/                         the rules and phases every task command shares
  agents/                         the agents, all internal to the skills
  hooks/hooks.json                hooks, silent without a journal
  scripts/                        bash for the steps, python3 for parsing
tests/                            tests of the scripts, outside the install
docs/                             design and probes
```

### Rules of the plugin

- **Only the human starts the workflow.** Every skill has `disable-model-invocation`, only `/overload:task` opens a task from a request and `/overload:build` only from a spec approved on main, no agent's description invites delegation, no hook that acts on a branch without `.workflow/journal.md`.
- **Scripts need only bash, git and python3** (3.8+, standard library), and find their files from `BASH_SOURCE`, since the model's Bash has no `CLAUDE_PLUGIN_ROOT`.
- **A new config key** goes in `lib.sh`'s `CONFIG_KEYS` with its default in `config_default`, in the key list of `agents/setup-explorer.md`, and in this README's *Configuration*; a test refuses a phase or an agent that names a key `lib.sh` does not know.
- **Phases and agents are instructions to a model**: imperative, short, one place per rule.

### Checks

```
shellcheck -x plugins/overload/scripts/*.sh tests/*.sh
tests/run.sh
python3 -m unittest discover -s tests
claude plugin validate .
```

CI runs them on every push. A change to a script starts with a test in `tests/scripts.test.sh` that fails without it.

### Branches, commits and releases

- Branch: `<type>/<scope>/<description>`, types `feature`, `fix`, `refactor`, `test`, `docs`, `chore`; scope `scripts`, `skill`, `agents`, `hooks` or `repo`.
- Commit: `[<scope>] <type>: <summary>`, the type one of `feat`, `fix`, `refactor`, `perf`, `test`, `docs`, `build`, `ci`, `chore`; summary imperative, lowercase, no trailing period, at most 72 characters in all; a body when the why is not obvious.
- A release bumps `version` in `plugins/overload/.claude-plugin/plugin.json`; a change that breaks existing configs bumps the minor version.

## Roadmap

Setup, of a new repository too, brainstorming, triage, the S path, the L path as a spec task and its build, a plan worked item by item, revised or dropped, a spec dropped, resume and integration by local merge all work today. Next, each to be designed before it is built (details in [the backlog](.workflow/backlog.md)):

- **Integration by pull or merge request** on GitHub, GitLab and Bitbucket, for projects whose main branch takes no local merge.
- **A level above the plan**, a roadmap of phases, each a plan, for building a whole application.

## License

[MIT](LICENSE)
