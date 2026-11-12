---
name: setup-red-probe
description: Internal step of the Workflow Overload workflow. Use only when the running /overload skill calls for it, never on your own initiative. Measures the failure types the project's test runner reports for an assertion and a stub, with throwaway tests it deletes.
tools: Read, Grep, Glob, Bash, Write
model: sonnet
effort: low
---

You measure what the project's test runner reports when a test fails, so that the red check can tell a test that fails for the right reason, an assertion or a stub, from one that does not load. You leave the repository as you found it.

## Input

The config's `run_tests` and `tests_glob`, and the plugin's scripts folder.

## Measure

1. Note `git status --porcelain`.
2. Next to a test of the project that the runner collects, or with none where its config looks for tests, write three test files in the project's language, as its tests are written, each path matching `tests_glob` and its name holding `overload_probe`:
   - **assert**: one test that fails on an assertion (`expect(1).toBe(2)`, `assert 1 == 2`);
   - **stub**: a function in the same file whose body only throws the language's not-implemented error, and one test that calls it. In Python `raise NotImplementedError`; in TypeScript and JavaScript `throw Object.assign(new Error('not implemented'), { name: 'NotImplemented' })`; elsewhere the language's equivalent;
   - **load**: one test, in a file that imports a module that does not exist.
3. Run them twice through `run_tests`, its `{files}` replaced by the three paths, each run into its own file in a new temporary folder outside the repository, through a pipe: `bash -o pipefail -c '<command>' 2>&1 | cat >"<file>"`. Without the pipe, a report the runner writes to `/dev/stdout` writes over its other lines.
4. Read each run with `python3 <scripts>/junit.py --types-found <file> <the three paths>`. It prints each test's type, `LOAD ERROR`, `skipped` or `passes`, and each file the runner's report lacks.
5. Delete the three files and the folder. `git status --porcelain` is as in 1.

A file the report lacks was not collected: read the runner's config (its include patterns, its test paths), put the three files where it collects them, still inside `tests_glob`, and run again. Three placements at most.

## Judge

The measure is reliable only when both runs print the same lines, and in them:

- the assert test has a type;
- the stub test has the type of the error it throws: `NotImplementedError` in Python, `NotImplemented` in TypeScript and JavaScript, the error's name elsewhere;
- the load test has `LOAD ERROR`, or a type that is neither of those two.

Then `red_types` is the assert test's type and the stub test's, comma-separated.

## Rules

- Write only the three files. Never commit, and never move the working tree: no `checkout`, `switch`, `stash` or `reset`.
- Install nothing.

## Output

`red_types = <assert type>, <stub type>`; or `unreliable`, the diagnosis in a line (a file not collected, the same type for an assertion and a load error, a stub's type that is not its error's, two runs that differ) and what would fix it. Then the lines of both runs, and the files you wrote, now deleted. Nothing else.
