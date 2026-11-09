# S path

For small changes: no spec, one reviewer, one checkpoint. The journal's *Intent* stands in for the spec and goes in the commit's body. `<scripts>` is the plugin's scripts folder of the skill.

## 1. Implement — phase `s/implement`

Write the change, following the project's rules. A bug fix starts with a test that reproduces the bug and fails with its symptom; run it red before the fix. A task that works an item of the backlog removes the item in a commit of its own; the backlog file stays, even empty.

## 2. Verify

`bash "<scripts>/verify.sh"`. Red: fix and run it again. The script counts the reds in a row; at the third it says to stop, and you go to `phases/escalate.md` (no *skip* on a red verify).

## 3. Commit

Write the message to a file outside the repository: a subject in the config's `commit` format, then a body with the intent (why the change, what it decides). `bash "<scripts>/commit.sh" <message-file>`. It refuses a tree that is not the verified one: verify again after any change.

## 4. Final review — phase `s/review`

Run the `workflow-overload:code-reviewer` agent with:

- the intent: the path of the journal, `.workflow/journal.md`, section *Intent*;
- the range: first round `<base>..HEAD`, with `base` from the journal; a later round, the previous findings and `<sha>..HEAD`, `sha` being the HEAD the previous round reviewed;
- the config's `rules`.

At every round, increment `review_rounds` in the journal and log the round with the HEAD it reviewed (`journal.sh log "review round <n> on <sha>: <k> blocking"`), which the next round and a resumed session start from. For each finding it reports:

- **blocking, one right answer**: fix it (a bug starts from a test that reproduces it), verify, commit the fixes on their own, then a new round on the new range;
- **blocking, needs judgment**: note it under *Open findings*, for the checkpoint;
- **not blocking**: under *Backlog candidates*, with its source (`code-reviewer`).

A round that still finds blocking issues after the third goes to `phases/escalate.md`. You may reject a finding: write why under *Open findings*, and the human sees it.

## 5. Lessons — phase `s/lessons`

Only for a problem of this task that could recur and costs more than its rule costs to read. Prefer a check, a script or a lint rule to written text; propose also to retire a rule of the area that proved useless. No proposal: skip to 6.

Write the proposals to a file outside the repository, one per lesson: its text as it would land, where it lands (file and section, or the check and what it refuses), and the evidence (a commit, a finding quoted as it came, a check's output, a `file:line`). Run the `workflow-overload:lesson-critic` agent with that path only. Apply the verdicts you accept; a `revise` or `drop` you reject keeps its reason.

## 6. Summary and checkpoint — phase `s/checkpoint`

One message to the human:

- what changes and why, in a few lines, and the diff's stat (`git diff --stat <base>..HEAD`);
- the last verify's result;
- the findings that need their judgment, and those you rejected, with the reason;
- the backlog candidates, each with its source;
- the lessons the critic kept, each with its verdict; a dropped one as a single line, so they can take it back.

Then stop and wait. The human gives the go and picks the lessons and backlog items to keep, or comes back with doubts: then you are in phase `s/implement` again, with their words logged.

## 7. Lessons and backlog — phase `s/close`

Write the approved lessons where they land, and the approved backlog items at the end of the config's `backlog` file (create it if missing), one item per entry: what, why, source. The rule, not its story: `git blame` gives the task and the date. Verify and commit the lessons on their own, then the backlog items on their own. A lesson that stays red goes to the human: retry, or skip, and the lesson leaves the task as a backlog item. Nothing approved: skip this step.

## 8. Integrate — phase `s/integrate`

`bash "<scripts>/integrate.sh"`. It merges with `--no-ff`, drops the journal, records the measures and deletes the branch. On a conflict or a red verify on the merge's result it leaves main as it was: go to `phases/escalate.md`. Then tell the human it is merged, in one line, with the merge's subject.
