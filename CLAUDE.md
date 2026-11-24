# workflow-overload

The Claude Code plugin `overload` and its marketplace `workflow-overload`. Its commands are `/overload:task`, `/overload:build` and `/overload:setup`; agents are `overload:<name>`. Public: no reference to private projects, people or clients, in code, docs, tests or commits.

## Layout

```
.claude-plugin/marketplace.json   the marketplace: one plugin, ./plugins/overload
plugins/overload/                 what an install copies
  .claude-plugin/plugin.json      name, version
  skills/task/SKILL.md            /overload:task, opens or resumes a task: an S, an L's spec, a plan or its items
  skills/task/phases/             the task skill's own phases, one file each
  skills/build/SKILL.md           /overload:build, builds a spec approved on main, or runs a plan's acceptance
  skills/build/phases/            the build skill's own phases
  skills/setup/SKILL.md           /overload:setup, writes .workflow/config
  shared/                         the rules and phases every task command shares
  agents/                         the agents, all internal to the skills
  hooks/hooks.json                hooks, silent without a journal
  scripts/                        bash for the steps, python3 for parsing
tests/                            tests of the scripts, outside the install
docs/                             design and probes
```

## Rules of the plugin

- **The workflow starts only with `/overload:task` or `/overload:build`.** Every skill has `disable-model-invocation: true` (without it the model could load one on its own); only `task` opens a task from a request, `build` only from a spec approved on main or a plan whose items are all ticked, and `setup` opens none; never an agent whose description invites delegation, never a hook that acts on a branch without `.workflow/journal.md`.
- **A script finds its files from `BASH_SOURCE`**: the model's Bash has no `CLAUDE_PLUGIN_ROOT`. Only the skill's text gets `${CLAUDE_PLUGIN_ROOT}` and `${CLAUDE_SKILL_DIR}` substituted.
- **Scripts need only bash, git and python3** (3.8+, standard library): no `jq`, no Node, no package to install. A script's output is short enough that the model never pipes it.
- **Project specifics live in `.workflow/config`**, read by `lib.sh`'s `config_get` without evaluation; each key has a default there or a refusal. A new key goes in `lib.sh`'s `CONFIG_KEYS` (its default in `config_default`), the key list of `agents/setup-explorer.md` with what makes a good value, and the README's *Configuration*; a test refuses a phase or an agent that names a key `lib.sh` does not know.
- **Phases and agents are instructions to a model**: imperative, short, one place per rule. A rule both a skill and an agent need lives in the agent, and the skill passes the inputs the agent's *Input* lists.

## Checks

```
shellcheck -x plugins/overload/scripts/*.sh tests/*.sh
tests/run.sh
python3 -m unittest discover -s tests
claude plugin validate .
```

CI runs them on every push. A change to a script starts with a test in `tests/scripts.test.sh` that fails without it.

## Branches and commits

- Branch: `<type>/<scope>/<description>`, types `feature, fix, refactor, test, docs, chore`, scope `scripts`, `skill`, `agents`, `hooks` or `repo`.
- Commit: `[<scope>] <type>: <summary>`, the scope as for branches, the type one of `feat, fix, refactor, perf, test, docs, build, ci, chore`; summary imperative, lowercase, no trailing period, at most 72 characters in all; a body when the why is not obvious.
- Integration by local merge to `main` (`git merge --no-ff`), a personal project with no pull requests. When the work is done, stop for a checkpoint with the owner before merging; on their go-ahead, merge and delete the feature branch, without pushing; without it, the work is discussed again. A release bumps `version` in `plugin.json`.
