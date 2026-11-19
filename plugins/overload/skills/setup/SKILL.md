---
name: setup
description: Configures a project for Workflow Overload by writing its .workflow/config. Runs only when the user types /overload:setup.
disable-model-invocation: true
argument-hint: "[guidance]"
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/status.sh), Bash(bash ${CLAUDE_PLUGIN_ROOT}/scripts/verify.sh:*)
---

# Workflow Overload: setup

Writes `.workflow/config`, the only place where this project differs from any other: an agent proposes it, the human settles it. Run on the main branch, with a clean tree. A short procedure, not a task: no branch, no journal, no review.

The user typed `/overload:setup $ARGUMENTS`: any text is their guidance for the setup (`take the commands from the Makefile`).

State of this project, read by a script as this skill loaded:

!`bash ${CLAUDE_PLUGIN_ROOT}/scripts/status.sh`

- Scripts: `${CLAUDE_PLUGIN_ROOT}/scripts/`, written `<scripts>` below. Run them from the project's root exactly as `bash ${CLAUDE_PLUGIN_ROOT}/scripts/<name> <arguments>`, unquoted and alone in the command.
- Talk to the human in their language; the config, the rule files and the commits follow the project's own conventions.

## A repository with no commit

The setup lays the workflow's skeleton, never the project's: language, framework, test runner and linter are decisions with alternatives, for the first task, with its review and decision records. So `check` and `run_tests` are written empty, and said so; the conventions for branches and commits are questions to the human, each with a proposal, since no history shows them. Before the first commit, point HEAD at the settled main, `git symbolic-ref HEAD refs/heads/<main>`: the commits of 5 are the repository's first. Skip 4, with nothing to measure. Once the task that brings the tools is merged, `/overload:setup` again measures `red_types` and confirms the values.

## 1. Propose

Run the `overload:setup-explorer` agent with the human's guidance, if any, and the scripts' folder. It reads the project and returns the proposal whole: a value for each key with its source and certainty, what it could not confirm of `check`, its questions, and the conventions the rule files lack, with the text to add. Do not read the files it read.

## 2. Settle

Show the human the proposal as it came. They answer the questions, counter-propose, accept or refuse each value and each text. Apply their answers yourself, reading a file at most to check one; never run the explorer again. Ask again only what their answers leave open.

## 3. Write and verify

On their acceptance, write `.workflow/config`: a `key = value` line for each key of the table, in its order, `check` even when empty (a config without it is refused); `red_types` waits for 4. A value never holds ` #`, which starts a comment: a command that needs one goes in a script of the project. Write a backlog file at `backlog` if there is none, holding only its heading, `# Backlog`: an empty file reads as a missing one. Write the accepted text in the rule files. An accepted folder of decision records: create it with its template, and add it to `rules`. Remove nothing the project already had.

Then run `bash <scripts>/verify.sh` on the main branch. It must be green: a red main makes every task red. A red goes to the human with its last lines; fix the config with them and run it again. No agent for one command. A session that cannot reach the project's container sets `OVERLOAD_CHECK` and `OVERLOAD_RUN_TESTS` to commands that run without it; the config keeps the project's.

## 4. Measure `red_types`

With `run_tests` set, run the `overload:setup-red-probe` agent with the config's `run_tests` and `tests_glob`, and the scripts' folder. It runs three throwaway tests twice and deletes them. Write the `red_types` it returns. When it finds the measure unreliable, set `run_tests` empty instead and give the human its diagnosis: the red check is then skipped, and logged as such. Change nothing else on its word.

## 5. Commit

Show the human the final config, verify's result and the probe's, in a few lines. On their go, commit on the main branch, each subject as the project's rules say, or else in the imperative and at most 72 characters; when one of its hooks refuses a message, change the message, never bypass the hook:

1. the text added to the rule files and the folder of decision records, in a commit of its own;
2. the config and the backlog file, in one commit (`chore: adopt workflow overload`, or the project's equivalent; on a later run, `chore: update the workflow config`). Nothing else goes in it.
