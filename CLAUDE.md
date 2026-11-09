# workflow-overload

The Claude Code plugin `overload` and its marketplace. Public: no reference to private projects, people or clients, in code, docs, tests or commits.

## Layout

```
.claude-plugin/marketplace.json   the marketplace: one plugin, ./plugins/overload
plugins/overload/                 what an install copies
  .claude-plugin/plugin.json      name, version
  skills/overload/SKILL.md        the only entry: /overload, disable-model-invocation
  skills/overload/phases/         one file per phase, read by the entry skill
  agents/                         the agents, all internal to /overload
  hooks/hooks.json                hooks, silent without a journal
  scripts/                        bash for the steps, python3 for parsing
tests/                            tests of the scripts, outside the install
docs/                             design and probes
```

## Rules of the plugin

- **The workflow starts only with `/overload`.** Never a second skill (the model could load it on its own), never an agent whose description invites delegation, never a hook that acts on a branch without `.workflow/journal.md`.
- **A script finds its files from `BASH_SOURCE`**: the model's Bash has no `CLAUDE_PLUGIN_ROOT`. Only the skill's text gets `${CLAUDE_PLUGIN_ROOT}` and `${CLAUDE_SKILL_DIR}` substituted.
- **Scripts need only bash, git and python3** (3.8+, standard library): no `jq`, no Node, no package to install. A script's output is short enough that the model never pipes it.
- **Project specifics live in `.workflow/config`**, read by `lib.sh`'s `config_get` without evaluation; each key has a default there or a refusal. A new key goes in `lib.sh`, `status.sh`, `phases/init.md` and the README's *Configuration*.
- **Phases and agents are instructions to a model**: imperative, short, one place per rule. A rule both the skill and an agent need lives in the agent, and the skill passes the inputs the agent's *Input* lists.

## Checks

```
shellcheck -x plugins/overload/scripts/*.sh tests/*.sh
tests/run.sh
python3 -m unittest discover -s tests
claude plugin validate .
```

CI runs them on every push. A change to a script starts with a test in `tests/scripts.test.sh` that fails without it.

## Branches and commits

- Branch: `<type>/<scope>/<description>`, types `feature, fix, refactor, test, docs, chore`, scope `scripts`, `skill`, `agents`, `hooks`, `metrics` or `repo`.
- Commit: `<type>(<scope>): <summary>`, imperative, lowercase, at most 72 characters; a body when the why is not obvious.
- Integration by pull request to `main`. A release bumps `version` in `plugin.json`.
