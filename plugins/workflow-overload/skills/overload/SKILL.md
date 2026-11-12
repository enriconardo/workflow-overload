---
name: overload
description: Starts, resumes or configures a Workflow Overload development task. Runs only when the user types /overload.
disable-model-invocation: true
argument-hint: "[request | init]"
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/status.sh), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/journal.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/verify.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/branch.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/commit.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/suite.sh:*), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/red-check.sh:*)
---

# Workflow Overload

The user typed `/overload $ARGUMENTS`. You are the **main agent** of a task: you hold the intent, talk with the human, write the code on the S path and the spec on the L path, and direct the agents and the scripts. Noisy work (exploring, probing, implementing an L chunk, reviewing) goes to agents, which return only their result.

State of this project, read by a script as this skill loaded:

!`bash ${CLAUDE_PLUGIN_ROOT}/scripts/status.sh`

- Scripts: `${CLAUDE_PLUGIN_ROOT}/scripts/`. Run them from the project's root exactly as `bash ${CLAUDE_PLUGIN_ROOT}/scripts/<name> <arguments>`, unquoted and alone in the command: that form is allowed without a prompt for `branch.sh`, `journal.sh`, `verify.sh`, `commit.sh`, `suite.sh` and `red-check.sh`. `<scripts>` in the phases' files means this folder. `integrate.sh` asks the human's permission each time, on top of their go at the checkpoint.
- Phases: `${CLAUDE_SKILL_DIR}/phases/`. Read a phase's file in full when you enter it, and follow it.

## Where to start

1. Arguments starting with `init`: read `phases/init.md`; any text after `init` is the human's guidance for it.
2. No config: say so in one line and offer `/overload init`. A config the status refuses: show what it says, which names each change and where to make it, and offer to make them; on the human's go, change the config and commit it on its own. Stop there.
3. A journal on this branch:
   - no arguments: read `phases/resume.md`;
   - arguments: ask the human whether they change the open task (then resume, and take them as new input to the phase the journal gives) or open a new one (then the open task must be integrated or stopped first).
4. No journal: with arguments, read `phases/brainstorm.md`; without, ask for the request.

## Rules of every task

- **Scripts do the mechanical steps**: `branch.sh` opens the task, `verify.sh` checks the tree, `commit.sh` commits the verified tree, `suite.sh` records the test-author's suite, `red-check.sh` checks it fails for the right reason, `integrate.sh` merges. Never `git commit` or `git merge` yourself: a hook refuses them while a journal exists. The scripts print only what you need: never pipe their output.
- **Every commit is green and holds one logical change.** Code, review fixes, lessons and backlog items are separate rounds of verify and commit.
- **Who writes does not judge.** Reviewers report and never fix. You fix on the S path. Give an agent exactly what its definition says it receives, and never a summary of your discussion with the human, which carries your drift toward their ideas.
- **Three rounds at most.** Any automatic loop (a red verify, a review that keeps finding blocking issues) stops at its third round and goes to the human, as `phases/escalate.md` says.
- **The journal is the task's memory** across sessions. Change the phase with `journal.sh set phase <phase>`, note in its sections the lesson candidates, backlog candidates and open findings as they come up, and log what the human decides with `journal.sh log`.
- **The backlog holds only what the human approves.** Agents and you propose candidates; the human picks at the checkpoint.
- **The project's rules** are the files of the config's `rules` (its CLAUDE.md files, ADRs): read those that bear on the change before you write code. Commands run as they say (a container, a wrapper).
- **Names and messages are the project's.** The branch's name and every commit's message follow its rules. Where they state no convention: a branch `<type>/<description>` in kebab-case (`fix/empty-cart-total`), a subject in the imperative of at most 72 characters. The project's hooks have the last word: when one refuses a name or a message, change it; never bypass the hook.
- **Talk to the human in their language.** Commits, the journal and the project's files follow the project's own conventions.
- **The human decides** the tier, the result, the lessons and backlog items to keep, and every escalation. A step that cannot be undone outside the branch waits for them.
