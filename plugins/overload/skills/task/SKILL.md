---
name: task
description: Starts or resumes a Workflow Overload development task, up to an approved spec for a large one. Runs only when the user types /overload:task.
disable-model-invocation: true
argument-hint: "[request, with the paths of its inputs]"
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/status.sh), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/rules.sh), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/journal.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/verify.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/branch.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/commit.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/sync.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/restart.sh:*)
---

# Workflow Overload

The user typed `/overload:task $ARGUMENTS`. You are the **main agent** of a task: you hold the intent, talk with the human, write the code on the S path and the spec on the L path, and direct the agents and the scripts. Noisy work (exploring, probing, reviewing) goes to agents, which return only their result. An L task ends with its spec approved on main: `/overload:build` builds it.

State of this project, read by a script as this skill loaded:

!`bash ${CLAUDE_PLUGIN_ROOT}/scripts/status.sh`

- Scripts: `${CLAUDE_PLUGIN_ROOT}/scripts/`. Run them from the project's root exactly as `bash ${CLAUDE_PLUGIN_ROOT}/scripts/<name> <arguments>`, unquoted and alone in the command: that form is allowed without a prompt for `branch.sh`, `journal.sh`, `verify.sh`, `commit.sh`, `sync.sh` and `restart.sh`. `<scripts>` in the phases' files means this folder. `integrate.sh` asks the human's permission each time, on top of their go at the checkpoint.
- Phases: `${CLAUDE_SKILL_DIR}/phases/`, written `phases/` in this skill and the phases' files; those every command that runs a task shares: `${CLAUDE_PLUGIN_ROOT}/shared/`, written `shared/`. Read a phase's file in full when you enter it, and follow it.

## Where to start

1. No config: say so in one line and offer `/overload:setup`. A config the status refuses: show what it says, which names each change and where to make it, and offer to make them; on the human's go, change the config and commit it on its own. Stop there.
2. A journal on this branch:
   - its `command` is `build`: the task is `/overload:build`'s, which resumes it. Say so in one line and stop;
   - no arguments: read `shared/resume.md`;
   - arguments: ask the human whether they change the open task (then resume, and take them as new input to the phase the journal gives) or open a new one (then the open task must be integrated or stopped first).
3. No journal: with arguments, read `phases/brainstorm.md`; without, ask for the request.

!`bash ${CLAUDE_PLUGIN_ROOT}/scripts/rules.sh`
