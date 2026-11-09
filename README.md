# Workflow Overload

A development workflow for [Claude Code](https://claude.com/claude-code), packaged as the plugin `workflow-overload`. It takes a request to a verified merge, spends agents and checks in proportion to the task, and starts only when you type `/overload`.

> **Status: 0.1, the S path.** Brainstorming, triage, the S path, its review, lessons, checkpoint and integration work. The L path (spec, spec review, chunks written test-first by a test author that never reads the code) is next: until then an L task stops at the triage.

## Principles

- **Who writes does not judge.** Code, and later specs and tests, are reviewed by agents with a clean context, which report and never fix.
- **The main agent holds the intent and stays light.** Exploring and reviewing go to agents, which return only their result.
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
| `/overload init` | Reads the project, proposes `.workflow/config`, tests it (verify green on main) and commits it through a first S task. |
| `/overload <request>` | Opens a task: brainstorming, then the S path. |
| `/overload` | Resumes the task of the current branch from its journal, after an interruption or a `/clear`. |

Without `/overload`, a session works as it would without the plugin: the entry skill cannot be invoked by the model, the agents declare themselves internal, and the hooks stay silent on a branch without a journal.

## The S path

For changes nothing outside sees (or docs, config, tooling), in one area, with clear requirements:

1. **Brainstorming**: restate the request, map the code (`code-explorer`), ask, propose S or L; you confirm.
2. **Branch**: `branch.sh` opens it from an up-to-date main and writes the journal.
3. **Implement, verify, commit**: a bug fix starts from a failing test; `commit.sh` refuses any tree but the verified one.
4. **Final review** (`code-reviewer`): six blocking cases, findings at confidence 80 or more; fixes are commits of their own, and a new round reviews only what changed.
5. **Lessons** (`lesson-critic`): rules proposed for problems that could recur, judged before you see them.
6. **Checkpoint**: you give the go and pick the lessons and backlog items to keep.
7. **Integrate**: `integrate.sh` merges with `--no-ff` without the journal, adds a line of measures to `.workflow/metrics.jsonl`, re-verifies the merge's result when main moved, and leaves main untouched on a conflict or a red verify.

## Configuration

`.workflow/config` holds everything project-specific, as `key = value` lines that scripts read without executing:

```
version      = 1
exec         = ./dev.sh exec        # prefix of commands that touch dependencies
verify       = pnpm verify          # green or red, on what changed and its dependents
main         = main
branch       = <type>/<scope>/<description>
types        = feature, fix, hotfix, refactor, test, docs, chore
commit       = <type>(<scope>): <summary>
commit_types = feat, fix, refactor, perf, test, docs, build, ci, chore
subject_max  = 72
integrate    = merge
rules        = CLAUDE.md, docs/adr/
backlog      = .workflow/backlog.md
```

Any key can be overridden for a session by `OVERLOAD_<KEY>`, even to empty: a cloud session without Docker sets `OVERLOAD_EXEC=`. The project's code conventions and lessons stay in its own CLAUDE.md files; the workflow's rules stay in the plugin.

## Files in a project

| File | Lives | Holds |
| --- | --- | --- |
| `.workflow/config` | main | the project's settings |
| `.workflow/backlog.md` | main | the items the human approved at a checkpoint |
| `.workflow/metrics.jsonl` | main | one line per integrated task: rounds, verify runs, commits, files, tokens per role |
| `.workflow/journal.md` | the task's branch | phase, intent, candidates, open findings; dropped at the merge |
| `.git/overload/` | the clone | the verified tree and the log of verify runs |

## Measures

`plugins/workflow-overload/scripts/metrics.py` also reads the Claude Code transcripts of a project (`transcripts`) and the merges of its history (`git`), to compare a workflow with the one before it. Claude Code deletes transcripts after 30 days: set `"cleanupPeriodDays"` in `~/.claude/settings.json` to keep them.

## Development

See [CLAUDE.md](CLAUDE.md). `tests/run.sh` tests the scripts, `python3 -m unittest discover -s tests` the measures.

## License

[MIT](LICENSE)
