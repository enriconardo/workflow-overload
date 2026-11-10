# Init

Creates `.workflow/config`, the only place where this project differs from any other. Run on the main branch, with a clean tree. A short procedure, not a task: no branch, no journal, no review.

Text after `init` is the human's guidance (where to find the commands, what to leave out): it wins over what this file says to look for.

## 1. Read the project

Without changing anything, find:

- the main branch (`git symbolic-ref refs/remotes/origin/HEAD`, else `main` or `master`);
- how its checks run: lockfile and scripts (`package.json`, `Makefile`, `pyproject.toml`, `justfile`…), the CI's workflow files, a container wrapper for commands that touch dependencies (`./dev.sh exec`, `docker compose exec …`);
- the single command that runs lint, typecheck and tests on what changed, and its dependents. If there is none, the one that runs everything. If the project has no checks at all, `verify` stays empty: verify then checks nothing and records the tree, and the run log says so;
- branch and commit conventions: the project's CLAUDE.md and contributing docs, then `git log --format=%s -50` and the merged branches' names; a limit on a subject's length, if a `commit-msg` hook or the rules set one;
- whether it integrates by local merge or by pull request, and where its rules live (CLAUDE.md files, ADR folders), its backlog if it keeps one.

## 2. Propose

Show the human the file you would write, filled in, and ask only for what you could not find out. The keys:

```
version      = 1
exec         =                      # prefix of commands that touch dependencies; empty: run here
verify       = <command>            # green or red: lint, typecheck, tests of what changed and dependents; empty: nothing checked
main         = main
branch       = <type>/<scope>/<description>
types        = feature, fix, hotfix, refactor, test, docs, chore     # branch types
commit       = <type>(<scope>): <summary>                            # subject format
commit_types = feat, fix, refactor, perf, test, docs, build, ci, chore
subject_max  =                      # the project's own limit on a subject, as its commit-msg hook or rules set it; empty: none
integrate    = merge                # this version merges locally, --no-ff
rules        = CLAUDE.md            # comma-separated: the files and folders of the project's rules
backlog      = .workflow/backlog.md
specs        = .workflow/specs      # where L specs go
test_files   = <command> {files}    # runs the given test files and prints JUnit XML on stdout; empty: no red check
tests_glob   = **/__tests__/**, **/*.test.*   # what the test-author's suite records
red_types    = AssertionError, NotImplemented # failure types that make a valid red
reference    = .workflow/reference  # the test-author's throwaway reference model
probe_env    = <command>            # a throwaway environment for the prober, e.g. docker run --rm <image>
```

For `test_files`, the runner's JUnit reporter on stdout: vitest `--reporter=junit`, jest with `jest-junit` to stdout, pytest `--junitxml=/dev/stdout`, go `gotestsum --junitfile /dev/stdout`. The red check reads the XML from the output, so other lines around it do no harm.

A value never holds ` #`, which starts a comment. Any key can be overridden for one session by an environment variable, `OVERLOAD_<KEY>`, even to empty: a cloud session without Docker runs with `OVERLOAD_EXEC=`.

## 3. Test

Write the file, and an empty backlog file if the project keeps none, then run `bash <scripts>/verify.sh` on the main branch. It must be green: a red main makes every task red. If it is red or the command is wrong, fix the config with the human and run it again. Remove nothing the project already had.

Then, if the project will run L tasks and `test_files` is set, test the red check: in a temporary folder of tests, one test that fails on an assertion and one that imports a module that does not exist, run through `test_files`, and `python3 <scripts>/junit.py <output-file> <the two files>`. The first must read `red, AssertionError`, the second `LOAD ERROR`. If not, the runner's report needs another `test_files` or `red_types`. With no way to tell them apart, leave `test_files` empty and tell the human: the red check is then skipped, and logged as such. Delete the folder.

## 4. Commit

Show the human the final file and what the tests gave, in a few lines. On their go, commit the config and the backlog file on the main branch, in one commit whose subject follows the config's `commit` format (`chore(<scope>): adopt workflow overload`, or the project's equivalent). Nothing else goes in it.
