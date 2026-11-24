# Acceptance

The plan's acceptance: once every item is ticked, the human runs each step of its *Acceptance* on the code the items built, and you record what they see. It is where a person judges what no test does, and where the real environment shows what the tests' did not. A failure the triage would call S is fixed here; a larger one stays failed, and its items come from a revision of the plan after this merge.

## 1. Run the steps — phase `a/run`

1. Read the plan in full: its requirements, decisions and steps. Every step runs, from the first, whatever mark an earlier acceptance left on it.
2. Give the human the steps in one message, in order, each as they will do it on this project: its preconditions, the exact action (a command, a URL, a click), and the result to expect, with the requirements it checks. A step that names a version names an item's merge: `bash <scripts>/plan.sh merge <plan> <n>` prints it; never take a commit from memory or from a log you read. Prepare what a step needs and the human cannot (a database of an earlier version, a seed), and say how to start and stop what it runs.
3. Log each outcome as the human reports it, in their words: `journal.sh log "acceptance step <k>: passed"`, or `journal.sh log "acceptance step <k>: failed: <what they saw>"`. The log is where the outcomes live until 3: write nothing in the plan yet.

## 2. A step that fails

Settle its size with the human, by the criteria of S in the triage (`/overload:task`'s brainstorming): the tier is theirs.

- **S**: fix it here, as the S path does. A test that reproduces it first, red before the fix, failing with the step's symptom; then the fix, `bash <scripts>/verify.sh`, and a commit of its own (`commit.sh`), its message naming the step. Then the human runs the step again, and you log the new outcome. Three rounds on one step without a pass go to `shared/escalate.md`. Note under *Lesson candidates* what should have caught the failure before the acceptance: a test that was missing, a review that missed it.
- **Larger**, or a fix that would change a requirement or a decision: it stays failed, with what the human saw. Note it for the checkpoint: after this merge, `/overload:task <plan> <the change>` revises the plan with the items it calls for, and `/overload:build <plan>` then runs every step again.

The steps after it still run, unless the human says it blocks them: then they stay failed too, each with the step that blocks it as what failed.

## 3. Commit the outcome

When every step has its outcome, write them all in the plan, from the log: a passed step ticked (`- [x]`); a failed one unticked, ending in ` — failed: <what>`; the marks of an earlier acceptance replaced. Set `status: done` when every step passed; otherwise it stays `approved`. Change nothing else of the plan: its items are the revision's.

`bash <scripts>/plan.sh check <plan>`, `bash <scripts>/verify.sh`, then commit the plan alone, after every fix. The commit moves the phase to `close/check`: go on with `shared/close.md` from 1. An acceptance with fixes has the whole close, the final review on the fixes included; one without runs `check_integrate` and goes from it to the lessons, with no code to review.
