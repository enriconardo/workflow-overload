---
name: task
description: Starts or resumes a Workflow Overload development task, up to an approved spec for a large one or a plan for one too large for a spec, the items of that plan, and the revision or drop of a plan or spec on main. Runs only when the user types /overload:task.
disable-model-invocation: true
argument-hint: "[request, with the paths of its inputs] | <plan> [<item> | <the change>] | <spec> <why drop it>"
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/status.sh), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/rules.sh), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/journal.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/verify.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/branch.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/commit.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/sync.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/restart.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/plan.sh:*)
---

# Workflow Overload

The user typed `/overload:task $ARGUMENTS`. You are the **main agent** of a task: you hold the intent, talk with the human, write the code on the S path and the spec on the L path, and direct the agents and the scripts. Noisy work (exploring, probing, reviewing) goes to agents, which return only their result. An L task ends with its spec approved on main: `/overload:build` builds it. A change too large for one spec ends with a plan approved on main, whose items are tasks of their own: `/overload:task <plan> <n>` opens item `n`. A plan or spec on main changes only through a task too: `/overload:task <plan> <the change>` revises or drops the plan, `/overload:task <spec> <why>` drops the spec.

State of this project, read by a script as this skill loaded:

!`bash ${CLAUDE_PLUGIN_ROOT}/scripts/status.sh`

- Scripts: `${CLAUDE_PLUGIN_ROOT}/scripts/`. Run them from the project's root exactly as `bash ${CLAUDE_PLUGIN_ROOT}/scripts/<name> <arguments>`, unquoted and alone in the command: that form is allowed without a prompt for `branch.sh`, `journal.sh`, `verify.sh`, `commit.sh`, `sync.sh`, `restart.sh` and `plan.sh`. `<scripts>` in the phases' files means this folder. `integrate.sh` asks the human's permission each time, on top of their go at the checkpoint.
- Phases: `${CLAUDE_SKILL_DIR}/phases/`, written `phases/` in this skill and the phases' files; those every command that runs a task shares: `${CLAUDE_PLUGIN_ROOT}/shared/`, written `shared/`. Read a phase's file in full when you enter it, and follow it.

## Where to start

1. No config: say so in one line and offer `/overload:setup`. A config the status refuses: show what it says, which names each change and where to make it, and offer to make them; on the human's go, change the config and commit it on its own. Stop there.
2. A journal on this branch:
   - its `command` is `build`: the task is `/overload:build`'s, which resumes it. Say so in one line and stop;
   - no arguments: read `shared/resume.md`;
   - arguments: ask the human whether they change the open task (then resume, and take them as new input to the phase the journal gives) or open a new one (then the open task must be integrated or stopped first).
3. No journal, and the first argument is a plan's path (`.workflow/plans/<name>.md`): it must be the open plan the status names; otherwise say which plan is open, if any, and stop. After the path:
   - an item's number: `bash <scripts>/plan.sh item <plan> <n>`. When it refuses, show why, with the next item the status gives, and stop; otherwise read `phases/brainstorm.md`, from *An item of the plan*;
   - nothing: show the next item and its command, as the status gives them, choose nothing, and stop;
   - anything else asks to revise or drop the plan: read `phases/change.md`.
4. No journal, and the first argument is a spec's path (`.workflow/specs/<name>.md`): what follows asks to drop it, the only change of a spec outside its build. It must be among the specs to build the status lists; otherwise say what it is (built, dropped, not on main) and stop. Then read `phases/change.md`.
5. No journal, other arguments: read `phases/brainstorm.md`. No arguments: ask for the request.

!`bash ${CLAUDE_PLUGIN_ROOT}/scripts/rules.sh`
