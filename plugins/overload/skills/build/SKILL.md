---
name: build
description: Builds a spec that a Workflow Overload task approved. Runs only when the user types /overload:build.
disable-model-invocation: true
argument-hint: "<the path of a spec approved on main>"
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/status.sh), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/rules.sh), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/journal.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/verify.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/branch.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/commit.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/suite.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/red-check.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/sync.sh:*)
---

# Workflow Overload: build

The user typed `/overload:build $ARGUMENTS`. You are the **main agent** of a build: a spec that `/overload:task` wrote, its reviewer judged and the human approved, on main, becomes code on a branch of its own, chunk by chunk, then one merge. The spec is your intent: it carries the human's decisions in their words, and nothing else of the discussion that wrote it reaches you. You direct the agents, which write the tests and the code and review them, and the scripts.

State of this project, read by a script as this skill loaded:

!`bash ${CLAUDE_PLUGIN_ROOT}/scripts/status.sh`

- Scripts: `${CLAUDE_PLUGIN_ROOT}/scripts/`. Run them from the project's root exactly as `bash ${CLAUDE_PLUGIN_ROOT}/scripts/<name> <arguments>`, unquoted and alone in the command: that form is allowed without a prompt for `branch.sh`, `journal.sh`, `verify.sh`, `commit.sh`, `suite.sh`, `red-check.sh` and `sync.sh`. `<scripts>` in the phases' files means this folder. `integrate.sh` asks the human's permission each time, on top of their go at the checkpoint.
- Phases: `${CLAUDE_SKILL_DIR}/phases/`, written `phases/` in this skill and the phases' files; those every command that runs a task shares: `${CLAUDE_PLUGIN_ROOT}/shared/`, written `shared/`. Read a phase's file in full when you enter it, and follow it.

## Where to start

1. No config: say so in one line and offer `/overload:setup`. A config the status refuses: show what it says, which names each change and where to make it, and offer to make them; on the human's go, change the config and commit it on its own. Stop there.
2. A journal on this branch:
   - its `command` is not `build`: the task is `/overload:task`'s, which resumes it. Say so in one line and stop;
   - no arguments, or the journal's spec: read `shared/resume.md`;
   - another spec: the open build must be integrated or stopped first. Say so in one line and stop.
3. No journal: with a spec's path, open the build (below); without, show the human the specs to build that the status lists, choose none, and stop.

## Open the build

1. Read the spec in full: what it asks, its decisions, its chunks. Its `inputs` are the human's documents: the agents that need them read them.
2. `bash <scripts>/branch.sh --build <name> <spec>`, from main; the name follows *Names and messages* in the rules of every task. It refuses a spec that main does not hold approved with a chunk left to build. The journal names the spec and its approval, and its phase is that chunk's first step, or `l/expiry` when main changed the files the spec rests on since its approval. A spec of a plan's item (its `plan` and `item`) builds that item: the journal names both, the plan is among the files the expiry watches, and the script refuses while another item of the plan is open on a branch.
3. When it says main moved since the approval, none of the spec's files changed: tell the human in one line, with the dependencies the spec's *Decisions* name in words, which no script sees change.
4. Go on with `phases/l-chunk.md`, from *Expiry* on `l/expiry`.

!`bash ${CLAUDE_PLUGIN_ROOT}/scripts/rules.sh`
