# Setup

Writes `.workflow/config`, the only place where this project differs from any other: an agent proposes it, the human settles it. Run on the main branch, with a clean tree. A short procedure, not a task: no branch, no journal, no review.

## 1. Propose

Run the `workflow-overload:setup-explorer` agent with the text after `setup`, the human's guidance, if any, and the scripts' folder. It reads the project and returns the proposal whole: a value for each key with its source and certainty, what it could not confirm of `check`, its questions, and the conventions the rule files lack, with the text to add. Do not read the files it read.

## 2. Settle

Show the human the proposal as it came. They answer the questions, counter-propose, accept or refuse each value and each text. Apply their answers yourself, reading a file at most to check one; never run the explorer again. Ask again only what their answers leave open.

## 3. Write and verify

On their acceptance, write `.workflow/config`: a `key = value` line for each key of the table, in its order, `check` even when empty (a config without it is refused); `red_types` waits for 4. A value never holds ` #`, which starts a comment: a command that needs one goes in a script of the project. Write an empty backlog file at `backlog` if there is none, and the accepted text in the rule files. Remove nothing the project already had.

Then run `bash <scripts>/verify.sh` on the main branch. It must be green: a red main makes every task red. A red goes to the human with its last lines; fix the config with them and run it again. No agent for one command. A session that cannot reach the project's container sets `OVERLOAD_CHECK` and `OVERLOAD_RUN_TESTS` to commands that run without it; the config keeps the project's.

## 4. Measure `red_types`

With `run_tests` set, run the `workflow-overload:setup-red-probe` agent with the config's `run_tests` and `tests_glob`, and the scripts' folder. It runs three throwaway tests twice and deletes them. Write the `red_types` it returns. When it finds the measure unreliable, set `run_tests` empty instead and give the human its diagnosis: the red check is then skipped, and logged as such. Change nothing else on its word.

## 5. Commit

Show the human the final config, verify's result and the probe's, in a few lines. On their go, commit on the main branch, each subject as *Names and messages* in the skill's rules says:

1. the text added to the rule files, in a commit of its own;
2. the config and the backlog file, in one commit (`chore: adopt workflow overload`, or the project's equivalent). Nothing else goes in it.
