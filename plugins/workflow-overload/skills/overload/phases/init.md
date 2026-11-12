# Init

Creates `.workflow/config`, the only place where this project differs from any other. Run on the main branch, with a clean tree. A short procedure, not a task: no branch, no journal, no review.

Text after `init` is the human's guidance (where to find the commands, what to leave out): it wins over what this file says to look for.

## 1. Read the project

Without changing anything, find:

- the main branch (`git symbolic-ref refs/remotes/origin/HEAD`, else `main` or `master`);
- how its checks run: lockfile and scripts (`package.json`, `Makefile`, `pyproject.toml`, `justfile`…), the CI's workflow files, a container or wrapper its commands run in (`./dev.sh exec`, `docker compose exec …`);
- the single command that checks the whole tree before every commit, a local subset of the CI: lint, typecheck, tests. It exits 0 on green and anything else on red, ends on its own (no watch mode, no prompt), changes no file (`--check`, not `--fix`), needs no secrets or services, and is fast enough for every commit. A container or wrapper goes inside it (`docker compose exec -T app make check`). If the project has no checks at all, `check` stays empty: verify then checks nothing and records the tree, and the run log says so;
- whether it integrates by local merge or by pull request, and where its rules live (CLAUDE.md files, ADR folders), its backlog if it keeps one.

## 2. Propose

Show the human the file you would write, filled in, and ask only for what you could not find out. The keys:

```
version    = 2
check      = <command>             # the commit gate: checks the whole tree, exit 0 green; empty: nothing checked
run_tests  = <command> {files}     # runs the given test files and prints JUnit XML on stdout; empty: no red check
main       = main
integrate  = merge                 # this version merges locally, --no-ff
rules      = CLAUDE.md             # comma-separated: the files and folders of the project's rules
backlog    = .workflow/backlog.md
tests_glob = **/__tests__/**, **/*.test.*   # what the test-author's suite records
red_types  = AssertionError, NotImplemented # the failure types the runner gives an assertion and a stub
```

`check` is always written, empty for a project with no checks: a config without it is refused, as is a key not in this list.

For `red_types`, the name the runner gives a failed assertion, and the one it gives a stub's error. A stub only throws the language's not-implemented error: in Python `raise NotImplementedError`, so `red_types = AssertionError, NotImplementedError`; in TypeScript and JavaScript `throw Object.assign(new Error('not implemented'), { name: 'NotImplemented' })`, which the default names.

For `run_tests`, the runner's JUnit reporter on stdout: vitest `--reporter=junit`, jest with `jest-junit` to stdout, pytest `--continue-on-collection-errors --junitxml=/dev/stdout` with its default traceback (no `--tb`: the failure's type is on the traceback's last line), go `gotestsum --junitfile /dev/stdout`. The red check reads the XML from the output, so other lines around it do no harm.

A value never holds ` #`, which starts a comment. Any key can be overridden for one session by an environment variable, `OVERLOAD_<KEY>`, even to empty: a session that cannot reach the project's container sets `OVERLOAD_CHECK` and `OVERLOAD_RUN_TESTS` to commands that run without it.

## 3. Test

Write the file, and an empty backlog file if the project keeps none, then run `bash <scripts>/verify.sh` on the main branch. It must be green: a red main makes every task red. If it is red or the command is wrong, fix the config with the human and run it again. Remove nothing the project already had.

Then, if the project will run L tasks and `run_tests` is set, test the red check: in a temporary folder of tests, one test that fails on an assertion, one that calls a stub (a function that only throws the not-implemented error above), and one that imports a module that does not exist, run through `run_tests`, and `python3 <scripts>/junit.py --types "<red_types>" <output-file> <the three files>`. The first must read `red, AssertionError`, the second `red, ` and a type of `red_types`, the third `LOAD ERROR`. If not, the runner's report needs another `run_tests` or `red_types`. With no way to tell them apart, leave `run_tests` empty and tell the human: the red check is then skipped, and logged as such. Delete the folder.

## 4. Commit

Show the human the final file and what the tests gave, in a few lines. On their go, commit the config and the backlog file on the main branch, in one commit whose subject follows *Names and messages* in the skill's rules (`chore: adopt workflow overload`, or the project's equivalent). Nothing else goes in it.
