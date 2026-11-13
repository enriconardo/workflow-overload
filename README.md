# Workflow Overload

A development workflow for [Claude Code](https://claude.com/claude-code), packaged as the plugin `workflow-overload`. It takes a request to a verified merge, spends agents and checks in proportion to the task, and starts only when you type `/overload`.

> **Status: 0.4.1.** Setup, brainstorming, triage, the S path, the L path, resume and integration by local merge all work. Not yet: integration by pull request, starting a project with no code, and a plan above the single task (see [the backlog](.workflow/backlog.md)).

## What this is and why it exists

An agent left alone on a change writes the code, writes the tests that confirm it, reviews its own work and commits whatever it last saw pass. Each of those steps hides the defects of the one before: tests written after the code confirm what it does today, bugs included; a review by the author sees what the author meant, not what they wrote; a long session carries its drift toward the human's first idea into every later step.

Workflow Overload splits those roles. The main agent holds the intent and talks with you; agents with a clean context explore, write tests from the spec without reading the code under change, implement, and review; scripts do every mechanical check, so a commit takes only the tree a green check just saw. A small change goes through a short path (S) with one review; anything that a consumer sees, or that spans areas, goes through a long one (L) with a reviewed spec, chunks written test-first, and a review per chunk. You decide the tier, the result and what the task leaves behind.

It is a plugin with a single entry point: without `/overload`, a session works as it would without it.

### Principles

- **Who writes does not judge.** Code, specs and tests are reviewed by agents with a clean context, which report and never fix.
- **The main agent holds the intent and stays light.** Exploring, probing, implementing an L chunk and reviewing go to agents, which return only their result. On a plainly small change it reads the files it changes itself, since it would read them anyway.
- **Mechanical checks are scripts.** Verify is green or red, a commit takes only the tree verify just checked, and a test-first suite must fail for the right reason before any code is written.
- **The human decides where it matters**: the tier, the result, the lessons and backlog items to keep, and every loop that does not converge in three rounds.
- **The workflow starts only with `/overload`.** The model cannot invoke the skill, the agents declare themselves internal, and the hooks stay silent on a branch without a task.
- **The project keeps its own conventions.** Its commands, branch names and commit messages live in its config and rule files; the plugin owns only when a check runs and the process around it.

## Quick start

You need Claude Code, `bash`, `git` and `python3` (3.8 or later, standard library only), and a git project whose checks pass on its main branch. With git older than 2.36, a task's merge subject is not checked against the project's `commit-msg` hook before the task starts.

1. **Install** the plugin, from Claude Code:

   ```
   /plugin marketplace add enriconardo/workflow-overload
   /plugin install workflow-overload@workflow-overload
   ```

2. **Set up the project.** On its main branch, with a clean tree:

   ```
   /overload setup
   ```

   An agent reads the project and proposes `.workflow/config`, each value with its source, plus the conventions your rule files lack. Answer its questions, accept or change the values; it then runs your `check` on main, which must be green, measures how your test runner reports a failure, and commits the config on your go. Guidance helps when the project is unusual: `/overload setup take the commands from the Makefile`.

3. **Run a first task**, something small:

   ```
   /overload fix the typo in the install section of the README
   ```

   It restates the request, asks what is unclear, and proposes S. On your confirmation it opens a branch, makes the change, verifies, commits, runs the final review, and stops at a checkpoint with a summary. Give the go: it merges into main with `--no-ff` and deletes the branch.

That is the whole loop. A larger request goes the same way, through the L path. If a session ends halfway, `/overload` on the task's branch resumes it from its journal.

## Configuration and usage

### Commands

| Command | What it does |
| --- | --- |
| `/overload setup [guidance]` | Proposes `.workflow/config` and the conventions your rule files lack; you settle it. Then verify must be green on main, a second agent measures `red_types` with throwaway tests, and it commits on your go. No branch, no journal. |
| `/overload <request>` | Opens a task: brainstorming, then the S or the L path. |
| `/overload` | Resumes the task of the current branch from its journal, after an interruption or a `/clear`. |

Inside a task, the scripts that open the branch, update the journal, verify, commit and handle the suite run without a permission prompt; `integrate.sh` asks each time, on top of your go at the checkpoint. While a task is open, a hook refuses a `git commit` or `git merge` typed directly. On a branch with an open task, a new session is told the task waits for `/overload`, and a compacted one is told to reread the journal.

### `.workflow/config`

The config holds what is the project's own, as `key = value` lines that scripts read without executing; `/overload setup` writes it.

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
| `rules` | `CLAUDE.md` | the project's rule files and folders, comma-separated; decision records go in a folder of them |
| `backlog` | `.workflow/backlog.md` | where the backlog items you approve go |
| `tests_glob` | the usual test file names of JavaScript, TypeScript, Python and Go | which files are tests: the suite records them, and `commit.sh` protects them |
| `red_types` | `AssertionError, NotImplemented` | the failure types the runner reports for an assertion and for a stub |

A value never holds ` #`, which starts a comment. A key the version does not know is refused, and so is a config without `check`: a misspelt key would otherwise leave `check` empty, and every commit would pass unchecked. A config of another version is refused with what to change; there is no migration.

Any key can be overridden for one session by `OVERLOAD_<KEY>`, even to empty: a session that cannot reach the project's container sets `OVERLOAD_CHECK` and `OVERLOAD_RUN_TESTS`.

### `check`

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

### `run_tests` and `red_types`

`run_tests` runs the test files named in `{files}` and prints JUnit XML on stdout, inside the same container or wrapper as `check`: vitest `--reporter=junit`, jest with `jest-junit` to stdout, pytest `--continue-on-collection-errors --junitxml=/dev/stdout` with its default traceback, go `gotestsum --junitfile /dev/stdout`. Without it, the red check is skipped and every task logs that.

`red_types` names the failure types the runner reports for a failed assertion and for a stub's not-implemented error (`NotImplementedError` in Python). `/overload setup` measures it with throwaway tests; when it finds the measure unreliable it leaves `run_tests` empty and says why.

### Names, messages and hooks

Branch names and commit messages follow the project's rules (its CLAUDE.md, its contributing docs); where they state none, a branch `<type>/<description>` in kebab-case and a subject in the imperative of at most 72 characters. The project's git hooks have the last word: `branch.sh` runs the `commit-msg` hook on the merge's subject before the task starts (git 2.36 or later), and `commit.sh` undoes a commit whose tree a `pre-commit` hook changed after the check.

### Files in a project

| File | Lives | Holds |
| --- | --- | --- |
| `.workflow/config` | main | the project's settings |
| `.workflow/backlog.md` | main | the items you approved at a checkpoint |
| `.workflow/metrics.jsonl` | main | one line per integrated task: rounds, verify runs, commits, files, tokens per role |
| `.workflow/journal.md` | the task's branch | phase, intent, candidates, open findings; dropped at the merge |
| `.workflow/specs/` | main | the L specs, ticked chunk by chunk |
| `.workflow/reference/` | the working tree, briefly | the test-author's throwaway model of a type-level case; deleted before its suite is recorded |
| `.git/overload/` | the clone | the verified tree and the log of verify runs and red checks |
| `refs/overload/suite/<branch>/<n>` | the clone | the test-author's recorded suites, outside every branch; deleted at the merge |

### Measures

Each integrated task adds a line to `.workflow/metrics.jsonl`. `plugins/workflow-overload/scripts/metrics.py` also reads the Claude Code transcripts of a project and the merges of its history, to compare a workflow with the one before it:

```
metrics.py transcripts --repo ~/code/project > t.jsonl
metrics.py git --repo ~/code/project > g.jsonl
metrics.py summary t.jsonl g.jsonl
```

Claude Code deletes transcripts after 30 days: set `"cleanupPeriodDays"` in `~/.claude/settings.json` to keep them.

## The workflow explained

```
/overload <request>
  └─ brainstorming ── triage: S or L, you confirm
       ├─ S: branch → implement → verify → commit ─────────────────────────┐
       └─ L: branch → spec → probe → spec review → split → checkpoint 1    │
              └─ per chunk: stubs → tests → red check → implement          │
                            → verify → step review → commit ───────────────┤
                                                                           ▼
                  close: final review → lessons → checkpoint → integrate
```

Every step is a phase recorded in the branch's journal, so a task survives an interruption, a `/clear` or a compaction: `/overload` reads the journal and resumes where it stopped.

### Brainstorming and triage

The main agent restates the request (the problem, the goal, the constraints) and maps the code it touches through `code-explorer`, which returns a short map with `file:line`; on a plainly small change it reads the files and their callers itself. It asks its questions in one message, then proposes a tier with a line of reasons.

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

A task that turns out bigger goes to the L path on your go: its commits stay, uncommitted work goes in a stash, and the spec describes the whole change, its chunks only what is left.

### The L path: planning

1. **Spec**, written by the main agent, which held the discussion: why, what, decisions with their alternatives, test cases, chunks. A decision that outlives the task also gets a decision record.
2. **Probe** (`prober`), only for external facts the spec rests on (versions, APIs, a dependency's behavior), in a temporary folder outside the repository.
3. **Spec review** (`spec-reviewer`): correctness, and a critique of the premises: was the problem seen, what is the strongest alternative, what is missing. It gets the spec and the code map, never a summary of the discussion.
4. **Split** (`spec-splitter`), above about 6–7 files or 10–15 test cases: the fewest chunks, each green alone, each test-first or not.
5. **Checkpoint 1**: you approve the plan, and the spec is committed. This is the moment for `/clear` and `/overload`: the next session resumes from the journal and the spec with a small context.

### The L path: chunks

Each chunk ends in one green commit, written by agents that did not write the spec.

1. **Stubs** (`step-implementer` in stub mode), when the chunk changes existing signatures or adds dependencies.
2. **Tests** (`step-test-author`), from the spec, never reading the code under change; it records its suite with `suite.sh`, outside every branch.
3. **Red check** (`red-check.sh`): every new test must fail on an assertion or a stub's not-implemented error, never on an import or load error, read from the runner's JUnit XML. A new test that passes already goes to the step reviewer, who checks it fails under a mutant.
4. **Implement** (`step-implementer`) until the tests pass. It cannot touch the recorded tests: `commit.sh` refuses. A test it thinks wrong goes to the main agent, who decides on the spec, or asks you when the spec is silent.
5. **Verify**, then the **step review** (`step-reviewer`): the code does what the chunk asks, and the tests cover it.
6. **Commit** the chunk, its tests, its code and its tick in the spec.

### Close

Both paths end the same way.

1. **Final review** (`code-reviewer`) of the whole range against the intent or the spec. Only six cases block: a bug a plausible caller meets, a security defect, a requirement missed or out of scope, a missing or vacuous test, a broken convention no tool checks, a misleading doc. Findings below confidence 80 are counted, not reported. Fixes are commits of their own, and a new round reviews only what changed.
2. **Lessons** (`lesson-critic`): rules proposed only for problems that got past the step meant to catch them, judged against the rules they would join before you see them.
3. **Checkpoint**: a summary of the change, the last verify, the findings that need your judgment, the backlog candidates and the lessons. You give the go and pick what to keep, or ask for changes.
4. **Integrate** (`integrate.sh`): merges with `--no-ff` without the journal, adds a line of measures, re-verifies the merge's result when main moved, deletes the branch and its suite, and leaves main untouched on a conflict or a red verify.

### Escalation

A loop that reaches its third round without converging, a stuck step, a finding that needs judgment, or a conflict at integration stops and comes to you, with what was tried and three choices: **retry** one more round, **skip** and record the problem (never on a red verify), or **stop**, leaving the branch and its journal for a later `/overload`.

### The agents

All are internal to `/overload` and called as `workflow-overload:<name>`.

| Agent | Model | Role |
| --- | --- | --- |
| `setup-explorer` | sonnet | reads a project and proposes its config; read-only |
| `setup-red-probe` | sonnet | measures `red_types` with throwaway tests |
| `code-explorer` | sonnet | maps the code a request touches; read-only |
| `prober` | sonnet | checks external facts in a throwaway environment |
| `spec-reviewer` | opus | reviews an L spec and challenges its premises; read-only |
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
.claude-plugin/marketplace.json   the marketplace: one plugin, ./plugins/workflow-overload
plugins/workflow-overload/        what an install copies
  .claude-plugin/plugin.json      name, version
  skills/overload/SKILL.md        the only entry: /overload
  skills/overload/phases/         one file per phase, read by the entry skill
  agents/                         the agents, all internal to /overload
  hooks/hooks.json                hooks, silent without a journal
  scripts/                        bash for the steps, python3 for parsing
tests/                            tests of the scripts, outside the install
docs/                             design and probes
```

### Rules of the plugin

- **One entry point.** No second skill, no agent whose description invites delegation, no hook that acts on a branch without `.workflow/journal.md`.
- **Scripts need only bash, git and python3** (3.8+, standard library), and find their files from `BASH_SOURCE`, since the model's Bash has no `CLAUDE_PLUGIN_ROOT`.
- **A new config key** goes in `lib.sh`'s `CONFIG_KEYS` with its default in `config_default`, in the key list of `agents/setup-explorer.md`, and in this README's *Configuration*; a test refuses a phase or an agent that names a key `lib.sh` does not know.
- **Phases and agents are instructions to a model**: imperative, short, one place per rule.

### Checks

```
shellcheck -x plugins/workflow-overload/scripts/*.sh tests/*.sh
tests/run.sh
python3 -m unittest discover -s tests
claude plugin validate .
```

CI runs them on every push. A change to a script starts with a test in `tests/scripts.test.sh` that fails without it.

### Branches, commits and releases

- Branch: `<type>/<scope>/<description>`, types `feature`, `fix`, `refactor`, `test`, `docs`, `chore`; scope `scripts`, `skill`, `agents`, `hooks`, `metrics` or `repo`.
- Commit: `[<scope>] <type>: <summary>`, the type one of `feat`, `fix`, `refactor`, `perf`, `test`, `docs`, `build`, `ci`, `chore`; summary imperative, lowercase, no trailing period, at most 72 characters in all; a body when the why is not obvious.
- A release bumps `version` in `plugins/workflow-overload/.claude-plugin/plugin.json`; a change that breaks existing configs bumps the minor version.

## License

[MIT](LICENSE)
